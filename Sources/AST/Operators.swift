///
/// Operators.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation
import Source

public enum Associativity {
  case left, right, none
}

public enum BuiltinOperator: String, CustomStringConvertible {
  case plus = "+"
  case minus = "-"
  case star = "*"
  case divide = "/"
  case mod = "%"
  case assign = "="
  case equalTo = "=="
  case notEqualTo = "!="
  case lessThan = "<"
  case lessThanOrEqual = "<="
  case greaterThan = ">"
  case greaterThanOrEqual = ">="
  case and = "&&"
  case or = "||"
  case xor = "^"
  case ampersand = "&"
  case bitwiseOr = "|"
  case not = "!"
  case bitwiseNot = "~"
  case leftShift = "<<"
  case rightShift = ">>"
  case plusAssign = "+="
  case minusAssign = "-="
  case timesAssign = "*="
  case divideAssign = "/="
  case modAssign = "%="
  case andAssign = "&="
  case orAssign = "|="
  case xorAssign = "^="
  case rightShiftAssign = ">>="
  case leftShiftAssign = "<<="

  public var isPrefix: Bool {
    return self == .bitwiseNot || self == .not ||
      self == .minus || self == .ampersand ||
      self == .star
  }

  public var isInfix: Bool {
    return self != .bitwiseNot && self != .not
  }

  public var isCompoundAssign: Bool {
    return self.associatedOp != nil
  }

  public var isAssign: Bool {
    return self.isCompoundAssign || self == .assign
  }

  public var associatedOp: BuiltinOperator? {
    switch self {
    case .modAssign: return .mod
    case .plusAssign: return .plus
    case .timesAssign: return .star
    case .divideAssign: return .divide
    case .minusAssign: return .minus
    case .leftShiftAssign: return .leftShift
    case .rightShiftAssign: return .rightShift
    case .andAssign: return .and
    case .orAssign: return .or
    case .xorAssign: return .xor
    default: return nil
    }
  }

  public var infixPrecedence: Int {
    switch self {

    case .leftShift: return 160
    case .rightShift: return 160

    case .star: return 150
    case .divide: return 150
    case .mod: return 150
    case .ampersand: return 150

    case .plus: return 140
    case .minus: return 140
    case .xor: return 140
    case .bitwiseOr: return 140

    case .equalTo: return 130
    case .notEqualTo: return 130
    case .lessThan: return 130
    case .lessThanOrEqual: return 130
    case .greaterThan: return 130
    case .greaterThanOrEqual: return 130

    case .and: return 120
    case .or: return 110

    case .assign: return 90
    case .plusAssign: return 90
    case .minusAssign: return 90
    case .timesAssign: return 90
    case .divideAssign: return 90
    case .modAssign: return 90
    case .andAssign: return 90
    case .orAssign: return 90
    case .xorAssign: return 90
    case .rightShiftAssign: return 90
    case .leftShiftAssign: return 90

    // prefix-only
    case .not: return 999
    case .bitwiseNot: return 999
    }
  }

  public var description: String { return self.rawValue }
}

public class PrefixOperatorExpr: Expr {
  public let op: BuiltinOperator
  public let opRange: SourceRange?
  public let rhs: Expr
  public init(op: BuiltinOperator, rhs: Expr, opRange: SourceRange? = nil, sourceRange: SourceRange? = nil) {
    self.rhs = rhs
    self.op = op
    self.opRange = opRange
    super.init(sourceRange: sourceRange)
  }

  public func typeForArgType(_ argType: DataType) -> DataType? {
    switch (self.op, argType) {
    case (.minus, .int): return argType
    case (.minus, .floating): return argType
    case (.star, .pointer(let type)): return type
    case (.not, .bool): return .bool
    case (.ampersand, let type): return .pointer(type: type)
    case (.bitwiseNot, .int): return argType
    default: return nil
    }
  }

  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["operator"] = "\(op)"
    return superAttrs
  }
}

public class InfixOperatorExpr: Expr {
  public let op: BuiltinOperator
  public let opRange: SourceRange?
  public let lhs: Expr
  public let rhs: Expr
  public var decl: OperatorDecl? = nil

  public init(op: BuiltinOperator, lhs: Expr, rhs: Expr, opRange: SourceRange? = nil, sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.op = op
    self.opRange = opRange
    self.rhs = rhs
    super.init(sourceRange: sourceRange)
  }

  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["operator"] = "\(op)"
    if let decl = decl {
      superAttrs["decl"] = decl.formattedName
    }
    return superAttrs
  }
}

public class OperatorDecl: FuncDecl {
  public let op: BuiltinOperator
  public let opRange: SourceRange?
  public init(op: BuiltinOperator,
       args: [ParamDecl],
       genericParams: [GenericParamDecl],
       returnType: TypeRefExpr,
       body: CompoundStmt?,
       modifiers: [DeclModifier],
       opRange: SourceRange? = nil,
       sourceRange: SourceRange? = nil) {
    self.op = op
    self.opRange = opRange
    super.init(name: Identifier(name: "\(op)"),
               returnType: returnType,
               args: args,
               genericParams: genericParams,
               body: body,
               modifiers: modifiers,
               sourceRange: sourceRange)
  }

  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["operator"] = "\(op)"
    superAttrs["name"] = nil
    superAttrs["kind"] = nil
    return superAttrs
  }
}
