///
/// TypeChecker.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import Foundation

enum TypeCheckError: Error, CustomStringConvertible {
  case incorrectArgumentLabel(got: Identifier, expected: Identifier)
  case missingArgumentLabel(expected: Identifier)
  case extraArgumentLabel(got: Identifier)
  case arityMismatch(name: Identifier, gotCount: Int, expectedCount: Int)
  case invalidBinOpArgs(op: BuiltinOperator, lhs: DataType, rhs: DataType)
  case typeMismatch(expected: DataType, got: DataType)
  case cannotDowncastFromAny(type: DataType)
  case addExplicitCast(to: DataType)
  case nonBooleanTernary(got: DataType)
  case subscriptWithInvalidType(type: DataType)
  case subscriptWithNoArgs
  case nonBoolCondition(got: DataType?)
  case overflow(raw: String, type: DataType)
  case underflow(raw: String, type: DataType)
  case shiftPastBitWidth(type: DataType, shiftWidth: Int64)

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
    case .underflow(let raw, let type):
      return "value '\(raw)' underflows when stored into '\(type)'"
    case .shiftPastBitWidth(let type, let shiftWidth):
      return "shift amount \(shiftWidth) is greater than or equal to \(type)'s size in bits"
    case .cannotDowncastFromAny(let type):
      return "cannot downcast from Any to type '\(type)'"
    case .addExplicitCast(let toType):
      return "add explicit cast (as \(toType)) to fix"
    }
  }
}

public class TypeChecker: ASTTransformer, Pass {
  let csGen: ConstraintGenerator
  var env: ConstraintEnvironment

  func withScope(_ function: () -> Void) {
    let oldTarget = env
    function()
    env = oldTarget
  }

  required public init(context: ASTContext) {
    env = ConstraintEnvironment()
    csGen = ConstraintGenerator(context: context)
    super.init(context: context)
  }

  public var title: String {
    return "Type Checking"
  }

  override func visitFloatExpr(_ expr: FloatExpr) {
    // If a FloatingLiteral has survived this far, reify it.
    if case .floatingLiteral = expr.type {
      expr.type = expr.type.literalFallback
    }
  }

  override func visitStringInterpolationExpr(_ expr: StringInterpolationExpr) {
    super.visitStringInterpolationExpr(expr)
  }

  override func visitStringExpr(_ expr: StringExpr) {
    // If a StringLiteral has survived this far, reify it.
    if case .stringLiteral = expr.type {
      expr.type = expr.type.literalFallback
    }
  }
  
  public override func visitNumExpr(_ expr: NumExpr) {
    // If an IntegerLiteral has survived this far, reify it.
    if case .integerLiteral = expr.type {
      expr.type = expr.type.literalFallback
    }
    func bounds(width: Int, signed: Bool) -> (lower: IntMax, upper: UIntMax) {
        assert(width % 2 == 0, "width must be an even number")
        assert(width <= 64, "the maximum width is 64 bits")
        assert(width > 0, "width cannot be negative")
        let lower: Int64
        let upper: UInt64
        if width == 64 && !signed {
            upper = .max
            lower = 0
        } else if width == 64 && signed {
            upper = UInt64(Int64.max)
            lower = .min
        } else {
            lower = signed ? Int64(-(1 << (width - 1))) : 0
            upper = UInt64(bitPattern: Int64(1 << (width - (signed ? 1 : 0)))) - 1
        }
        return (lower, upper)
    }

    let type = expr.type
    guard type != .error else { return }
    let canTy = context.canonicalType(type)
    let reportUnderflow = {
      self.error(TypeCheckError.underflow(raw: expr.raw, type: expr.type),
                 loc: expr.startLoc, highlights: [expr.sourceRange])
    }
    if case .int(let width, let signed) = canTy {
      if expr.value == Int64(bitPattern: UInt64.max) { return }
      if !signed && expr.value < 0 {
        reportUnderflow()
        return
      }

      let (minimum, maximum) = bounds(width: width, signed: signed)

      if expr.value >= 0 && UInt64(expr.value) > maximum {
        error(TypeCheckError.overflow(raw: expr.raw, type: expr.type),
              loc: expr.startLoc, highlights: [expr.sourceRange])
        return
      }
      if expr.value < 0 && expr.value < minimum {
        reportUnderflow()
        return
      }
    }
  }
  
