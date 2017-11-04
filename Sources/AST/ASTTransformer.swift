///
/// ASTTransformer.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation
import Source

open class ASTTransformer: ASTVisitor {
  public typealias Result = Void
  public var currentFunction: FuncDecl? = nil
  public var currentType: TypeDecl? = nil
  public var currentScope: CompoundStmt? = nil
  public var currentBreakTarget: ASTNode? = nil
  public var currentClosure: ClosureExpr? = nil

  public var declContext: ASTNode? = nil

  public let context: ASTContext
  public required init(context: ASTContext) {
    self.context = context
  }

  open func withBreakTarget(_ e: ASTNode, _ f: () -> Void) {
    let oldTarget = currentBreakTarget
    currentBreakTarget = e
    withDeclContext(e, f)
    currentBreakTarget = oldTarget
  }

  open func withFunction(_ e: FuncDecl, _ f: () -> Void) {
    let oldFunction = currentFunction
    currentFunction = e
    withDeclContext(e, f)
    currentFunction = oldFunction
  }

  open func withClosure(_ e: ClosureExpr, _ f: () -> Void) {
    let oldClosure = currentClosure
    currentClosure = e
    withDeclContext(e, f)
    currentClosure = oldClosure
  }

  open func withTypeDecl(_ e: TypeDecl, _ f: () -> Void) {
    let oldType = currentType
    currentType = e
    withDeclContext(e, f)
    currentType = oldType
  }

  open func withScope(_ e: CompoundStmt, _ f: () -> Void) {
    let oldScope = currentScope
    currentScope = e
    f()
    currentScope = oldScope
  }

  open func withDeclContext(_ e: ASTNode, _ f: () -> Void) {
    let oldContext = declContext
    declContext = e
    f()
    declContext = oldContext
  }

  open func run(in context: ASTContext) {
    context.diagnostics.forEach(visitPoundDiagnosticStmt)
    context.globals.forEach(visitVarAssignDecl)
    context.protocols.forEach(visitProtocolDecl)
    context.types.forEach(visitTypeDecl)
    context.typeAliases.forEach(visitTypeAliasDecl)
    context.functions.forEach(visitFuncDecl)
    context.operators.forEach(visitOperatorDecl)
    context.extensions.forEach(visitExtensionDecl)
  }

  public func matchRank(_ t1: DataType, _ t2: DataType) -> TypeRank? {
    return context.matchRank(t1, t2)
  }

  public func matches(_ t1: DataType, _ t2: DataType) -> Bool {
    return context.matches(t1, t2)
  }

  open func visitNumExpr(_ expr: NumExpr) {}
  open func visitCharExpr(_ expr: CharExpr) {}
  open func visitFloatExpr(_ expr: FloatExpr) {}
  open func visitVarExpr(_ expr: VarExpr) {}
  open func visitBoolExpr(_ expr: BoolExpr) {}
  open func visitVoidExpr(_ expr: VoidExpr) {}
  open func visitNilExpr(_ expr: NilExpr) {}
  open func visitStringExpr(_ expr: StringExpr) {}
  open func visitStringInterpolationExpr(_ expr: StringInterpolationExpr) {
    _ = expr.segments.map(visit)
  }
  open func visitTypeRefExpr(_ expr: TypeRefExpr) {}
  open func visitParenExpr(_ expr: ParenExpr) {
    visit(expr.value)
  }
  open func visitSizeofExpr(_ expr: SizeofExpr) {
    _ = expr.value.map(visit)
  }

  open func visitVarAssignDecl(_ decl: VarAssignDecl) {
    _ = decl.rhs.map(visit)
  }

  open func visitParamDecl(_ decl: ParamDecl) {
    _ = decl.rhs.map(visit)
  }

