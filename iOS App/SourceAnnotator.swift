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
  let keyword: Color
  let literal: Color
  let normal: Color
  let comment: Color
  let string: Color
  let internalName: Color
  let externalName: Color
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
  
  func add(color: Color, range: NSRange) {
    sourceAttributes.append(Attribute(name: NSForegroundColorAttributeName, value: color, range: range))
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
        let color = self.color(for: type)
        attrs.append(Attribute(name: NSForegroundColorAttributeName, value: color, range: range))
      }
    }
    return attrs
  }
  
  var sourceAttributes = [Attribute]()
  var errorAttributes = [Attribute]()
  
  override func visitFuncCallExpr(_ expr: FuncCallExpr) {
    super.visitFuncCallExpr(expr)
    let decl = expr.decl!
    let color: Color
    if case .initializer(let type) = decl.kind {
      color = self.color(for: type)
    } else {
      color = decl.sourceRange == nil ? attributes.externalName : attributes.internalName
    }
    switch expr.lhs {
    case let lhs as VarExpr:
      if let range = lhs.sourceRange?.nsRange {
        add(color: color, range: range)
      }
    case let lhs as FieldLookupExpr:
      if let range = lhs.name.range?.nsRange {
        add(color: color, range: range)
      }
    default:
      visit(expr.lhs)
    }
  }
  
  func color(for type: DataType) -> Color {
    return context.isIntrinsic(type: type) ? attributes.externalName : attributes.internalName
  }
  
  override func visitStringExpr(_ expr: StringExpr) {
    if let range = expr.sourceRange?.nsRange {
      add(color: attributes.string, range: range)
    }
    super.visitStringExpr(expr)
  }
  
  override func visitFieldLookupExpr(_ expr: FieldLookupExpr) {
    guard let decl = expr.decl else {
      return
    }
    if let range =  expr.name.range?.nsRange, let decl = decl as? Decl {
      let color = context.isIntrinsic(decl: decl) ? attributes.externalName : attributes.internalName
      add(color: color, range: range)
    }
    super.visitFieldLookupExpr(expr)
  }
  
  override func visitFuncArgumentAssignDecl(_ decl: FuncArgumentAssignDecl) {

    add(attributes(for: decl.typeRef!))
    super.visitFuncArgumentAssignDecl(decl)
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
