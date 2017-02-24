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
  case `is` = "is"
  
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
    case .is: return 170
      
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
  
  func type(forArgType argType: DataType) -> DataType? {
    switch (self.op, argType) {
    case (.minus, .int): return argType
    case (.minus, .floating): return argType
    case (.star, .pointer(let type)): return type
    case (.not, .bool): return .bool
    case (.ampersand, let type): return .pointer(type: type)
    case (.bitwiseNot, .int): return argType
    case (.is, _): return .bool
    default: return nil
    }
  }
  
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["operator"] = "\(op)"
    return superAttrs
  }
}

class InfixOperatorExpr: Expr {
  let op: BuiltinOperator
  let opRange: SourceRange?
  let lhs: Expr
  let rhs: Expr
  var decl: OperatorDecl? = nil
  
  init(op: BuiltinOperator, lhs: Expr, rhs: Expr, opRange: SourceRange? = nil, sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.op = op
    self.opRange = opRange
    self.rhs = rhs
    super.init(sourceRange: sourceRange)
  }
  
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["operator"] = "\(op)"
    if let decl = decl {
      superAttrs["decl"] = decl.formattedName
    }
    return superAttrs
  }
}

class OperatorDecl: FuncDecl {
  let op: BuiltinOperator
  let opRange: SourceRange?
  init(op: BuiltinOperator,
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
  
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["operator"] = "\(op)"
    superAttrs["name"] = nil
    superAttrs["kind"] = nil
    return superAttrs
  }
}
