//
//  SourceAnnotator.swift
//  Trill
//

import Foundation
#if os(iOS)
  import UIKit
  typealias Font = UIFont
  typealias Color = UIColor
#endif

#if os(macOS)
  import Cocoa
  typealias Font = NSFont
  typealias Color = NSColor
#endif


struct TextAttributes {
  let font: Font
  let boldFont: Font
  let keyword: TextStyle
  let literal: TextStyle
  let normal: TextStyle
  let comment: TextStyle
  let string: TextStyle
  let internalName: TextStyle
  let externalName: TextStyle
}

struct TextStyle {
  let bold: Bool
  let color: Color
}

struct Attribute {
  let name: String
  let value: Any
  let range: NSRange
}

class SourceAnnotator: ASTTransformer, DiagnosticConsumer {
  let attributes: TextAttributes
  
  init(attributes: TextAttributes, context: ASTContext) {
    self.attributes = attributes
    super.init(context: context)
  }
  
  required init(context: ASTContext) {
    fatalError("init(context:) has not been implemented")
  }
  
  func add(style: TextStyle, range: NSRange) {
    sourceAttributes.append(Attribute(name: NSForegroundColorAttributeName,
                                      value: style.color,
                                      range: range))
    
    if style.bold {
      sourceAttributes.append(Attribute(name: NSFontAttributeName,
                                        value: attributes.boldFont,
                                        range: range))
    }
  }
  
  func add(_ attributes: [Attribute]) {
    sourceAttributes.append(contentsOf: attributes)
  }
  
  func attributes(for typeRef: TypeRefExpr) -> [Attribute] {
    var attrs = [Attribute]()
    if let funcRef = typeRef as? FuncTypeRefExpr {
      for type in funcRef.argNames {
        attrs += attributes(for: type)
      }
      attrs += attributes(for: funcRef.retName)
    } else if let pointerRef = typeRef as? PointerTypeRefExpr {
      attrs += attributes(for: pointerRef.pointed)
    } else if let tupleRef = typeRef as? TupleTypeRefExpr {
      for type in tupleRef.fieldNames {
        attrs += attributes(for: type)
      }
    } else {
      if let type = typeRef.type, let range = typeRef.sourceRange?.nsRange {
        add(style: style(for: type), range: range)
      }
    }
    return attrs
  }
  
  var sourceAttributes = [Attribute]()
  var errorAttributes = [Attribute]()
  
  func style(for type: DataType) -> TextStyle {
    if case .any = type {
      return attributes.keyword
    }
    return context.isIntrinsic(type: type) ? attributes.externalName : attributes.internalName
  }
  
  override func visitStringExpr(_ expr: StringExpr) {
    if let range = expr.sourceRange?.nsRange {
      add(style: expr is PoundFileExpr ? attributes.keyword : attributes.string,
          range: range)
    }
    super.visitStringExpr(expr)
  }
  
  override func visitPropertyRefExpr(_ expr: PropertyRefExpr) {
    guard let decl = expr.decl else { return }
    if let range =  expr.name.range?.nsRange {
      let style = context.isIntrinsic(decl: decl) ? attributes.externalName : attributes.internalName
      add(style: style, range: range)
    }
    super.visitPropertyRefExpr(expr)
  }
  
  override func visitParamDecl(_ decl: ParamDecl) {
    add(attributes(for: decl.typeRef!))
    super.visitParamDecl(decl)
  }
  
  override func visitFuncDecl(_ decl: FuncDecl) {
    add(attributes(for: decl.returnType))
    super.visitFuncDecl(decl)
  }
  
  override func visitVarAssignDecl(_ decl: VarAssignDecl) {
    add(attributes(for: decl.typeRef!))
    super.visitVarAssignDecl(decl)
  }
  
  override func visitExtensionDecl(_ expr: ExtensionDecl) {
    add(attributes(for: expr.typeRef))
    super.visitExtensionDecl(expr)
  }
  
  override func visitTypeDecl(_ expr: TypeDecl) {
    let ref = TypeRefExpr(type: expr.type, name: expr.name)
    add(attributes(for: ref))
    super.visitTypeDecl(expr)
  }
  
  override func visitTypeAliasDecl(_ decl: TypeAliasDecl) {
    add(attributes(for: decl.bound))
    super.visitTypeAliasDecl(decl)
  }
  
  override func visitClosureExpr(_ expr: ClosureExpr) {
    add(attributes(for: expr.returnType))
    super.visitClosureExpr(expr)
  }
    
  override func visitSubscriptExpr(_ expr: SubscriptExpr) {
    visitFuncCallExpr(expr)
  }
  
  override func visitVarExpr(_ expr: VarExpr) {
    super.visitVarExpr(expr)
    guard let decl = expr.decl else { return }
    guard let range = expr.sourceRange?.nsRange else { return }
    if expr.isTypeVar {
      let type = DataType(name: expr.name.name)
      let typeStyle = self.style(for: type)
      add(style: typeStyle, range: range)
      return
    }
    let kind = (decl as? VarAssignDecl)?.kind ?? .global
    var style = attributes.normal
    switch kind {
    case .local:
      break
    case .global:
      style = attributes.internalName
    case .implicitSelf:
      style = attributes.keyword
    case .property:
      style = attributes.internalName
    }
    if decl.has(attribute: .foreign) {
      style = attributes.externalName
    }
    add(style: style, range: range)
  }
  
  override func run(in context: ASTContext) {
    super.run(in: context)
  }
  
  func consume(_ diagnostic: Diagnostic) {
    for r in diagnostic.highlights {
      let range = r.nsRange
      let color = diagnostic.diagnosticType == .warning ?
        Color(red: 1.0, green: 221.0/255.0, blue: 0, alpha: 1.0) :
        Color(red: 222.0/255.0, green: 7.0/255.0, blue: 7.0/255.0, alpha: 1.0)
      let style = NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.styleSingle.rawValue
      errorAttributes.append(Attribute(name: NSUnderlineColorAttributeName, value: color, range: range))
      errorAttributes.append(Attribute(name: NSUnderlineStyleAttributeName, value: style, range: range))
    }
  }
}
