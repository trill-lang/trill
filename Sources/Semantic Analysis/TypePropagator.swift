//
//  ConstraintApplier.swift
//  trill
//
//  Created by Harlan Haskins on 4/26/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

final class TypePropagator: ASTTransformer {

  required init(context: ASTContext) {
    super.init(context: context)
  }

  func update(_ expr: Expr, type: DataType) {
    expr.type = type
    visit(expr)
  }

  override func visitVarAssignDecl(_ decl: VarAssignDecl) {
    if let rhs = decl.rhs {
      update(rhs, type: decl.type)
    }
    if let typeRef = decl.typeRef {
      update(typeRef, type: decl.type)
    }
  }

  override func visitCoercionExpr(_ expr: CoercionExpr) {
    update(expr.lhs, type: expr.type)
    update(expr.rhs, type: expr.type)
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
}
