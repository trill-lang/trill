///
/// Statements.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation
import Source

public class Stmt: ASTNode {}

public class ReturnStmt: Stmt { // return <expr>;
  public let value: Expr
  public init(value: Expr, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
}

public enum VarKind: Equatable {
  case local(FuncDecl)
  case global
  case property(TypeDecl)
  case implicitSelf(FuncDecl, TypeDecl)

  public static func ==(lhs: VarKind, rhs: VarKind) -> Bool {
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

public class VarAssignDecl: Decl {
  public let rhs: Expr?
  public let name: Identifier
  public var typeRef: TypeRefExpr?
  public var kind: VarKind
  public var mutable: Bool
  public init?(name: Identifier,
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

  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["type"] = typeRef?.type.description
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

public class CompoundStmt: Stmt {
  public let stmts: [Stmt]
  public var hasReturn = false
  public init(stmts: [Stmt], sourceRange: SourceRange? = nil) {
    self.stmts = stmts
    super.init(sourceRange: sourceRange)
  }
}

public class BranchStmt: Stmt {
  public let condition: Expr
  public let body: CompoundStmt
  public init(condition: Expr, body: CompoundStmt, sourceRange: SourceRange? = nil) {
    self.condition = condition
    self.body = body
    super.init(sourceRange: sourceRange)
  }
}

public class IfStmt: Stmt {
  public let blocks: [(Expr, CompoundStmt)]
  public let elseBody: CompoundStmt?
  public init(blocks: [(Expr, CompoundStmt)], elseBody: CompoundStmt?, sourceRange: SourceRange? = nil) {
    self.blocks = blocks
    self.elseBody = elseBody
    super.init(sourceRange: sourceRange)
  }
}

public class WhileStmt: BranchStmt {}

public class ForStmt: Stmt {
  public let initializer: Stmt?
  public let condition: Expr?
  public let incrementer: Stmt?
  public let body: CompoundStmt
  public init(initializer: Stmt?,
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

public class SwitchStmt: Stmt {
  public let value: Expr
  public let cases: [CaseStmt]
  public let defaultBody: CompoundStmt?
  public init(value: Expr, cases: [CaseStmt], defaultBody: CompoundStmt? = nil, sourceRange: SourceRange? = nil) {
    self.value = value
    self.cases = cases
    self.defaultBody = defaultBody
    super.init(sourceRange: sourceRange)
  }
}

public class CaseStmt: Stmt {
  public let constant: Expr
  public let body: CompoundStmt
  public init(constant: Expr, body: CompoundStmt, sourceRange: SourceRange? = nil) {
    self.constant = constant
    self.body = body
    super.init(sourceRange: sourceRange)
  }
}

public class BreakStmt: Stmt {}
public class ContinueStmt: Stmt {}

public class ExtensionDecl: Decl {
  public let methods: [MethodDecl]
  public let staticMethods: [MethodDecl]
  public let subscripts: [SubscriptDecl]
  public let typeRef: TypeRefExpr
  public var typeDecl: TypeDecl?
  public init(type: TypeRefExpr,
       methods: [MethodDecl],
       staticMethods: [MethodDecl],
       subscripts: [SubscriptDecl],
       sourceRange: SourceRange? = nil) {
    self.methods = methods
    self.subscripts = subscripts
    self.staticMethods = staticMethods
    self.typeRef = type
    super.init(type: type.type, modifiers: [], sourceRange: sourceRange)
  }
}

public class ExprStmt: Stmt {
  public let expr: Expr

  public init(expr: Expr) {
    self.expr = expr
    super.init(sourceRange: expr.sourceRange)
  }
}

public class DeclStmt: Stmt {
  public let decl: Decl

  public init(decl: Decl) {
    self.decl = decl
    super.init(sourceRange: decl.sourceRange)
  }
}

public class PoundDiagnosticStmt: Stmt {
  public let isError: Bool
  public let content: StringExpr
  public init(isError: Bool, content: StringExpr,
              sourceRange: SourceRange? = nil) {
    self.isError = isError
    self.content = content
    super.init(sourceRange: sourceRange)
  }

  public var text: String {
    return content.text
  }

  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["text"] = text
    superAttrs["kind"] = isError ? "error" : "warning"
    return superAttrs
  }
}