  public override func visitSwitchStmt(_ stmt: SwitchStmt) {
    for c in stmt.cases where !matches(c.constant.type, stmt.value.type) {
      error(TypeCheckError.typeMismatch(expected: stmt.value.type, got: c.constant.type),
            loc: c.constant.startLoc,
            highlights: [c.constant.sourceRange!])
    }
  }

  public override func visitVarAssignDecl(_ decl: VarAssignDecl) -> Result {
    if let type = solve(decl) {
      decl.type = type
    }
    env[decl.name] = decl.type
  }

  public override func visitIfStmt(_ stmt: IfStmt) {
    for (expr, _) in stmt.blocks {
      guard case .bool = expr.type else {
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
  
  public override func visitParamDecl(_ decl: ParamDecl) -> Result {
    if let rhsType = decl.rhs?.type, !matches(decl.type, rhsType) {
      error(TypeCheckError.typeMismatch(expected: decl.type, got: rhsType),
            loc: decl.startLoc,
            highlights: [
              decl.sourceRange
        ])
    }
    super.visitParamDecl(decl)
  }
  
  public override func visitReturnStmt(_ stmt: ReturnStmt) -> Result {
    guard let returnType = currentClosure?.returnType?.type ??
                           currentFunction?.returnType.type else { return }
    let valType = stmt.value.type
    if !matches(valType, returnType) {
      error(TypeCheckError.typeMismatch(expected: returnType, got: valType),
            loc: stmt.startLoc,
            highlights: [
              stmt.sourceRange
        ])
    }
    super.visitReturnStmt(stmt)
  }

  public override func visitFuncDecl(_ decl: FuncDecl) {
    self.withScope {
      for pd in decl.args {
        env[pd.name] = pd.type
      }
      super.visitFuncDecl(decl)
    }
  }

  public override func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result {
    guard let decl = expr.decl else { return }
    ensureTypesAndLabelsMatch(expr, decl: decl)
  }

  public override func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    let condType = expr.condition.type
    let trueType = expr.trueCase.type
    let falseType = expr.falseCase.type
    guard condType != .error, trueType != .error, falseType != .error else { return }
    guard matches(condType, .bool) else {
      error(TypeCheckError.nonBooleanTernary(got: condType),
            loc: expr.startLoc,
            highlights: [
              expr.sourceRange
        ])
      return
    }
    super.visitTernaryExpr(expr)
  }

  override func visitAssignStmt(_ stmt: AssignStmt) {
    super.visitAssignStmt(stmt)
    let lhsType = stmt.lhs.type
    let rhsType = stmt.rhs.type
    guard lhsType != .error, rhsType != .error else { return }
    // thrown from sema
    if let associated = stmt.associatedOp {
      if stmt.decl == nil {
        error(TypeCheckError.invalidBinOpArgs(op: associated, lhs: lhsType, rhs: rhsType),
              loc: stmt.startLoc,
              highlights: [
                stmt.lhs.sourceRange
          ])
        return
      }
      if [.leftShift, .rightShift].contains(associated),
        let num = stmt.rhs.semanticsProvidingExpr as? NumExpr,
        case .int(let width, _) = context.canonicalType(stmt.lhs.type),
        num.value >= IntMax(width) {
        error(TypeCheckError.shiftPastBitWidth(type: stmt.lhs.type, shiftWidth: num.value),
              loc: num.startLoc,
              highlights: [
                num.sourceRange
          ])
        return
      }
    } else {
      if case .any = context.canonicalType(rhsType),
        context.canonicalType(lhsType) != .any {
        error(TypeCheckError.cannotDowncastFromAny(type: lhsType),
              loc: stmt.rhs.startLoc,
              highlights: [
                stmt.lhs.sourceRange,
                stmt.rhs.sourceRange
          ])
        note(TypeCheckError.addExplicitCast(to: lhsType))
      }
    }
  }
}
