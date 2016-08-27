//
//  Value.swift
//  Trill
//

import Foundation

class ValExpr: Expr {
  var type: DataType? = nil
}

class ConstantExpr: ValExpr {
  override init(sourceRange: SourceRange? = nil) {
    super.init(sourceRange: sourceRange)
  }
  var text: String { return "" }
}

class VoidExpr: ValExpr {
  override init(sourceRange: SourceRange? = nil) {
    super.init(sourceRange: sourceRange)
    self.type = .void
  }
  override func equals(_ expr: Expr) -> Bool {
    return expr is VoidExpr
  }
}

class NilExpr: ValExpr {
  override init(sourceRange: SourceRange? = nil) {
    super.init(sourceRange: sourceRange)
    self.type = .pointer(type: .int8)
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let other = expr as? NilExpr else { return false }
    return other.type == type
  }
}

class NumExpr: ConstantExpr { // 1234567
  let value: IntMax
  let raw: String
  init(value: IntMax, raw: String, sourceRange: SourceRange? = nil) {
    self.value = value
    self.raw = raw
    super.init(sourceRange: sourceRange)
    self.type = .int64
  }
  override var text: String {
    return "\(value)"
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? NumExpr else { return false }
    return value == expr.value
  }
}

class ParenExpr: ValExpr {
  let value: ValExpr
  init(value: ValExpr, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  
  var rootExpr: ValExpr {
    if let paren = value as? ParenExpr {
      return paren.rootExpr
    }
    return value
  }
}

class TupleExpr: ValExpr {
  let values: [ValExpr]
  init(values: [ValExpr], sourceRange: SourceRange? = nil) {
    self.values = values
    super.init(sourceRange: sourceRange)
  }
  
  override var type: DataType? {
    get {
      var fieldTypes = [DataType]()
      for v in self.values {
        guard let type = v.type else { return nil }
        fieldTypes.append(type)
      }
      return .tuple(fields: fieldTypes)
    }
    set {
      fatalError("cannot set type on tuple expr")
    }
  }
}


class TupleFieldLookupExpr: ValExpr {
  let lhs: ValExpr
  var decl: Expr? = nil
  let field: Int
  let fieldRange: SourceRange
  init(lhs: ValExpr, field: Int, fieldRange: SourceRange, sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.field = field
    self.fieldRange = fieldRange
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ rhs: Expr) -> Bool {
    guard let rhs = rhs as? TupleFieldLookupExpr else { return false }
    guard field == rhs.field else { return false }
    guard lhs == rhs.lhs else { return false }
    return true
  }
}

class FloatExpr: ConstantExpr {
  override var type: DataType? {
    get { return .double } set { }
  }
  let value: Double
  init(value: Double, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  override var text: String {
    return "\(value)"
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? FloatExpr else { return false }
    return value == expr.value
  }
}

class BoolExpr: ConstantExpr {
  override var type: DataType? {
    get { return .bool } set { }
  }
  let value: Bool
  init(value: Bool, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  override var text: String {
    return "\(value)"
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? BoolExpr else { return false }
    return value == expr.value
  }
}

class StringExpr: ConstantExpr {
  override var type: DataType? {
    get { return .pointer(type: .int8) } set { }
  }
  var value: String
  init(value: String, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  override var text: String {
    return value
  }
}

class PoundFunctionExpr: StringExpr {
  init(sourceRange: SourceRange? = nil) {
    super.init(value: "", sourceRange: sourceRange)
  }
}

class CharExpr: ConstantExpr {
  override var type: DataType? {
    get { return .int8 } set { }
  }
  let value: UInt8
  init(value: UInt8, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  override var text: String {
    return "\(value)"
  }
}

class VarExpr: ValExpr {
  let name: Identifier
  var isTypeVar = false
  var isSelf = false
  var decl: DeclExpr? = nil
  init(name: Identifier, sourceRange: SourceRange? = nil) {
    self.name = name
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? VarExpr else { return false }
    return name == expr.name
  }
}

class SizeofExpr: ValExpr {
  var value: ValExpr?
  var valueType: DataType?
  init(value: ValExpr, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
    self.type = .int64
  }
}

class SubscriptExpr: ValExpr {
  let lhs: ValExpr
  let amount: ValExpr
  init(lhs: ValExpr, amount: ValExpr, sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.amount = amount
    super.init(sourceRange: sourceRange)
  }
}

class TernaryExpr: ValExpr {
  let condition: ValExpr
  let trueCase: ValExpr
  let falseCase: ValExpr
  init(condition: ValExpr, trueCase: ValExpr, falseCase: ValExpr, sourceRange: SourceRange? = nil) {
    self.condition = condition
    self.trueCase = trueCase
    self.falseCase = falseCase
    super.init(sourceRange: sourceRange)
  }
}
