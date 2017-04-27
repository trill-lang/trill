///
/// ConstraintError.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import Foundation

enum ConstraintErrorKind: CustomStringConvertible {
  case ambiguousExpressionType
  case cannotConvert(DataType, to: DataType)

  var description: String {
    switch self {
    case .ambiguousExpressionType:
      return "type of expression is ambiguous without more context"
    case let .cannotConvert(t1, t2):
      return "cannot convert value of type \(t1) to \(t2)"
    }
  }
}

struct ConstraintError: Error, CustomStringConvertible {
  let constraint: Constraint
  let kind: ConstraintErrorKind

  var description: String {
    return kind.description
  }
}
