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
}

enum VarKind: Equatable {
  case local(FuncDecl)
  case global
  case property(TypeDecl)
  case implicitSelf(FuncDecl, TypeDecl)
  
  static func ==(lhs: VarKind, rhs: VarKind) -> Bool {
    switch (lhs, rhs) {
    case (.local(let fn), .local(let fn2)):
      return fn === fn2
    case (.global, .global):
      return true
    case (.property(let t), .property(let t2)):
      return t === t2
    case (.implicitSelf(let fn, let ty), .implicitSelf(let fn2, let ty2)):
      return fn === fn2 && ty === ty2
    default: return false
    }
  }
}

class VarAssignDecl: Decl {
  let rhs: Expr?
  let name: Identifier
  var typeRef: TypeRefExpr?
  var kind: VarKind
  var mutable: Bool
  init?(name: Identifier,
       typeRef: TypeRefExpr?,
       kind: VarKind = .global,
       rhs: Expr? = nil,
       modifiers: [DeclModifier] = [],
       mutable: Bool = true,
       sourceRange: SourceRange? = nil) {
    guard rhs != nil || typeRef != nil else { return nil }
    self.rhs = rhs
    self.typeRef = typeRef
    self.mutable = mutable
    self.name = name
    self.kind = kind
    super.init(type: typeRef?.type ?? .void,
               modifiers: modifiers,
               sourceRange: sourceRange)
  }
  
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["type"] = typeRef?.type?.description
    superAttrs["name"] = name.name
    superAttrs["kind"] = {
      switch kind {
      case .local: return "local"
      case .global: return "global"
      case .implicitSelf: return "implicit_self"
      case .property: return "property"
      }
    }()
    superAttrs["mutable"] = mutable
    return superAttrs
  }
}

class CompoundStmt: Stmt {
  let stmts: [Stmt]
  var hasReturn = false
  init(stmts: [Stmt], sourceRange: SourceRange? = nil) {
    self.stmts = stmts
    super.init(sourceRange: sourceRange)
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
}

class IfStmt: Stmt {
  let blocks: [(Expr, CompoundStmt)]
  let elseBody: CompoundStmt?
  init(blocks: [(Expr, CompoundStmt)], elseBody: CompoundStmt?, sourceRange: SourceRange? = nil) {
    self.blocks = blocks
    self.elseBody = elseBody
    super.init(sourceRange: sourceRange)
  }
}

class WhileStmt: BranchStmt {}

class ForStmt: Stmt {
  let initializer: Stmt?
  let condition: Expr?
  let incrementer: Stmt?
  let body: CompoundStmt
  init(initializer: Stmt?,
       condition: Expr?,
       incrementer: Stmt?,
       body: CompoundStmt,
       sourceRange: SourceRange? = nil) {
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
  let constant: Expr
  let body: CompoundStmt
  init(constant: Expr, body: CompoundStmt, sourceRange: SourceRange? = nil) {
    self.constant = constant
    self.body = body
    super.init(sourceRange: sourceRange)
  }
}

class BreakStmt: Stmt {}
class ContinueStmt: Stmt {}

class ExtensionDecl: Decl {
  let methods: [MethodDecl]
  let staticMethods: [MethodDecl]
  let subscripts: [SubscriptDecl]
  let typeRef: TypeRefExpr
  var typeDecl: TypeDecl?
  init(type: TypeRefExpr,
       methods: [MethodDecl],
       staticMethods: [MethodDecl],
       subscripts: [SubscriptDecl],
       sourceRange: SourceRange? = nil) {
    self.methods = methods
    self.subscripts = subscripts
    self.staticMethods = staticMethods
    self.typeRef = type
    super.init(type: type.type!, modifiers: [], sourceRange: sourceRange)
  }
}

class ExprStmt: Stmt {
  let expr: Expr

  init(expr: Expr) {
    self.expr = expr
    super.init(sourceRange: expr.sourceRange)
  }
}

class DeclStmt: Stmt {
  let decl: Decl

  init(decl: Decl) {
    self.decl = decl
    super.init(sourceRange: decl.sourceRange)
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