  open func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) {}

  open func visitClosureExpr(_ expr: ClosureExpr) {
    withClosure(expr) {
      withScope(expr.body) {
        expr.args.forEach(visitParamDecl)
        visitCompoundStmt(expr.body)
      }
    }
  }

  open func visitOperatorDecl(_ decl: OperatorDecl) {
    visitFuncDecl(decl)
  }

  open func visitFuncDecl(_ expr: FuncDecl) {
    let visitor: () -> Void = {
      for arg in expr.args {
        self.visitParamDecl(arg)
      }
      _ = expr.body.map(self.visitCompoundStmt)
    }
    withFunction(expr) {
      if let body = expr.body {
        withScope(body, visitor)
      } else {
        visitor()
      }
    }
  }
  open func visitReturnStmt(_ stmt: ReturnStmt) {
    visit(stmt.value)
  }
  open func visitBreakStmt(_ stmt: BreakStmt) {}
  open func visitContinueStmt(_ stmt: ContinueStmt) {}
  open func visitCompoundStmt(_ stmt: CompoundStmt) {
    withScope(stmt) {
      stmt.stmts.forEach(visit)
    }
  }

  open func visitTypeAliasDecl(_ decl: TypeAliasDecl) {}

  open func visitSubscriptExpr(_ expr: SubscriptExpr) {
    visit(expr.lhs)
    for arg in expr.args {
        visit(arg.val)
    }
  }

  open func visitFuncCallExpr(_ expr: FuncCallExpr) {
    visit(expr.lhs)
    expr.args.forEach {
      visit($0.val)
    }
  }

  open func visitArrayExpr(_ expr: ArrayExpr) {
    expr.values.forEach(visit)
  }

  open func visitTupleExpr(_ expr: TupleExpr) {
    expr.values.forEach(visit)
  }

  open func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) {
    visit(expr.lhs)
  }

  open func visitTypeDecl(_ decl: TypeDecl) {
    withTypeDecl(decl) {
      for initializer in decl.initializers {
        visitFuncDecl(initializer)
      }
      for method in decl.methods {
        visitFuncDecl(method)
      }
      for method in decl.staticMethods {
        visitFuncDecl(method)
      }
      for property in decl.properties {
        visitPropertyDecl(property)
      }
      for subscriptDecl in decl.subscripts {
        visitFuncDecl(subscriptDecl)
      }
      if let deinitializer = decl.deinitializer {
        visitFuncDecl(deinitializer)
      }
    }
  }

  open func visitPropertyDecl(_ decl: PropertyDecl) {
    if let getter = decl.getter {
      visitFuncDecl(getter)
    }
    if let setter = decl.setter {
      visitFuncDecl(setter)
    }
  }

  open func visitExtensionDecl(_ decl: ExtensionDecl) {
    decl.methods.forEach(visitFuncDecl)
    decl.subscripts.forEach(visitFuncDecl)
  }

  open func visitWhileStmt(_ stmt: WhileStmt) {
    visit(stmt.condition)
    withBreakTarget(stmt) {
      visitCompoundStmt(stmt.body)
    }
  }

  open func visitForStmt(_ stmt: ForStmt) {
    withScope(stmt.body) {
      if let initial = stmt.initializer {
        visit(initial)
      }
      if let cond = stmt.condition {
        visit(cond)
      }
      if let incr = stmt.incrementer {
        visit(incr)
      }
      withBreakTarget(stmt) {
        visit(stmt.body)
      }
    }
  }

  open func visitIfStmt(_ stmt: IfStmt) {
    for (condition, body) in stmt.blocks {
      _ = visit(condition)
      visitCompoundStmt(body)
    }
    _ = stmt.elseBody.map(visit)
  }

  open func visitTernaryExpr(_ expr: TernaryExpr) {
    visit(expr.condition)
    visit(expr.trueCase)
    visit(expr.falseCase)
  }

  open func visitProtocolDecl(_ decl: ProtocolDecl) {
    for method in decl.methods {
      visitFuncDecl(method)
    }
    for conformance in decl.conformances {
      visitTypeRefExpr(conformance)
    }
  }

  open func visitSwitchStmt(_ stmt: SwitchStmt) {
    visit(stmt.value)
    for `case` in stmt.cases {
      visit(`case`)
    }
    _ = stmt.defaultBody.map(visitCompoundStmt)
  }

  open func visitCaseStmt(_ stmt: CaseStmt) {
    visit(stmt.constant)
    visit(stmt.body)
  }

  open func visitDeclStmt(_ stmt: DeclStmt) -> () {
    visit(stmt.decl)
  }

  open func visitExprStmt(_ stmt: ExprStmt) -> () {
    visit(stmt.expr)
  }

  open func visitIsExpr(_ expr: IsExpr) -> Void {
    visit(expr.lhs)
    visit(expr.rhs)
  }

  open func visitCoercionExpr(_ expr: CoercionExpr) -> Void {
    visit(expr.lhs)
    visit(expr.rhs)
  }

  open func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
    visit(expr.lhs)
    visit(expr.rhs)
  }

  open func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) {
    visit(expr.rhs)
  }

  open func visitPropertyRefExpr(_ expr: PropertyRefExpr) {
    visit(expr.lhs)
  }

  open func visitPoundDiagnosticStmt(_ stmt: PoundDiagnosticStmt) {
    // do nothing
  }
}
