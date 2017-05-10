///
/// ConstraintSolver.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST

struct ConstraintSolver {
  let context: ASTContext

  /// Solves a full system of constraints, providing a full environment
  /// of concrete type-variable mappings.
  /// - parameter cs: The constraint system you're trying to solve.
  /// - returns: A full environment of concrete types to fill in the type
  ///            variables in the system.
  public func solveSystem(_ system: ConstraintSystem) -> Solution? {
    var fullSolution = ConstraintSolution(system: system)
    for constraint in system.sortedConstraints {
      let subst = constraint.substituting(fullSolution.substitutions)
      let solution = try self.solveSingle(subst)
      fullSolution.unionInPlace(solution)
    }
    return fullSolution
  }

  /// Solves a single constraint based on the set of available
  /// relationships between types in Trill.
  /// - parameter c: The constraint to solve.
  /// - returns: A `Solution`, essentially a set of bindings that concretize
  ///            all type variables present in the constraint, if any.
  /// - throws ConstraintError if the constraint is unsatisfiable.
  public func solveSingle(_ c: Constraint) -> Solution? {
    var solution = ConstraintSolution(system: ConstraintSystem(constraints: [c]))
    switch c.kind {
    case let .conforms(_t1, _t2):
      // Canonicalize types before checking.
      let t1 = context.canonicalType(_t1)
      let t2 = context.canonicalType(_t2)

      guard let typeDecl = context.decl(for: t1) else {
        throw SemaError.unknownType(type: _t1)
      }

      guard let protocolDecl = context.protocolDecl(for: t2) else {
        throw SemaError.unknownProtocol(name: Identifier(name: _t2.description))
      }

      guard context.conformsToProtocol(typeDecl, protocolDecl) else {
        throw SemaError.typeDoesNotConform(_t1, protocol: _t2)
      }

      return solution

    case let .coercion(t1, t2):
      if let solution = try? solveSingle(c.withKind(.equal(t1, t2))) {
        return solution
      }
      guard context.canCoerce(t1, to: t2) else {
        throw SemaError.cannotCoerce(type: t1, toType: t2)
      }
      return solution

    case let .equal(_t1, _t2):

      // Canonicalize types before checking.
      let t1 = context.canonicalType(_t1)
      let t2 = context.canonicalType(_t2)

      // If the two types are already equal there's nothing to be done.
      if t1 == t2 {
        return solution
      }

      switch (t1, t2) {
      case (.typeVariable, .typeVariable):
        throw ConstraintError(constraint: c,
                              kind: .ambiguousExpressionType)
      case let (t, .typeVariable(m)):
        // Perform the occurs check
        if t.contains(m) {
          fatalError("infinite type")
        }
        // Unify the type variable with the concrete type.
        solution.bind(m, to: _t1)

        if c.isExplicitTypeVariable {
          solution.punish(.genericPromotion)
        }
        return solution
      case let (.typeVariable(m), t):
        // Perform the occurs check
        if t.contains(m) {
          fatalError("infinite type")
        }

        // Unify the type variable with the concrete type.
        solution.bind(m, to: _t2)

        if c.isExplicitTypeVariable {
          solution.punish(.genericPromotion)
        }
        return solution
      case let (t, .protocolComposition(types)),
           let (.protocolComposition(types), t):
        if types.isEmpty {
          // Anything can unify to an existential
          solution.punish(.anyPromotion)
        } else {
          // Try to solve each protocol in the list.
          do {
            var system = ConstraintSystem()
            for type in types {
              system.constrainConforms(t, type, node: c.attachedNode)
            }
            var solution = try solveSystem(system)
            solution.punish(.existentialPromotion)
            return solution
          } catch {
            break
          }
        }
        return solution
      case let (.function(args1, returnType1, hasVarArgs1),
                .function(args2, returnType2, hasVarArgs2)):

        guard args1.count == args2.count || hasVarArgs1 || hasVarArgs2 else {
          break
        }

        var system = ConstraintSystem()
        for (arg1, arg2) in zip(args1, args2) {
          system.constrainEqual(arg1, arg2,
                                node: c.attachedNode,
                                caller: c.location)
        }
        system.constrainEqual(returnType1, returnType2,
                              node: c.attachedNode,
                              caller: c.location)

        // Don't propagate the error from the sub-solution directly, because
        // that makes the error needlessly specific. Generate a new error.
        do {
          return try solveSystem(system)
        } catch {
          break
        }
      case let (.pointer(t1), .pointer(t2)):
        // Don't propagate the error from the sub-solution directly, because
        // that makes the error needlessly specific. Generate a new error.
        do {
          return try solveSingle(c.withKind(.equal(t1, t2)))
        } catch {
          break
        }
      case (.stringLiteral, .pointer(DataType.int8)),
           (.pointer(DataType.int8), .stringLiteral):

        // Punish promotions from String to *Int8
        solution.punish(.stringLiteralPromotion)
        return solution
      case (.nilLiteral, .nilLiteral):
        // Assigning `nil` without context is ambiguous, always.
        throw ConstraintError(constraint: c,
                              kind: .ambiguousExpressionType)

      case (.stringLiteral, DataType.string),
           (DataType.string, .stringLiteral):
        return solution
      case let (.integerLiteral, t),
           let (t, .integerLiteral):
        switch t {
        case .int, .floating:
          // If we're promoting to anything but `Int`, then punish the solution.
          if t != .int64 {
            solution.punish(.numericLiteralPromotion)
          }
          return solution
        default: break
        }
      case let (.floatingLiteral, t),
           let (t, .floatingLiteral):
        guard case .floating = t else { break }
        // If we're promoting to anything but `Double`, then punish the solution.
        if t != .double {
          solution.punish(.numericLiteralPromotion)
        }
        return solution
      case let (.nilLiteral, t),
           let (t, .nilLiteral):
        guard context.canBeNil(t) else { break }
        return solution
      default:
        break
      }
      throw ConstraintError(constraint: c,
                            kind: .cannotConvert(_t1, to: _t2))
    }
  }
}

extension Dictionary {
  mutating func unionInPlace(_ with: Dictionary) {
    with.forEach { self.updateValue($0.1, forKey: $0.0) }
  }

 func union(_ other: Dictionary) -> Dictionary {
    var dictionary = other
    dictionary.unionInPlace(self)
    return dictionary
  }

  init<S: Sequence>(_ pairs: S) where S.Iterator.Element == (Key, Value) {
    self.init()
    var g = pairs.makeIterator()
    while let (k, v): (Key, Value) = g.next() {
      self[k] = v
    }
  }
}
