//
//  ConstraintSolution.swift
//  trill
//

import Foundation

/// Defines the kinds of automatic coercions performed by the compiler during
/// overload resolution. These are declared in order of severity.
enum CoercionKind: Int {
  /// A value has been promoted to `Any`.
  case anyPromotion

  /// A value has been promoted to an existential that isn't `Any`.
  case existentialPromotion

  /// An explicit type variable has been reified to a concrete type.
  case genericPromotion

  /// A string literal has been promoted to *Int8.
  case stringLiteralPromotion

  /// A numeric literal has been promoted to another Integer or Floating Point
  /// type.
  case numericLiteralPromotion

  /// The severity of this specific coercion kind, used for comparing two
  /// overload resolution solutions.
  var severity: Int {
    return rawValue
  }

  /// The severities of each coercion kind, in order.
  static var rankedSeverities: [CoercionKind] {
    return [.anyPromotion, .existentialPromotion, .genericPromotion,
            .stringLiteralPromotion, .numericLiteralPromotion]
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

  /// A map to keep track of the number of each kind of punishment applied
  /// to this solution.
  private(set) var punishments = Counter<CoercionKind>()

  /// Punish this solution with the value from the provided coercion kind.
  mutating func punish(_ coercion: CoercionKind) {
    punishments.count(coercion)
  }

  /// Whether this solution has been punished with the given punishment.
  func has(punishment: CoercionKind) -> Bool {
    return punishments[punishment] != 0
  }

  func hasAny(_ punishments: CoercionKind...) -> Bool {
    for kind in punishments where has(punishment: kind) { return true }
    return false
  }

  /// Whether this solution has been punished by any punishments.
  var isPunished: Bool {
    return !punishments.isEmpty
  }

  /// Adds the score and substitions from the provided solution to this
  /// solution.
  mutating func unionInPlace(_ solution: ConstraintSolution) {
    punishments.addCounts(from: solution.punishments)
    substitutions.unionInPlace(solution.substitutions)
  }

  /// Binds the type variable name provided to the concrete type provided.
  mutating func bind(_ name: String, to type: DataType) {
    substitutions[name] = type
  }

  func dump() {
    print("\n|======= Constraint Solution =======")
    print("|  =====     Constraints     =====")
    system.dump()

    print("|  =====    Substitutions    =====")
    for (variable, substitution) in substitutions {
      print("|    \(variable) : \(substitution)")
    }
    print("|  =====     Punishments     =====")
    for (kind, count) in punishments {
      print("|    \(kind) x \(count)")
    }
    print("|===== End Constraint Solution =====\n")
  }
}
