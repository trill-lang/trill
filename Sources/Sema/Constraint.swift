///
/// Constraint.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import Foundation

/// Describes the kinds of constraints we can use to solve type variables.
struct Constraint {
  enum Kind {
    /// The two types must be substitutable for each other.
    case equal(DataType, DataType)

    /// The first type must be convertible to the second type. This can be any
    /// kind of conversion the compiler can perform through an `as` cast.
    /// For example, integer size conversions. `someVar as Int8` will yield a
    /// `conversion` constraint.
    case conversion(DataType, DataType)

    /// The first type must conform to the second type. The second type must be
    /// a protocol or protocol composition type to solve this constraint.
    case conforms(DataType, DataType)
  }

  /// The kind of constraint generated here
  let kind: Kind

  /// The name of the function that generated this constraint.
  let location: StaticString

  /// The node that this constraint applies to.
  let attachedNode: ASTNode?

  /// Whether this constraint makes a reference to a type variable written by
  /// the programmer, instead of a type variable generated during inference.
  let isExplicitTypeVariable: Bool

  /// Substitutes the types inside this constraint with the provided solution
  /// set.
  func substituting(_ solution: [String: DataType]) -> Constraint {
    switch kind {
    case let .equal(t1, t2):
      return withKind(.equal(t1.substitute(solution),
                             t2.substitute(solution)))
    case let .conforms(t1, t2):
      return withKind(.conforms(t1.substitute(solution),
                                t2.substitute(solution)))
    case let .conversion(t1, t2):
      return withKind(.conversion(t1.substitute(solution),
                                t2.substitute(solution)))
    }
  }

  /// Returns a new constraint based on the provided constraint, but by updating
  /// the kind of constraint.
  func withKind(_ kind: Kind) -> Constraint {
    return Constraint(kind: kind, location: location,
                      attachedNode: attachedNode,
                      isExplicitTypeVariable: isExplicitTypeVariable)
  }
}
