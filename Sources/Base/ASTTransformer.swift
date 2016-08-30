//
//  ASTTransformer.swift
//  Trill
//

import Foundation

class ASTTransformer: ASTVisitor {
  typealias Result = Void
  var currentFunction: FuncDecl? = nil
  var currentType: TypeDecl? = nil
  var currentScope: CompoundStmt? = nil
  var currentBreakTarget: ASTNode? = nil
  var currentClosure: ClosureExpr? = nil
  
  var declContext: ASTNode? = nil
  
  let context: ASTContext
  required init(context: ASTContext) {
    self.context = context
  }
  
  func withBreakTarget(_ e: ASTNode, _ f: () -> Void) {
    let oldTarget = currentBreakTarget
    currentBreakTarget = e
    withDeclContext(e, f)
    currentBreakTarget = oldTarget
  }
  
  func withFunction(_ e: FuncDecl, _ f: () -> Void) {
    let oldFunction = currentFunction
    currentFunction = e
    withDeclContext(e, f)
    currentFunction = oldFunction
  }
  
  func withClosure(_ e: ClosureExpr, _ f: () -> Void) {
    let oldClosure = currentClosure
    currentClosure = e
    withDeclContext(e, f)
    currentClosure = oldClosure
  }
  
  func withTypeDecl(_ e: TypeDecl, _ f: () -> Void) {
    let oldType = currentType
    currentType = e
    withDeclContext(e, f)
    currentType = oldType
  }
  
  func withScope(_ e: CompoundStmt, _ f: () -> Void) {
    let oldScope = currentScope
    currentScope = e
    f()
    currentScope = oldScope
  }
  
  func withDeclContext(_ e: ASTNode, _ f: () -> Void) {
    let oldContext = declContext
    declContext = e
    f()
    declContext = oldContext
  }
  
  func run(in context: ASTContext) {
    context.diagnostics.forEach(visitPoundDiagnosticStmt)
    context.globals.forEach(visit)
    context.types.forEach(visit)
    context.typeAliases.forEach(visit)
    context.functions.forEach(visit)
    context.extensions.forEach(visit)
  }
  
  func matches(_ t1: DataType?, _ t2: DataType?) -> Bool {
    return context.matches(t1, t2)
  }
  
  func visitNumExpr(_ expr: NumExpr) {}
  func visitCharExpr(_ expr: CharExpr) {}
  func visitFloatExpr(_ expr: FloatExpr) {}
  func visitVarExpr(_ expr: VarExpr) {}
  func visitBoolExpr(_ expr: BoolExpr) {}
  func visitVoidExpr(_ expr: VoidExpr) {}
  func visitNilExpr(_ expr: NilExpr) {}
  func visitStringExpr(_ expr: StringExpr) {}
  func visitTypeRefExpr(_ expr: TypeRefExpr) {}
  func visitParenExpr(_ expr: ParenExpr) {
    visit(expr.value)
  }
  func visitSizeofExpr(_ expr: SizeofExpr) {
    _ = expr.value.map(visit)
  }
  
  func visitVarAssignDecl(_ decl: VarAssignDecl) {
    _ = decl.rhs.map(visit)
  }
  
  func visitFuncArgumentAssignDecl(_ decl: FuncArgumentAssignDecl) {
    _ = decl.rhs.map(visit)
  }
  
  func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) {}
  
  func visitClosureExpr(_ expr: ClosureExpr) {
    withClosure(expr) {
      withScope(expr.body) {
        expr.args.forEach(visitFuncArgumentAssignDecl)
        visitCompoundStmt(expr.body)
      }
    }
  }
  
  func visitFuncDecl(_ expr: FuncDecl) {
    let visitor: () -> Void = {
      for arg in expr.args {
        self.visitFuncArgumentAssignDecl(arg)
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
  func visitReturnStmt(_ stmt: ReturnStmt) {
    visit(stmt.value)
  }
  func visitBreakStmt(_ stmt: BreakStmt) {}
  func visitContinueStmt(_ stmt: ContinueStmt) {}
  func visitCompoundStmt(_ stmt: CompoundStmt) {
    withScope(stmt) {
      stmt.exprs.forEach(visit)
    }
  }
  
  func visitTypeAliasDecl(_ decl: TypeAliasDecl) {}
  
  func visitSubscriptExpr(_ expr: SubscriptExpr) {
    visit(expr.lhs)
    visit(expr.amount)
  }
  
  func visitFuncCallExpr(_ expr: FuncCallExpr) {
    visit(expr.lhs)
    expr.args.forEach {
      visit($0.val)
    }
  }
  
  func visitTupleExpr(_ expr: TupleExpr) {
    expr.values.forEach(visit)
  }
  
  func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) {
    visit(expr.lhs)
  }
  
  func visitTypeDecl(_ decl: TypeDecl) {
    withTypeDecl(decl) {
      for initializer in decl.initializers {
        visitFuncDecl(initializer)
      }
      for method in decl.methods {
        visitFuncDecl(method)
      }
      for field in decl.fields {
        visitVarAssignDecl(field)
      }
      if let deinitializer = decl.deinitializer {
        visitFuncDecl(deinitializer)
      }
    }
  }
  func visitExtensionDecl(_ decl: ExtensionDecl) {
    for method in decl.methods {
      visitFuncDecl(method)
    }
  }
  
  func visitWhileStmt(_ stmt: WhileStmt) {
    visit(stmt.condition)
    withBreakTarget(stmt) {
      visitCompoundStmt(stmt.body)
    }
  }
  
  func visitForStmt(_ stmt: ForStmt) {
    _ = stmt.initializer.map(visit)
    _ = stmt.condition.map(visit)
    _ = stmt.incrementer.map(visit)
    withBreakTarget(stmt) {
      visit(stmt.body)
    }
  }
  
  func visitIfStmt(_ stmt: IfStmt) {
    for (condition, body) in stmt.blocks {
      _ = visit(condition)
      visitCompoundStmt(body)
    }
    _ = stmt.elseBody.map(visit)
  }
  
  func visitTernaryExpr(_ expr: TernaryExpr) {
    visit(expr.condition)
    visit(expr.trueCase)
    visit(expr.falseCase)
  }
  
  func visitSwitchStmt(_ stmt: SwitchStmt) {
    visit(stmt.value)
    for `case` in stmt.cases {
      visit(`case`)
    }
    _ = stmt.defaultBody.map(visitCompoundStmt)
  }
  
  func visitCaseStmt(_ stmt: CaseStmt) {
    visit(stmt.constant)
    visit(stmt.body)
  }
  
  func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
    visit(expr.lhs)
    visit(expr.rhs)
  }
  
  func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) {
    visit(expr.rhs)
  }
  
  func visitFieldLookupExpr(_ expr: FieldLookupExpr) {
    visit(expr.lhs)
  }
  
  func visitPoundDiagnosticStmt(_ stmt: PoundDiagnosticStmt) {
    // do nothing
  }
}
