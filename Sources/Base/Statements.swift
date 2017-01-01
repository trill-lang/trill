//
//  Statement.swift
//  Trill
//

import Foundation

class Stmt: ASTNode {}

class ReturnStmt: Stmt { // return <expr>;
  let value: Expr
  init(value: Expr, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ node: ASTNode) -> Bool {
    guard let node = node as? ReturnStmt else { return false }
    return value == node.value
  }
}

class VarAssignDecl: Decl {
  let rhs: Expr?
  let name: Identifier
  var typeRef: TypeRefExpr?
  var containingTypeDecl: TypeDecl?
  var mutable: Bool
  init(name: Identifier, typeRef: TypeRefExpr?, rhs: Expr? = nil, containingTypeDecl: TypeDecl? = nil, modifiers: [DeclModifier] = [], mutable: Bool = true, sourceRange: SourceRange? = nil) {
    precondition(rhs != nil || typeRef != nil)
    self.rhs = rhs
    self.typeRef = typeRef
    self.mutable = mutable
    self.name = name
    self.containingTypeDecl = containingTypeDecl
    super.init(type: typeRef?.type ?? .void,
               modifiers: modifiers,
               sourceRange: sourceRange)
  }
  override func equals(_ node: ASTNode) -> Bool {
    guard let node = node as? VarAssignDecl else { return false }
    guard name == node.name else { return false }
    guard type == node.type else { return false }
    guard rhs == node.rhs else { return false }
    return true
  }
  
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["type"] = typeRef?.type?.description
    superAttrs["name"] = name.name
    superAttrs["kind"] = mutable ? "let" : "var"
    return superAttrs
  }
}

class CompoundStmt: Stmt {
  let exprs: [ASTNode]
  var hasReturn = false
  init(exprs: [ASTNode], sourceRange: SourceRange? = nil) {
    self.exprs = exprs
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ node: ASTNode) -> Bool {
    guard let node = node as? CompoundStmt else { return false }
    return exprs == node.exprs
  }
}

class BranchStmt: Stmt {
  let condition: Expr
  let body: CompoundStmt
  init(condition: Expr, body: CompoundStmt, sourceRange: SourceRange? = nil) {
    self.condition = condition
    self.body = body
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ node: ASTNode) -> Bool {
    guard let node = node as? BranchStmt else { return false }
    return condition == node.condition && body == node.body
  }
}

class IfStmt: Stmt {
  let blocks: [(Expr, CompoundStmt)]
  let elseBody: CompoundStmt?
  init(blocks: [(Expr, CompoundStmt)], elseBody: CompoundStmt?, sourceRange: SourceRange? = nil) {
    self.blocks = blocks
    self.elseBody = elseBody
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ node: ASTNode) -> Bool {
    guard let node = node as? IfStmt else { return false }
    guard blocks.count == node.blocks.count else { return false }
    guard elseBody == node.elseBody else { return false }
    for (block, otherBlock) in zip(blocks, node.blocks) {
      if block.0 != otherBlock.0 { return false }
      if block.1 != otherBlock.1 { return false }
    }
    return true
  }
}

class WhileStmt: BranchStmt {}

class ForStmt: Stmt {
  let initializer: ASTNode?
  let condition: Expr?
  let incrementer: ASTNode?
  let body: CompoundStmt
  init(initializer: ASTNode?, condition: Expr?, incrementer: ASTNode?, body: CompoundStmt, sourceRange: SourceRange? = nil) {
    self.initializer = initializer
    self.condition = condition
    self.incrementer = incrementer
    self.body = body
    super.init(sourceRange: sourceRange)
  }
}

class SwitchStmt: Stmt {
  let value: Expr
  let cases: [CaseStmt]
  let defaultBody: CompoundStmt?
  init(value: Expr, cases: [CaseStmt], defaultBody: CompoundStmt? = nil, sourceRange: SourceRange? = nil) {
    self.value = value
    self.cases = cases
    self.defaultBody = defaultBody
    super.init(sourceRange: sourceRange)
  }
}

class CaseStmt: Stmt {
  let constant: ConstantExpr
  let body: CompoundStmt
  init(constant: ConstantExpr, body: CompoundStmt, sourceRange: SourceRange? = nil) {
    self.constant = constant
    self.body = body
    super.init(sourceRange: sourceRange)
  }
}

class BreakStmt: Stmt {
  override func equals(_ node: ASTNode) -> Bool {
    return node is BreakStmt
  }
}

class ContinueStmt: Stmt {
  override func equals(_ node: ASTNode) -> Bool {
    return node is ContinueStmt
  }
}

class ExtensionDecl: Decl {
  let methods: [FuncDecl]
  let staticMethods: [FuncDecl]
  let subscripts: [SubscriptDecl]
  let typeRef: TypeRefExpr
  var typeDecl: TypeDecl?
  init(type: TypeRefExpr,
       methods: [FuncDecl],
       staticMethods: [FuncDecl],
       subscripts: [SubscriptDecl],
       sourceRange: SourceRange? = nil) {
    self.methods = methods.map { $0.addingImplicitSelf(type.type!) }
    self.subscripts = subscripts.map { $0.addingImplicitSelf(type.type!) }
    self.staticMethods = staticMethods
    self.typeRef = type
    super.init(type: type.type!, modifiers: [], sourceRange: sourceRange)
  }
  override func equals(_ node: ASTNode) -> Bool {
    guard let node = node as? ExtensionDecl else { return false }
    return   methods == node.methods
          && subscripts == node.subscripts
          && staticMethods == node.staticMethods
          && typeRef == node.typeRef
  }
}

class PoundDiagnosticStmt: Stmt {
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
  
  
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["text"] = text
    superAttrs["kind"] = isError ? "error" : "warning"
    return superAttrs
  }
}
