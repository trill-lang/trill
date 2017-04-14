//
//  Value.swift
//  Trill
//

import Foundation

enum Promotion {
  case any, generic
}

class Expr: ASTNode {
  var type: DataType? = nil
  var promotion: Promotion? = nil

  /// Looks through syntactic sugar expressions like `ParenExpr` to find the
  /// underlying expression that informs the semantics of this expression.
  var semanticsProvidingExpr: Expr {
    return self
  }

  override func attributes() -> [String : Any] {
    var attrs = super.attributes()
    if let type = type {
      attrs["type"] = type.description
    }
    if let promotion = promotion {
      attrs["promotion"] = "\(promotion)"
    }
    return attrs
  }
}

class ConstantExpr: Expr {
  override init(sourceRange: SourceRange? = nil) {
    super.init(sourceRange: sourceRange)
  }
  var text: String { return "" }
}

class VoidExpr: Expr {
  override init(sourceRange: SourceRange? = nil) {
    super.init(sourceRange: sourceRange)
    self.type = .void
  }
}

class NilExpr: ConstantExpr {
  override init(sourceRange: SourceRange? = nil) {
    super.init(sourceRange: sourceRange)
    self.type = .pointer(type: .int8)
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
    return raw
  }
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    superAttrs["raw"] = raw
    return superAttrs
  }
}

class ParenExpr: Expr {
  let value: Expr
  init(value: Expr, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }

  override var semanticsProvidingExpr: Expr {
    return value.semanticsProvidingExpr
  }
}

class TupleExpr: Expr {
  let values: [Expr]
  init(values: [Expr], sourceRange: SourceRange? = nil) {
    self.values = values
    super.init(sourceRange: sourceRange)
  }
}

class ArrayExpr: Expr {
  let values: [Expr]
  init(values: [Expr], sourceRange: SourceRange? = nil) {
    self.values = values
    super.init(sourceRange: sourceRange)
  }
}

class TupleFieldLookupExpr: Expr {
  let lhs: Expr
  var decl: Decl? = nil
  let field: Int
  let fieldRange: SourceRange
  init(lhs: Expr, field: Int, fieldRange: SourceRange, sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.field = field
    self.fieldRange = fieldRange
    super.init(sourceRange: sourceRange)
  }
  
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["field"] = field
    return superAttrs
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
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    return superAttrs
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
    return value.description
  }
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    return superAttrs
  }
}

class StringExpr: ConstantExpr {
  var value: String
  init(value: String, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  override var text: String {
    return value
  }
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    return superAttrs
  }
}

class StringInterpolationExpr: Expr {
  let segments: [Expr]
  
  init(segments: [Expr], sourceRange: SourceRange? = nil) {
    self.segments = segments
    super.init(sourceRange: sourceRange)
  }
}

class PoundFunctionExpr: StringExpr {
  init(sourceRange: SourceRange? = nil) {
    super.init(value: "", sourceRange: sourceRange)
  }
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    return superAttrs
  }
}

class PoundFileExpr: StringExpr {}

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
    return value.description
  }
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    return superAttrs
  }
}

protocol LValue {}

class GenericContainingExpr: Expr {
  var genericParams: [GenericParam]

  init(genericParams: [GenericParam], sourceRange: SourceRange? = nil) {
    self.genericParams = genericParams
    super.init(sourceRange: sourceRange)
  }
}

class VarExpr: GenericContainingExpr, LValue {
  let name: Identifier
  var isTypeVar = false
  var isSelf = false
  var decl: Decl? = nil
  init(name: Identifier, genericParams: [GenericParam] = [], sourceRange: SourceRange? = nil) {
    self.name = name
    super.init(genericParams: genericParams, sourceRange: sourceRange ?? name.range)
  }
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["name"] = name.name
    if isTypeVar {
      superAttrs["isTypeVar"] = true
    }
    return superAttrs
  }
}

class SizeofExpr: Expr {
  var value: Expr?
  var valueType: DataType?
  init(value: Expr, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
    self.type = .int64
  }
}

class SubscriptExpr: FuncCallExpr, LValue {}

class PropertyRefExpr: GenericContainingExpr, LValue {
  let lhs: Expr
  var decl: Decl? = nil
  var typeDecl: TypeDecl? = nil
  let name: Identifier
  let dotLoc: SourceLocation?
  init(lhs: Expr, name: Identifier, genericParams: [GenericParam] = [],
       dotLoc: SourceLocation? = nil,
       sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.name = name
    self.dotLoc = dotLoc
    super.init(genericParams: genericParams, sourceRange: sourceRange)
  }
  
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["fieldName"] = name.name
    return superAttrs
  }
}

class TernaryExpr: Expr {
  let condition: Expr
  let trueCase: Expr
  let falseCase: Expr
  init(condition: Expr, trueCase: Expr, falseCase: Expr, sourceRange: SourceRange? = nil) {
    self.condition = condition
    self.trueCase = trueCase
    self.falseCase = falseCase
    super.init(sourceRange: sourceRange)
  }
}

/// <expr> as <expr>
class CoercionExpr: Expr {
  let lhs: Expr
  let rhs: TypeRefExpr
  let asRange: SourceRange?

  init(lhs: Expr, rhs: TypeRefExpr,
       asRange: SourceRange? = nil,
       sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.asRange = asRange
    self.rhs = rhs
    super.init(sourceRange: sourceRange)
  }
}

/// <expr> is <expr>
class IsExpr: Expr {
  let lhs: Expr
  let rhs: TypeRefExpr
  let isRange: SourceRange?

  init(lhs: Expr, rhs: TypeRefExpr,
       isRange: SourceRange? = nil,
       sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.isRange = isRange
    self.rhs = rhs
    super.init(sourceRange: sourceRange)
  }
}
