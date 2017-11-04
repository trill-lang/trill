///
/// Values.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation
import Source

public class Expr: ASTNode {
  public var type: DataType = .error

  /// Looks through syntactic sugar expressions like `ParenExpr` to find the
  /// underlying expression that informs the semantics of this expression.
  public var semanticsProvidingExpr: Expr {
    return self
  }

  public override func attributes() -> [String : Any] {
    var attrs = super.attributes()
    if type != .error {
      attrs["type"] = type.description
    }
    return attrs
  }
}

public class ConstantExpr: Expr {
  public override init(sourceRange: SourceRange? = nil) {
    super.init(sourceRange: sourceRange)
  }
  public var text: String { return "" }
}

public class VoidExpr: Expr {
  public override init(sourceRange: SourceRange? = nil) {
    super.init(sourceRange: sourceRange)
    self.type = .void
  }
}

public class NilExpr: ConstantExpr {
  public override init(sourceRange: SourceRange? = nil) {
    super.init(sourceRange: sourceRange)
    self.type = .pointer(type: .int8)
  }
}

public class NumExpr: ConstantExpr { // 1234567
  public let value: Int64
  public let raw: String
  public init(value: Int64, raw: String, sourceRange: SourceRange? = nil) {
    self.value = value
    self.raw = raw
    super.init(sourceRange: sourceRange)
    self.type = .int64
  }
  public override var text: String {
    return raw
  }
  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    superAttrs["raw"] = raw
    return superAttrs
  }
}

public class ParenExpr: Expr {
  public let value: Expr
  public init(value: Expr, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }

  public override var semanticsProvidingExpr: Expr {
    return value.semanticsProvidingExpr
  }
}

public class TupleExpr: Expr {
  public let values: [Expr]
  public init(values: [Expr], sourceRange: SourceRange? = nil) {
    self.values = values
    super.init(sourceRange: sourceRange)
  }
}

public class ArrayExpr: Expr {
  public let values: [Expr]
  public init(values: [Expr], sourceRange: SourceRange? = nil) {
    self.values = values
    super.init(sourceRange: sourceRange)
  }
}

public class TupleFieldLookupExpr: Expr {
  public let lhs: Expr
  public let field: Int
  public let fieldRange: SourceRange
  public init(lhs: Expr, field: Int, fieldRange: SourceRange, sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.field = field
    self.fieldRange = fieldRange
    super.init(sourceRange: sourceRange)
  }

  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["field"] = field
    return superAttrs
  }
}

public class FloatExpr: ConstantExpr {
  public override var type: DataType {
    get { return .double } set { }
  }
  public let value: Double
  public init(value: Double, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  public override var text: String {
    return "\(value)"
  }
  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    return superAttrs
  }
}

public class BoolExpr: ConstantExpr {
  public override var type: DataType {
    get { return .bool } set { }
  }
  public let value: Bool
  public init(value: Bool, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  public override var text: String {
    return value.description
  }
  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    return superAttrs
  }
}

public class StringExpr: ConstantExpr {
  public var value: String
  public init(value: String, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  public override var text: String {
    return value
  }
  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    return superAttrs
  }
}

public class StringInterpolationExpr: Expr {
  public let segments: [Expr]

  public init(segments: [Expr], sourceRange: SourceRange? = nil) {
    self.segments = segments
    super.init(sourceRange: sourceRange)
  }
}

public class PoundFunctionExpr: StringExpr {
  public init(sourceRange: SourceRange? = nil) {
    super.init(value: "", sourceRange: sourceRange)
  }
  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    return superAttrs
  }
}

public class PoundFileExpr: StringExpr {}

public class CharExpr: ConstantExpr {
  public override var type: DataType {
    get { return .int8 } set { }
  }
  public let value: UInt8
  public init(value: UInt8, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  public override var text: String {
    return value.description
  }
  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["value"] = value
    return superAttrs
  }
}

public protocol LValue {}

public class GenericContainingExpr: Expr {
  public var genericParams: [GenericParam]

  public init(genericParams: [GenericParam],
              sourceRange: SourceRange? = nil) {
    self.genericParams = genericParams
    super.init(sourceRange: sourceRange)
  }
}

public class VarExpr: GenericContainingExpr, LValue {
  public let name: Identifier
  public var isTypeVar = false
  public var isSelf = false
  public var decl: Decl? = nil
  public init(name: Identifier,
              genericParams: [GenericParam] = [],
              sourceRange: SourceRange? = nil) {
    self.name = name
    super.init(genericParams: genericParams, sourceRange: sourceRange ?? name.range)
  }
  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["name"] = name.name
    if isTypeVar {
      superAttrs["isTypeVar"] = true
    }
    return superAttrs
  }
}

public class SizeofExpr: Expr {
  public var value: Expr?
  public var valueType: DataType?
  public init(value: Expr, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
    self.type = .int64
  }
}

public class SubscriptExpr: FuncCallExpr, LValue {}

public class PropertyRefExpr: GenericContainingExpr, LValue {
  public let lhs: Expr
  public var decl: Decl? = nil
  public var typeDecl: TypeDecl? = nil
  public let name: Identifier
  public let dotLoc: SourceLocation?
  public init(lhs: Expr, name: Identifier, genericParams: [GenericParam] = [],
              dotLoc: SourceLocation? = nil,
              sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.name = name
    self.dotLoc = dotLoc
    super.init(genericParams: genericParams, sourceRange: sourceRange)
  }

  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["fieldName"] = name.name
    return superAttrs
  }
}

public class TernaryExpr: Expr {
  public let condition: Expr
  public let trueCase: Expr
  public let falseCase: Expr
  public init(condition: Expr, trueCase: Expr,
       falseCase: Expr, sourceRange: SourceRange? = nil) {
    self.condition = condition
    self.trueCase = trueCase
    self.falseCase = falseCase
    super.init(sourceRange: sourceRange)
  }
}

/// <expr> as <expr>
public class CoercionExpr: Expr {
  public let lhs: Expr
  public let rhs: TypeRefExpr
  public let asRange: SourceRange?

  public init(lhs: Expr, rhs: TypeRefExpr,
              asRange: SourceRange? = nil,
              sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.asRange = asRange
    self.rhs = rhs
    super.init(sourceRange: sourceRange)
  }
}

/// <expr> is <expr>
public class IsExpr: Expr {
  public let lhs: Expr
  public let rhs: TypeRefExpr
  public let isRange: SourceRange?

  public init(lhs: Expr, rhs: TypeRefExpr,
              isRange: SourceRange? = nil,
              sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.isRange = isRange
    self.rhs = rhs
    super.init(sourceRange: sourceRange)
  }
}
