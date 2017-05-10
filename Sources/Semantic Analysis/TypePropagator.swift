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
/// is assigned the resolved subepxression type.
final class TypePropagator: ASTTransformer {

  required init(context: ASTContext) {
    super.init(context: context)
  }

  /// Sets the type of the expression and updates its subexpressions.
  func update(_ expr: inout Expr, type: DataType) {
    let canExprTy = context.canonicalType(expr.type)
    let canTy = context.canonicalType(type)

    // If the type already matches, then we're fine.
    guard canExprTy != canTy else { return }

    if !(expr is ExistentialCoercionExpr) && context.isProtocolType(type) {
      expr = ExistentialCoercionExpr(expr: expr, protocol: type)
    }

    retype(expr, type: type)
  }

  func retype(_ expr: Expr, type: DataType) {
    expr.type = type.literalFallback
    visit(expr)
  }

  override func visitVarAssignDecl(_ decl: VarAssignDecl) {
    if let typeRef = decl.typeRef {
      retype(typeRef, type: decl.type)
    }
    if let rhs = decl.rhs {
      var newRHS = rhs
      update(&newRHS, type: decl.type)
      decl.rhs = newRHS
    }
  }

  override func visitCoercionExpr(_ expr: CoercionExpr) {
    if case .promotion = expr.kind {
      update(&expr.lhs, type: expr.type)
    }
    retype(expr.rhs, type: expr.type)
  }

  override func visitPropertyRefExpr(_ expr: PropertyRefExpr) {
    if let typeDecl = expr.typeDecl {
      update(&expr.lhs, type: typeDecl.type)
    }
  }

  override func visitAssignStmt(_ stmt: AssignStmt) {
    if let decl = stmt.decl {
      guard case .function(let args, _, _) =
        context.canonicalType(decl.type) else { return }
      retype(stmt.lhs, type: args[0])
      update(&stmt.rhs, type: args[1])
    } else {
      update(&stmt.rhs, type: stmt.lhs.type)
    }
  }

  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
    guard let decl = expr.decl else { return }
    guard case .function(let args, let ret, _) =
      context.canonicalType(decl.type) else { return }
    update(&expr.lhs, type: args[0])
    update(&expr.rhs, type: args[1])
    expr.type = ret
  }

  override func visitTupleExpr(_ expr: TupleExpr) {
    guard case .tuple(let fields) =
      context.canonicalType(expr.type) else { return }
    for (type, childIdx) in zip(fields, expr.values.indices) {
      update(&expr.values[childIdx], type: type)
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

    for (type, childIdx) in zip(args, expr.args.indices) {
      update(&expr.args[childIdx].val, type: type)
    }
    
    if expr is SubscriptExpr {
      update(&expr.lhs, type: decl.args[0].type)
    } else {
      update(&expr.lhs, type: decl.type)
    }
    expr.type = ret
  }

  override func visitParenExpr(_ expr: ParenExpr) {
    update(&expr.value, type: expr.type)
  }

  override func visitArrayExpr(_ expr: ArrayExpr) {
    guard case .array(let element, _) =
      context.canonicalType(expr.type) else { return }
    for childIdx in expr.values.indices {
      update(&expr.values[childIdx], type: element)
    }
  }

  override func visitReturnStmt(_ stmt: ReturnStmt) {
    update(&stmt.value, type: stmt.type)
  }

  override func visitSubscriptExpr(_ expr: SubscriptExpr) {
    visitFuncCallExpr(expr)
  }

  override func visitTernaryExpr(_ expr: TernaryExpr) {
    update(&expr.trueCase, type: expr.type)
    update(&expr.falseCase, type: expr.type)
  }

  override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) {
    switch (expr.op, expr.type) {
    case let (.ampersand, .pointer(elt)):
      update(&expr.rhs, type: elt)
    case let (.star, elt):
      update(&expr.rhs, type: .pointer(elt))
    default:
      break
    }
  }
}
