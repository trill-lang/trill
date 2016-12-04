//
//  BaseTypeChecker.swift
//  Trill
//

import Foundation

enum TypeCheckError: Error, CustomStringConvertible {
  case incorrectArgumentLabel(got: Identifier, expected: Identifier)
  case missingArgumentLabel(expected: Identifier)
  case extraArgumentLabel(got: Identifier)
  case arityMismatch(name: Identifier, gotCount: Int, expectedCount: Int)
  case invalidBinOpArgs(op: BuiltinOperator, lhs: DataType, rhs: DataType)
  case typeMismatch(expected: DataType, got: DataType)
  case nonBooleanTernary(got: DataType)
  case subscriptWithInvalidType(type: DataType)
  case subscriptWithNoArgs
  case nonBoolCondition(got: DataType?)
  case overflow(raw: String, type: DataType)
  case shiftPastBitWidth(type: DataType, shiftWidth: IntMax)
  
  var description: String {
    switch self {
    case .arityMismatch(let name, let gotCount, let expectedCount):
      return "expected \(expectedCount) arguments to function \(name) (got \(gotCount))"
    case .incorrectArgumentLabel(let got, let expected):
      return "incorrect argument label (expected '\(expected)', got '\(got)')"
    case .missingArgumentLabel(let expected):
      return "missing argument label (expected '\(expected)')"
    case .extraArgumentLabel(let got):
      return "extra argument label (got '\(got)')"
    case .typeMismatch(let expected, let got):
      return "type mismatch (expected value of type '\(expected)', got '\(got)')"
    case .invalidBinOpArgs(let op, let lhs, let rhs):
      return "cannot apply binary operator '\(op)' to operands of type '\(lhs)' and '\(rhs)'"
    case .subscriptWithInvalidType(let type):
      return "cannot subscript with argument of type \(type)"
    case .subscriptWithNoArgs:
      return "cannot subscript with no arguments"
    case .nonBooleanTernary(let got):
      return "ternary condition must be a Bool (got '\(got)')"
    case .nonBoolCondition(let got):
      let typeName = got != nil ? "\(got!)" : "<<error type>>"
      return "if condition must be a Bool (got '\(typeName)')"
    case .overflow(let raw, let type):
      return "value '\(raw)' overflows when stored into '\(type)'"
    case .shiftPastBitWidth(let type, let shiftWidth):
      return "shift amount \(shiftWidth) is greater than or equal to \(type)'s size in bits"
    }
  }
}

class TypeChecker: ASTTransformer, Pass {
  var title: String {
    return "Type Checking"
  }
  
  func ensureTypesAndLabelsMatch(_ expr: FuncCallExpr, decl: FuncDecl) {
    let precondition: Bool
    var declArgs = decl.args
    
    if let first = declArgs.first, first.isImplicitSelf {
      declArgs.removeFirst()
    }
    if decl.hasVarArgs {
      precondition = declArgs.count <= expr.args.count
    } else {
      precondition = declArgs.count == expr.args.count
    }
    if !precondition {
      let name = Identifier(name: "\(expr)")
      error(TypeCheckError.arityMismatch(name: name,
                                         gotCount: expr.args.count,
                                         expectedCount: declArgs.count),
            loc: expr.startLoc)
      return
    }
    for (arg, val) in zip(declArgs, expr.args) {
      if let externalName = arg.externalName {
        guard let label = val.label else {
          error(TypeCheckError.missingArgumentLabel(expected: externalName),
                loc: val.val.startLoc)
          continue
        }
        if label.name != externalName.name {
          error(TypeCheckError.incorrectArgumentLabel(got: label, expected: externalName),
                loc: val.val.startLoc,
                highlights: [
                  val.val.sourceRange
            ])
        }
      } else if let label = val.label {
        error(TypeCheckError.extraArgumentLabel(got: label),
              loc: val.val.startLoc)
      }
      var argType = arg.type
      guard let type = val.val.type else {
        fatalError("unable to resolve val type")
      }
      if arg.isImplicitSelf {
        argType = argType.rootType
      }
      if !matches(argType, .any) && !matches(type, argType) {
        error(TypeCheckError.typeMismatch(expected: argType, got: type),
              loc: val.val.startLoc,
              highlights: [
                val.val.sourceRange
          ])
      }
    }
  }
  
  override func visitNumExpr(_ expr: NumExpr) {
    guard let type = expr.type else { return }
    let canTy = context.canonicalType(type)
    if case .int(let width, let signed) = canTy {
      var overflows = false
      switch width {
      case 8:
        if expr.value > IntMax(Int8.max) { overflows = true }
      case 16:
        if expr.value > IntMax(Int16.max) { overflows = true }
      case 32:
        if expr.value > IntMax(Int32.max) { overflows = true }
      case 64:
        if expr.value > IntMax(Int64.max) { overflows = true }
      default: break
      }
      if overflows {
        error(TypeCheckError.overflow(raw: expr.raw, type: expr.type!),
              loc: expr.startLoc, highlights: [expr.sourceRange])
        return
      }
      if !signed && expr.value < 0 {
        fatalError("ASDFASDF")
      }
    }
  }
  
