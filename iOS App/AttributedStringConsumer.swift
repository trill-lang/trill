//
//  AttributedStringConsumer.swift
//  Trill
//

import UIKit

class AttributedStringConsumer: DiagnosticConsumer {
  let file: SourceFile
  var palette: TextAttributes
  private var builder = NSMutableAttributedString()
  static let font = UIFont(name: "Menlo", size: 14.0)!
  static let boldFont = UIFont(name: "Menlo-Bold", size: 14.0)!
  
  init(file: SourceFile, palette: TextAttributes) {
    self.file = file
    self.palette = palette
  }
  
  var attributedString: NSAttributedString {
    return NSAttributedString(attributedString: builder)
  }
  
  func bold(_ s: String, _ color: UIColor = .white) {
    let attrs = [
      NSFontAttributeName: AttributedStringConsumer.boldFont,
      NSForegroundColorAttributeName: color
    ]
    let attrString = NSAttributedString(string: s, attributes: attrs)
    builder.append(attrString)
  }
  func string(_ s: String, _ color: UIColor = .white) {
    let attrs = [
      NSFontAttributeName: AttributedStringConsumer.font,
      NSForegroundColorAttributeName: color
    ]
    let attrString = NSAttributedString(string: s, attributes: attrs)
    builder.append(attrString)
  }
  func lexString(_ s: String) {
    let lexer = Lexer(filename: file.path.filename, input: s)
    let str = NSMutableAttributedString(string: s)
    let stringRange = NSRange(location: 0, length: str.length)
    str.addAttribute(NSFontAttributeName, value: AttributedStringConsumer.font, range: stringRange)
    str.addAttribute(NSForegroundColorAttributeName, value: palette.normal, range: stringRange)
    for token in (try? lexer.lex()) ?? [] {
      if token.isKeyword {
        str.addAttribute(NSForegroundColorAttributeName, value: palette.keyword, range: token.range.nsRange)
      } else if token.isLiteral {
        str.addAttribute(NSForegroundColorAttributeName, value: palette.literal, range: token.range.nsRange)
      } else if token.isString {
        str.addAttribute(NSForegroundColorAttributeName, value: palette.string, range: token.range.nsRange)
      } else if !token.isEOF {
        str.addAttribute(NSForegroundColorAttributeName, value: palette.normal, range: token.range.nsRange)
      }
    }
    builder.append(str)
  }
  
  func highlightString(forDiag diag: Diagnostic) -> String {
    guard let loc = diag.loc, loc.line > 0 && loc.column > 0 else { return "" }
    var s = [Character]()
    if !diag.highlights.isEmpty {
      let ranges = diag.highlights.sorted { $0.start.charOffset < $1.start.charOffset }
      s = [Character](repeating: " ", count: ranges.last!.end.column)
      for r in ranges {
        let range = (r.start.column - 1)..<(r.end.column - 1)
        let tildes = [Character](repeating: "~", count: range.count)
        s.replaceSubrange(Range(range), with: tildes)
      }
    }
    let index = loc.column - 1
    if index >= s.endIndex {
      s += [Character](repeating: " ", count: s.distance(from: s.endIndex, to: index))
      s.append("^")
    } else {
      s[index] = "^" as Character
    }
    return String(s)
  }
  
  func consume(_ diagnostic: Diagnostic) {
    if let sourceLoc = diagnostic.loc {
      bold("\(file.path.basename):\(sourceLoc.line):\(sourceLoc.column): ")
    }
    switch diagnostic.diagnosticType {
    case .warning:
      bold("warning: ", .magenta)
    case .error:
      bold("error: ", .red)
    }
    bold("\(diagnostic.message)\n")
    if let loc = diagnostic.loc, loc.line > 0 {
      let line = file.lines[loc.line - 1]
      lexString(line)
      string("\n")
      string(highlightString(forDiag: diagnostic), .green)
      string("\n")
    }
  }
}
