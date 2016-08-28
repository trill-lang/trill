//
//  Operator.swift
//  Trill
//

import Foundation

enum Associativity {
  case left, right, none
}

enum BuiltinOperator: String, CustomStringConvertible {
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
  case `as` = "as"
  
  var isPrefix: Bool {
    return self == .bitwiseNot || self == .not ||
      self == .minus || self == .ampersand ||
      self == .star
  }
  
  var isInfix: Bool {
    return self != .bitwiseNot && self != .not
  }
  
  var isCompoundAssign: Bool {
    return self.associatedOp != nil
  }
  
  var isAssign: Bool {
    return self.isCompoundAssign || self == .assign
  }
  
  var associatedOp: BuiltinOperator? {
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
  
  var infixPrecedence: Int {
    switch self {

    case .as: return 170
      
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
  
  var description: String { return self.rawValue }
}

class PrefixOperatorExpr: Expr {
  let op: BuiltinOperator
  let opRange: SourceRange?
  let rhs: Expr
  init(op: BuiltinOperator, rhs: Expr, opRange: SourceRange? = nil, sourceRange: SourceRange? = nil) {
    self.rhs = rhs
    self.op = op
    self.opRange = opRange
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ node: ASTNode) -> Bool {
    guard let node = node as? PrefixOperatorExpr else { return false }
    return op == node.op && rhs == node.rhs
  }
  
  func type(forArgType argType: DataType) -> DataType? {
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
}

class InfixOperatorExpr: Expr {
  let op: BuiltinOperator
  let opRange: SourceRange?
  let lhs: Expr
  let rhs: Expr
  
  init(op: BuiltinOperator, lhs: Expr, rhs: Expr, opRange: SourceRange? = nil, sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.op = op
    self.opRange = opRange
    self.rhs = rhs
    super.init(sourceRange: sourceRange)
  }
  
  override func equals(_ node: ASTNode) -> Bool {
    guard let node = node as? InfixOperatorExpr else { return false }
    return op == node.op && rhs == node.rhs && lhs == node.lhs
  }
  
  func type(forArgType argType: DataType) -> DataType? {
    if op.isAssign { return argType }
    switch (self.op, argType) {
    case (.plus, .int): return argType
    case (.plus, .floating): return argType
    case (.plus, .pointer): return argType
    case (.minus, .int): return argType
    case (.minus, .floating): return argType
    case (.minus, .pointer): return .int64
    case (.star, .int): return argType
    case (.star, .floating): return argType
    case (.star, .pointer): return .int64
    case (.divide, .int): return argType
    case (.divide, .floating): return argType
    case (.mod, .int): return argType
      
    case (.equalTo, .int): return .bool
    case (.equalTo, .pointer): return .bool
    case (.equalTo, .floating): return .bool
    case (.equalTo, .bool): return .bool
      
    case (.notEqualTo, .int): return .bool
    case (.notEqualTo, .floating): return .bool
    case (.notEqualTo, .pointer): return .bool
    case (.notEqualTo, .bool): return .bool
      
    case (.lessThan, .int): return .bool
    case (.lessThan, .pointer): return .bool
    case (.lessThan, .floating): return .bool
      
    case (.lessThanOrEqual, .int): return .bool
    case (.lessThanOrEqual, .pointer): return .bool
    case (.lessThanOrEqual, .floating): return .bool
      
    case (.greaterThan, .int): return .bool
    case (.greaterThan, .pointer): return .bool
    case (.greaterThan, .floating): return .bool
      
    case (.greaterThanOrEqual, .int): return .bool
    case (.greaterThanOrEqual, .pointer): return .bool
    case (.greaterThanOrEqual, .floating): return .bool
      
    case (.and, .bool): return .bool
    case (.or, .bool): return .bool
    case (.xor, .int): return argType
    case (.xor, .bool): return .bool
    case (.bitwiseOr, .int): return argType
    case (.ampersand, .int): return argType
    case (.leftShift, .int): return argType
    case (.rightShift, .int): return argType
    default: return nil
    }
  }
}