  override func visitSwitchStmt(_ stmt: SwitchStmt) {
    for c in stmt.cases where !matches(c.constant.type, stmt.value.type) {
      error(TypeCheckError.typeMismatch(expected: stmt.value.type!, got: c.constant.type!),
            loc: c.constant.startLoc,
            highlights: [c.constant.sourceRange!])
    }
  }
  
  override func visitVarExpr(_ expr: VarExpr) -> Result {
    guard let decl = expr.decl else { return }
    guard let type = expr.type else { return }
    if !matches(decl.type, type) {
      error(TypeCheckError.typeMismatch(expected: decl.type, got: type),
            loc: expr.startLoc)
    }
    super.visitVarExpr(expr)
  }
  
  override func visitVarAssignDecl(_ decl: VarAssignDecl) -> Result {
    if let rhs = decl.rhs {
      guard let rhsType = rhs.type else { return }
      if !matches(decl.type, rhsType) {
        error(TypeCheckError.typeMismatch(expected: decl.type, got: rhsType),
              loc: decl.startLoc)
        return
      }
    }
    super.visitVarAssignDecl(decl)
  }
  
  override func visitIfStmt(_ stmt: IfStmt) {
    for (expr, _) in stmt.blocks {
      guard case .bool? = expr.type else {
        self.error(TypeCheckError.nonBoolCondition(got: expr.type),
                   loc: expr.startLoc,
                   highlights: [
                    expr.sourceRange
          ])
        return
      }
    }
    super.visitIfStmt(stmt)
  }
  
  override func visitFuncArgumentAssignDecl(_ decl: FuncArgumentAssignDecl) -> Result {
    if let rhsType = decl.rhs?.type, !matches(decl.type, rhsType) {
      error(TypeCheckError.typeMismatch(expected: decl.type, got: rhsType),
            loc: decl.startLoc,
            highlights: [
              decl.sourceRange
        ])
    }
    super.visitFuncArgumentAssignDecl(decl)
  }
  
  override func visitReturnStmt(_ expr: ReturnStmt) -> Result {
    guard let returnType = currentClosure?.returnType.type ?? currentFunction?.returnType.type else { return }
    guard let valType = expr.value.type else { return }
    if !matches(valType, returnType) {
      error(TypeCheckError.typeMismatch(expected: returnType, got: valType),
            loc: expr.startLoc,
            highlights: [
              expr.sourceRange
        ])
    }
    super.visitReturnStmt(expr)
  }
  
  override func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result {
    guard let decl = expr.decl else { return }
    ensureTypesAndLabelsMatch(expr, decl: decl)
    super.visitFuncCallExpr(expr)
  }
  
  override func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    guard let condType = expr.condition.type else { return }
    guard let trueType = expr.trueCase.type else { return }
    guard let falseType = expr.falseCase.type else { return }
    guard matches(condType, .bool) else {
      error(TypeCheckError.nonBooleanTernary(got: condType),
            loc: expr.startLoc,
            highlights: [
              expr.sourceRange
        ])
      return
    }
    guard matches(trueType, falseType) else {
      error(TypeCheckError.typeMismatch(expected: trueType, got: falseType),
            loc: expr.startLoc,
            highlights: [
              expr.sourceRange
        ])
      return
    }
    super.visitTernaryExpr(expr)
  }
  
  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) -> Result {
    guard let lhsType = expr.lhs.type else { return }
    guard let rhsType = expr.rhs.type else { return }
    if [.as, .is].contains(expr.op) {
      // thrown from sema
    } else if expr.op.isAssign {
      // thrown from sema
    } else if expr.decl == nil  {
      error(TypeCheckError.invalidBinOpArgs(op: expr.op, lhs: lhsType, rhs: rhsType),
            loc: expr.startLoc,
            highlights: [
              expr.lhs.sourceRange
        ])
      return
    } else if [.leftShift, .rightShift, .leftShiftAssign, .rightShiftAssign].contains(expr.op),
      let num = expr.rhs as? NumExpr,
      case .int(let width, _)? = expr.type,
      num.value >= IntMax(width) {
      error(TypeCheckError.shiftPastBitWidth(type: expr.type!, shiftWidth: num.value),
            loc: num.startLoc,
            highlights: [
              num.sourceRange
        ])
      return
    }
    super.visitInfixOperatorExpr(expr)
  }
  
  override func visitSubscriptExpr(_ expr: SubscriptExpr) -> Result {
    switch expr.lhs.type! {
    case .pointer(let subtype):
      ensureTypesAndLabelsMatch(expr, decl: context.foreignDecl(args: [.int64], ret: subtype))
    case .array(let subtype, _):
      ensureTypesAndLabelsMatch(expr, decl: context.foreignDecl(args: [.int64], ret: subtype))
    default:
      guard let decl = expr.decl else { return }
      ensureTypesAndLabelsMatch(expr, decl: decl)
    }
    super.visitSubscriptExpr(expr)
  }
}
