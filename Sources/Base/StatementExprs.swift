//
//  Statement.swift
//  Trill
//

import Foundation

class VarAssignExpr: DeclExpr {
  let rhs: ValExpr?
  var typeRef: TypeRefExpr?
  var containingTypeDecl: TypeDeclExpr?
  var mutable: Bool
  init(name: Identifier, typeRef: TypeRefExpr?, rhs: ValExpr? = nil, containingTypeDecl: TypeDeclExpr? = nil, attributes: [DeclAttribute] = [], mutable: Bool = true, sourceRange: SourceRange? = nil) {
    precondition(rhs != nil || typeRef != nil)
    self.rhs = rhs
    self.typeRef = typeRef
    self.mutable = mutable
    self.containingTypeDecl = containingTypeDecl
    super.init(name: name, type: typeRef?.type ?? .void, attributes: attributes, sourceRange: sourceRange)
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? VarAssignExpr else { return false }
    guard name == expr.name else { return false }
    guard type == expr.type else { return false }
    guard rhs == expr.rhs else { return false }
    return true
  }
}

class CompoundExpr: Expr {
  let exprs: [Expr]
  var hasReturn = false
  init(exprs: [Expr], sourceRange: SourceRange? = nil) {
    self.exprs = exprs
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? CompoundExpr else { return false }
    return exprs == expr.exprs
  }
}

class BranchExpr: Expr {
  let condition: ValExpr
  let body: CompoundExpr
  init(condition: ValExpr, body: CompoundExpr, sourceRange: SourceRange? = nil) {
    self.condition = condition
    self.body = body
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? BranchExpr else { return false }
    return condition == expr.condition && body == expr.body
  }
}

class IfExpr: Expr {
  let blocks: [(ValExpr, CompoundExpr)]
  let elseBody: CompoundExpr?
  init(blocks: [(ValExpr, CompoundExpr)], elseBody: CompoundExpr?, sourceRange: SourceRange? = nil) {
    self.blocks = blocks
    self.elseBody = elseBody
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? IfExpr else { return false }
    guard blocks.count == expr.blocks.count else { return false }
    guard elseBody == expr.elseBody else { return false }
    for (block, otherBlock) in zip(blocks, expr.blocks) {
      if block.0 != otherBlock.0 { return false }
      if block.1 != otherBlock.1 { return false }
    }
    return true
  }
}

class WhileExpr: BranchExpr {}

class ForLoopExpr: Expr {
  let initializer: Expr?
  let condition: ValExpr?
  let incrementer: Expr?
  let body: CompoundExpr
  init(initializer: Expr?, condition: ValExpr?, incrementer: Expr?, body: CompoundExpr, sourceRange: SourceRange? = nil) {
    self.initializer = initializer
    self.condition = condition
    self.incrementer = incrementer
    self.body = body
    super.init(sourceRange: sourceRange)
  }
}

class SwitchExpr: Expr {
  let value: ValExpr
  let cases: [CaseExpr]
  let defaultBody: CompoundExpr?
  init(value: ValExpr, cases: [CaseExpr], defaultBody: CompoundExpr? = nil, sourceRange: SourceRange? = nil) {
    self.value = value
    self.cases = cases
    self.defaultBody = defaultBody
    super.init(sourceRange: sourceRange)
  }
}

class CaseExpr: Expr {
  let constant: ConstantExpr
  let body: CompoundExpr
  init(constant: ConstantExpr, body: CompoundExpr, sourceRange: SourceRange? = nil) {
    self.constant = constant
    self.body = body
    super.init(sourceRange: sourceRange)
  }
}

class BreakExpr: Expr {
  override func equals(_ expr: Expr) -> Bool {
    return expr is BreakExpr
  }
}

class ContinueExpr: Expr {
  override func equals(_ expr: Expr) -> Bool {
    return expr is ContinueExpr
  }
}

class ExtensionExpr: DeclRefExpr<TypeDeclExpr> {
  let methods: [FuncDeclExpr]
  let typeRef: TypeRefExpr
  init(type: TypeRefExpr, methods: [FuncDeclExpr], sourceRange: SourceRange? = nil) {
    self.methods = methods.map { $0.addingImplicitSelf(type.type!) }
    self.typeRef = type
    super.init(sourceRange: sourceRange)
    self.type = type.type!
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? ExtensionExpr else { return false }
    return methods == expr.methods
  }
}

class PoundDiagnosticExpr: Expr {
  let isError: Bool
  let content: StringExpr
  init(isError: Bool, content: StringExpr, sourceRange: SourceRange? = nil) {
    self.isError = isError
    self.content = content
    super.init(sourceRange: sourceRange)
  }
  
  var text: String {
    return content.text
  }
}
