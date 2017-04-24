//
//  ConstraintSolution.swift
//  trill
//

import Foundation

/// Defines the kinds of automatic coercions performed by the compiler during
/// overload resolution.
enum CoercionKind {
  /// A value has been promoted to `Any`.
  case anyPromotion

  /// A numeric literal has been promoted to another Integer or Floating Point
  /// type.
  case numericLiteral

  /// An explicit type variable has been reified to a concrete type.
  case genericPromotion

  /// Defines the punishment that will be applied to a constraint
  /// solution if the type provided has to be resolved this way.
  var punishment: Int {
    switch self {
    case .anyPromotion: return 100
    case .genericPromotion: return 50
    case .numericLiteral: return 10
    }
  }
}

/// Represents a solution of a constraint system. It has a score that can
/// be used to determine if this solution is the most optimal.
struct ConstraintSolution {

  /// The constraint system being solved.
  let system: ConstraintSystem

  /// Create a ConstraintSolution for a given system.
  init(system: ConstraintSystem) {
    self.system = system
  }
  
  /// The map of type variable names to concrete data types.
  private(set) var substitutions = [String: DataType]()

  /// A score for this solution (lower is better) which will be "punished"
  /// whenever the constraint solver has to perform coercions to solve the
  /// system.
  private(set) var score = 0

  /// Punish this solution with the value from the provided coercion kind.
  mutating func punish(_ coercion: CoercionKind) {
    score += coercion.punishment
  }

  /// Adds the score and substitions from the provided solution to this
  /// solution.
  mutating func unionInPlace(_ solution: ConstraintSolution) {
    score += solution.score
    substitutions.unionInPlace(solution.substitutions)
  }

  /// Binds the type variable name provided to the concrete type provided.
  mutating func bind(_ name: String, to type: DataType) {
    substitutions[name] = type
  }
}
