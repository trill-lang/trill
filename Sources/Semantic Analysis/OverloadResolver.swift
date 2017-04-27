//
//  OverloadResolver.swift
//  trill
//
//  Created by Harlan Haskins on 4/23/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

struct OverloadSolution<DeclType: FuncDecl> {
  let constraintSolution: ConstraintSolution
  let chosenDecl: FuncDecl

  /// Performs a lexicographical comparison of the severities of punishments
  /// applied to this overload solution. If one solution has a higher largest
  /// punishment, then it will be considered 'worse' than the other. Otherwise,
  /// use the number of each of the punishments applied to the solution with
  /// the same severity.
  /// - parameter other: The other solution you're comparing to.
  /// - returns: A comparison result that describes the relative fitness of
  ///            two solutions:
  ///  - `ascending` means that the receiver is worse than the
  ///     passed-in solution.
  ///
  ///  - `descending` means that the receiver is better than the
  ///    passed-in solution.
  ///
  ///  - `unordered` means both solutions are exactly the same fitness.
  func compare(to other: OverloadSolution) -> ComparisonResult {
    for kind in CoercionKind.rankedSeverities {
      switch (constraintSolution.punishments[kind],
              other.constraintSolution.punishments[kind]) {
      // If neither of them have this punishment applied, then continue.
      case (0, 0): continue

      // If the receiver's had this punishment applied, and the other hasn't,
      // then it's worse.
      case (_, 0): return .ascending

      // If the other's had this punishment applied, and the receiver hasn't,
      // then it's better.
      case (0, _): return .descending

      case let (p1, p2):
        // If they've both had the same amount of this punishment, then
        // go down a level.
        if p1 == p2 { continue }
        // Otherwise, whichever's had fewer of this punishment is better.
        return p1 < p2 ? .descending : .ascending
      }
    }

    // If everything was exactly the same, then there's an ambiguity.
    return .unordered
  }
}

enum OverloadResolution<DeclType: FuncDecl> {
  case resolved(DeclType)
  case noCandidates
  case noMatchingCandidates([DeclType])
  case ambiguity([DeclType])
}

/// Resolves overloads by choosing the overload for which the constraint system
/// had to perform the least amount of coercions and conversions to converge
/// on the solution.
struct OverloadResolver {
  /// The generator that will generate constraints for a given function
  /// call.
  let csGen: ConstraintGenerator

  /// The current environment for the generator.
  let env: ConstraintEnvironment

  /// The AST context.
  let context: ASTContext

  init(context: ASTContext, environment: ConstraintEnvironment) {
    self.context = context
    self.env = environment
    self.csGen = ConstraintGenerator(context: context)
  }

  /// Resolves the appropriate overload for the given infix operator expression.
  ///
  /// - Parameters:
  ///   - infix: The operator being resolved
  ///   - candidates: The candidates through which to search.
  /// - Returns: A resolution decision explaining exactly what was chosen by
  ///            the overload system.
  func resolve(_ infix: InfixOperatorExpr) -> OverloadResolution<OperatorDecl> {
    let args = [
      Argument(val: infix.lhs, label: nil),
      Argument(val: infix.rhs, label: nil)
    ]

    // Search through the "associated op" of the operator, to handle
    // custom implementations of `+=` and the like.
    var candidates = context.operators(for: infix.op.associatedOp ?? infix.op)

    // HACK: Until we have generic declarations solvable, make an explicit
    //       OperatorDecl for pointer comparison operators.
    // FIXME: Replace with:
    //          func ==<T>(_ a: *T, _ b: *T) -> Bool
    //          func !=<T>(_ a: *T, _ b: *T) -> Bool

    if [.equalTo, .notEqualTo].contains(infix.op) {
      let canLhs = context.canonicalType(infix.lhs.type)
      let canRhs = context.canonicalType(infix.rhs.type)
      let makePointerEqualityOps = {
          candidates += makeBoolOps(infix.op, [canLhs, canRhs])
      }
      switch (canLhs, canRhs) {
      case (.pointer(let elt1), .pointer(let elt2)) where elt1 == elt2:
        makePointerEqualityOps()
      case (.pointer, .nilLiteral), (.nilLiteral, .pointer):
        makePointerEqualityOps()
      default: break
      }
    }

    return resolve(args, candidates: candidates) { candidate in
      infix.decl = candidate
      csGen.visitInfixOperatorExpr(infix)
      infix.decl = nil
    }
  }

