//
//  LexerTextStorage.swift
//  Trill
//

import Foundation
#if os(iOS)
  import UIKit
#endif
#if os(macOS)
  import Cocoa
#endif

extension SourceRange {
  var nsRange: NSRange {
    let length = end.charOffset <= start.charOffset ? 0 : end.charOffset - start.charOffset
    return NSRange(location: start.charOffset, length: length)
  }
}

private let commentRegex = try! NSRegularExpression(pattern: "\\/\\/.*$", options: .anchorsMatchLines)
private let multilineCommentRegex = try! NSRegularExpression(pattern: "\\/\\*.*\\*\\/", options: .dotMatchesLineSeparators)
private let inProgressMultilineCommentRegex = try! NSRegularExpression(pattern: "\\/\\*([^\\*\\/]|\\*)*", options: .dotMatchesLineSeparators)

class LexerTextStorage: NSTextStorage {
  let attributes: TextAttributes
  let filename: String
  let storage: NSMutableAttributedString
  
  init(attributes: TextAttributes, filename: String, initialContents: String = "") {
    self.attributes = attributes
    self.filename = filename
    self.storage = NSMutableAttributedString(string: initialContents)
    super.init()
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  #if os(macOS)
  required init?(pasteboardPropertyList propertyList: AnyObject, ofType type: String) {
    fatalError("init(pasteboardPropertyList:ofType:) has not been implemented")
  }
  #endif
  
  override var string: String {
    return storage.string
  }
  
  override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [String : Any] {
    return storage.attributes(at: location, effectiveRange: range)
  }
  
  override func replaceCharacters(in range: NSRange, with attrString: NSAttributedString) {
    beginEditing()
    storage.replaceCharacters(in: range, with: attrString.string)
    edited(.editedCharacters, range: range, changeInLength: attrString.length - range.length)
    endEditing()
  }
  
  override func replaceCharacters(in range: NSRange, with str: String) {
    replaceCharacters(in: range, with: NSAttributedString(string: str))
  }
  
  override func append(_ attrString: NSAttributedString) {
    beginEditing()
    let loc = storage.length
    storage.append(attrString)
    edited(.editedCharacters, range: NSRange(location: loc, length: 0), changeInLength: attrString.length)
    endEditing()
  }
  
  override func setAttributes(_ attrs: [String : Any]?, range: NSRange) {
    beginEditing()
    storage.setAttributes(attrs, range: range)
    edited(.editedAttributes, range: range, changeInLength: 0)
    endEditing()
  }
  
  override func processEditing() {
    var lexer = Lexer(filename: self.filename, input: string)
    let tokens = (try? lexer.lex()) ?? []
    
    let fullRange =  NSRange(location: 0, length: storage.length)
    removeAttribute(NSForegroundColorAttributeName, range: fullRange)
    removeAttribute(NSUnderlineStyleAttributeName, range: fullRange)
    addAttribute(NSUnderlineStyleAttributeName,
                 value: NSUnderlineStyle.styleNone.rawValue,
                 range: fullRange)
    addAttribute(NSFontAttributeName,
                 value: attributes.font,
                 range: fullRange)
    addAttribute(NSForegroundColorAttributeName,
                 value: attributes.normal.color,
                 range: fullRange)
    for token in tokens  {
      if token.isKeyword {
        addAttribute(NSForegroundColorAttributeName,
                     value: attributes.keyword.color,
                     range: token.range.nsRange)
      } else if token.isLiteral {
        addAttribute(NSForegroundColorAttributeName,
                     value: attributes.literal.color,
                     range: token.range.nsRange)
      } else if token.isString {
        addAttribute(NSForegroundColorAttributeName,
                     value: attributes.string.color,
                     range: token.range.nsRange)
      } else if !token.isEOF {
        addAttribute(NSForegroundColorAttributeName,
                     value: attributes.normal.color,
                     range: token.range.nsRange)
      }
    }
    
    let diag = DiagnosticEngine()
    let context = ASTContext(diagnosticEngine: diag)
    let annotator = SourceAnnotator(attributes: self.attributes,
                                    context: context)
    diag.register(annotator)
    let driver = Driver(context: context)
    driver.add("Parser") { context in
      let parser = Parser(tokens: tokens, filename: self.filename, context: context)
      do {
        try parser.parseTopLevel(into: context)
      } catch let error as Diagnostic {
        diag.add(error)
      } catch {
        diag.error("\(error)")
      }
    }
    driver.add(pass: PopulateJSDecls.self)
    driver.add(pass: Sema.self)
    driver.add(pass: TypeChecker.self)
    driver.add("Source Annotation") { context in
      _ = annotator.run(in: context)
      for attr in annotator.sourceAttributes {
        self.addAttribute(attr.name, value: attr.value, range: attr.range)
      }
    }
    driver.run(in: context)
    diag.consumeDiagnostics()
    for attr in annotator.errorAttributes {
      self.addAttribute(attr.name, value: attr.value, range: attr.range)
    }
    
    for r in [commentRegex, multilineCommentRegex, inProgressMultilineCommentRegex] {
      r.enumerateMatches(in: string, options: [], range: fullRange) { result, _, _ in
        self.addAttribute(NSForegroundColorAttributeName, value: self.attributes.comment.color, range: result!.range)
      }
    }
    super.processEditing()
  }
}
