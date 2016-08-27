//
//  ASTTransformer.swift
//  Trill
//

import Foundation

class ASTTransformer: ASTVisitor {
  typealias Result = Void
  var currentFunction: FuncDeclExpr? = nil
  var currentType: TypeDeclExpr? = nil
  var currentScope: CompoundExpr? = nil
  var currentBreakTarget: Expr? = nil
  var currentClosure: ClosureExpr? = nil
  
  var declContext: Expr? = nil
  
  let context: ASTContext
  required init(context: ASTContext) {
    self.context = context
  }
  
  func withBreakTarget(_ e: Expr, _ f: () -> Void) {
    let oldTarget = currentBreakTarget
    currentBreakTarget = e
    withDeclContext(e, f)
    currentBreakTarget = oldTarget
  }
  
  func withFunction(_ e: FuncDeclExpr, _ f: () -> Void) {
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
  
  func withTypeDecl(_ e: TypeDeclExpr, _ f: () -> Void) {
    let oldType = currentType
    currentType = e
    withDeclContext(e, f)
    currentType = oldType
  }
  
  func withScope(_ e: CompoundExpr, _ f: () -> Void) {
    let oldScope = currentScope
    currentScope = e
    f()
    currentScope = oldScope
  }
  
  func withDeclContext(_ e: Expr, _ f: () -> Void) {
    let oldContext = declContext
    declContext = e
    f()
    declContext = oldContext
  }
  
  func run(in context: ASTContext) {
    context.diagnostics.forEach(visitPoundDiagnosticExpr)
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
  
  func visitVarAssignExpr(_ expr: VarAssignExpr) {
    _ = expr.rhs.map(visit)
  }
  
  func visitFuncArgumentAssignExpr(_ expr: FuncArgumentAssignExpr) {
    _ = expr.rhs.map(visit)
  }
  
  func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) {}
  
  func visitClosureExpr(_ expr: ClosureExpr) {
    withClosure(expr) {
      withScope(expr.body) {
        expr.args.forEach(visitFuncArgumentAssignExpr)
        visitCompoundExpr(expr.body)
      }
    }
  }
  
  func visitFuncDeclExpr(_ expr: FuncDeclExpr) {
    let visitor: () -> Void = {
      for arg in expr.args {
        self.visitFuncArgumentAssignExpr(arg)
      }
      _ = expr.body.map(self.visitCompoundExpr)
    }
    withFunction(expr) {
      if let body = expr.body {
        withScope(body, visitor)
      } else {
        visitor()
      }
    }
  }
  func visitReturnExpr(_ expr: ReturnExpr) {
    visit(expr.value)
  }
  func visitBreakExpr(_ expr: BreakExpr) {}
  func visitContinueExpr(_ expr: ContinueExpr) {}
  func visitCompoundExpr(_ expr: CompoundExpr) {
    withScope(expr) {
      expr.exprs.forEach(visit)
    }
  }
  
  func visitTypeAliasExpr(_ expr: TypeAliasExpr) {}
  
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
  
  func visitTypeDeclExpr(_ expr: TypeDeclExpr) {
    withTypeDecl(expr) {
      for initializer in expr.initializers {
        visitFuncDeclExpr(initializer)
      }
      for method in expr.methods {
        visitFuncDeclExpr(method)
      }
      for field in expr.fields {
        visitVarAssignExpr(field)
      }
      if let deinitializer = expr.deinitializer {
        visitFuncDeclExpr(deinitializer)
      }
    }
  }
  func visitExtensionExpr(_ expr: ExtensionExpr) {
    for method in expr.methods {
      visitFuncDeclExpr(method)
    }
  }
  
  func visitWhileExpr(_ expr: WhileExpr) {
    visit(expr.condition)
    withBreakTarget(expr) {
      visitCompoundExpr(expr.body)
    }
  }
  
  func visitForLoopExpr(_ expr: ForLoopExpr) {
    _ = expr.initializer.map(visit)
    _ = expr.condition.map(visit)
    _ = expr.incrementer.map(visit)
    withBreakTarget(expr) {
      visit(expr.body)
    }
  }
  
  func visitIfExpr(_ expr: IfExpr) {
    for (condition, body) in expr.blocks {
      _ = visit(condition)
      visitCompoundExpr(body)
    }
    _ = expr.elseBody.map(visit)
  }
  
  func visitTernaryExpr(_ expr: TernaryExpr) {
    visit(expr.condition)
    visit(expr.trueCase)
    visit(expr.falseCase)
  }
  
  func visitSwitchExpr(_ expr: SwitchExpr) {
    visit(expr.value)
    for e in expr.cases {
      visit(e)
    }
    _ = expr.defaultBody.map(visitCompoundExpr)
  }
  
  func visitCaseExpr(_ expr: CaseExpr) {
    visit(expr.constant)
    visit(expr.body)
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
  
  func visitPoundDiagnosticExpr(_ expr: PoundDiagnosticExpr) {
    // do nothing
  }
}
