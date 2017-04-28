//
//  ConstraintApplier.swift
//  trill
//
//  Created by Harlan Haskins on 4/26/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

/// Propagates types from parent expressions to their subexpressions.
/// This allows for back-propagating coercions to subepxressions.
/// This ensures that when, say, a tuple expr is given a type:
///
/// (1, true, 3) --> default type (IntegerLiteral, Bool, IntegerLiteral)
/// let x: (Int, Bool, Int8) = (1, true, 3) --> resolved type (Int, Bool, Int8)
/// TypePropagator will ensure that each of the literals inside the tuple
/// is assogined the resolved subepxression type.
final class TypePropagator: ASTTransformer {

  required init(context: ASTContext) {
    super.init(context: context)
  }

  /// Sets the type of the expression and updates its subexpressions.
  func update(_ expr: Expr, type: DataType) {
    expr.type = type
    visit(expr)
  }

  override func visitVarAssignDecl(_ decl: VarAssignDecl) {
    if let typeRef = decl.typeRef {
      update(typeRef, type: decl.type)
    }
  }

  override func visitCoercionExpr(_ expr: CoercionExpr) {
    update(expr.lhs, type: expr.type)
    update(expr.rhs, type: expr.type)
  }

  override func visitAssignStmt(_ stmt: AssignStmt) {
    if let decl = stmt.decl {
      guard case .function(let args, _, _) =
        context.canonicalType(decl.type) else { return }
      update(stmt.lhs, type: args[0])
      update(stmt.rhs, type: args[1])
    } else {
      update(stmt.rhs, type: stmt.lhs.type)
    }
  }

  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
    guard let decl = expr.decl else { return }
    guard case .function(let args, let ret, _) =
      context.canonicalType(decl.type) else { return }
    update(expr.lhs, type: args[0])
    update(expr.rhs, type: args[1])
    expr.type = ret
  }

  override func visitTupleExpr(_ expr: TupleExpr) {
    guard case .tuple(let fields) =
      context.canonicalType(expr.type) else { return }
    for (type, child) in zip(fields, expr.values) {
      update(child, type: type)
    }
  }

  override func visitFuncCallExpr(_ expr: FuncCallExpr) {
    guard let decl = expr.decl else { return }
    guard case .function(var args, let ret, _) =
      context.canonicalType(decl.type) else { return }

    // Remove implicit self
    if decl.args.count >= 1 && decl.args[0].isImplicitSelf {
      args.remove(at: 0)
    }

    for (type, child) in zip(args, expr.args) {
      update(child.val, type: type)
    }
    
    if expr is SubscriptExpr {
      update(expr.lhs, type: decl.args[0].type)
    } else {
      update(expr.lhs, type: decl.type)
    }
    expr.type = ret
  }

  override func visitArrayExpr(_ expr: ArrayExpr) {
    guard case .array(let element, _) =
      context.canonicalType(expr.type) else { return }
    for child in expr.values {
      update(child, type: element)
    }
  }

  override func visitSubscriptExpr(_ expr: SubscriptExpr) {
    visitFuncCallExpr(expr)
  }

  override func visitTernaryExpr(_ expr: TernaryExpr) {
    update(expr.trueCase, type: expr.type)
    update(expr.falseCase, type: expr.type)
  }

  override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) {
    switch (expr.op, expr.type) {
    case let (.ampersand, .pointer(elt)):
      update(expr.rhs, type: elt)
    case let (.star, elt):
      update(expr.rhs, type: .pointer(type: elt))
    default:
      break
    }
  }
}