  /// Resolves the appropriate overload for the given function call.
  ///
  /// - Parameters:
  ///   - call: The function call being resolved
  ///   - candidates: The candidates through which to search.
  /// - Returns: A resolution decision explaining exactly what was chosen by
  ///            the overload system.
  func resolve<DeclType: FuncDecl>(_ call: FuncCallExpr,
                                   candidates: [DeclType]) -> OverloadResolution<DeclType> {
    return resolve(call.args, candidates: candidates) { candidate in
      call.decl = candidate
      if var declRef = call.lhs as? DeclRef {
        declRef.decl = candidate
      }
      csGen.visitFuncCallExpr(call)
      call.decl = nil
      if var declRef = call.lhs as? DeclRef {
        declRef.decl = nil
      }
    }
  }

  /// Resolves the appropriate overload for the given subscript.
  ///
  /// - Parameters:
  ///   - expr: The subscript being resolved
  ///   - candidates: The candidates through which to search.
  /// - Returns: A resolution decision explaining exactly what was chosen by
  ///            the overload system.
  func resolve(_ expr: SubscriptExpr, candidates: [SubscriptDecl]) -> OverloadResolution<SubscriptDecl> {
    return resolve(expr.args, candidates: candidates) { candidate in
      expr.decl = candidate
      csGen.visitSubscriptExpr(expr)
      expr.decl = nil
    }
  }

  /// Resolves the appropriate overload for the given arguments.
  ///
  /// - Parameters:
  ///   - call: The arguments to the function call being resolved
  ///   - candidates: The candidates through which to search.
  ///   - genConstraints: A closure that will generate the appropriate
  ///                     constraints for the node passed in.
  /// - Returns: A resolution decision explaining exactly what was chosen by
  ///            the overload system.
  func resolve<DeclType: FuncDecl>(_ args: [Argument],
               candidates: [DeclType],
               genConstraints: (DeclType) -> Void) -> OverloadResolution<DeclType> {
    guard !candidates.isEmpty else {
      return .noCandidates
    }
    var solutions = [OverloadSolution<DeclType>]()

    candidateSearch: for candidate in candidates {
      var declArgs = candidate.args

      // Remove the "implicit self" parameter when we're matching methods.
      if declArgs.count > 0 && declArgs[0].isImplicitSelf {
        declArgs.remove(at: 0)
      }

      if candidate.hasVarArgs {
        // Ensure the call has at least as many arguments as the candidate.
        guard args.count >= declArgs.count else {
          continue
        }
      } else {
        // Ensure the call has exactly as many arguments as the candidate.
        guard args.count == declArgs.count else {
          continue
        }
      }

      // Walk the arguments of both the call and the decl's arguments
      var index = 0
      while index < declArgs.count {
        let callArg = args[index]
        let declArg = declArgs[index]

        // Make sure the labels match for each argument
        guard callArg.label == declArg.externalName else {
          continue candidateSearch
        }
        index += 1
      }

      // For all the extra arguments in a varargs call, make sure they don't
      // have a label.
      while index < args.count {
        guard args[index].label == nil else {
          continue candidateSearch
        }
        index += 1
      }

      // If that all passed, solve the types of the function and add it to the
      // list of solutions.
      csGen.reset(with: env)
      genConstraints(candidate)
      do {
        let solution = try ConstraintSolver(context: context)
                              .solveSystem(csGen.system)
        solutions.append(OverloadSolution(constraintSolution: solution,
                                          chosenDecl: candidate))
      } catch let error as ConstraintError {
        print("Overload not accepted for candidate \(candidate.name): \(error.kind)")
      } catch {
        print("Overload not accepted for candidate \(candidate.name): \(error)")
      }
    }

    if solutions.isEmpty {
      return .noMatchingCandidates(candidates)
    }

    if solutions.count == 1 {
      return .resolved(solutions[0].chosenDecl as! DeclType)
    }

    // Keep a list of all candidates with the minimum punishments that we've seen
    var minSolutionCandidates = [OverloadSolution<DeclType>]()

    // Go through each generated solution and look for
    // the candidate(s) with the lowest score.
    for solution in solutions {
      if let candidate = minSolutionCandidates.first {
        switch candidate.compare(to: solution) {
        case .ascending:
          // This solution is better, so replace all candidates with this one
          minSolutionCandidates = [solution]
        case .descending:
          // This solution is worse, so ignore it.
          continue
        case .unordered:
          // This solution is the same as the existing, so add it to the
          // candidates with lowest score.
          minSolutionCandidates.append(solution)
        }
      } else {
        // If we don't have any solutions yet, just add it.
        minSolutionCandidates = [solution]
      }
    }

    // If we found a single candidate with the lowest score, it's our decl!
    if minSolutionCandidates.count == 1 {
      return .resolved(minSolutionCandidates[0].chosenDecl as! DeclType)
    }

    for solution in minSolutionCandidates {
      print("solution for \(solution.chosenDecl.formattedName)")
      solution.constraintSolution.dump()
    }

    // Otherwise, we have to flag an ambiguity.
    return .ambiguity(minSolutionCandidates.map { $0.chosenDecl as! DeclType })
  }
}
