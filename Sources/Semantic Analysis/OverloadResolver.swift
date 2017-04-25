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
  /// - parameter solution: The other solution you're comparing to.
  /// - returns: `true` if this solution has been punished more than the
  ///            other.
  func compare(to other: OverloadSolution) -> ComparisonResult {
    for kind in CoercionKind.rankedSeverities {
      switch (constraintSolution.punishments[kind],
              other.constraintSolution.punishments[kind]) {
      case (nil, nil):
        continue
      case (_, nil):
        return .ascending
      case (nil, _):
        return .descending
      case let (p1?, p2?):
        if p1 == p2 { continue }
        return p1 < p2 ? .descending : .ascending
      default:
        fatalError("Unreachable")
      }
    }

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
    let candidates = context.operators(for: infix.op.associatedOp ?? infix.op)
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
  ///   - isMethodCall: Whether this represents a method call.
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

  /// Resolves the appropriate overload for the given arguments.
  ///
  /// - Parameters:
  ///   - call: The arguments to the function call being resolved
  ///   - candidates: The candidates through which to search.
  ///   - isMethodCall: Whether this represents a method call.
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
      if candidate.name == "fatalError" {

      }
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

    // Keep a list of all scores that we've seen
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
          minSolutionCandidates.append(candidate)
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

    // Otherwise, we have to flag an ambiguity.
    return .ambiguity(minSolutionCandidates.map { $0.chosenDecl as! DeclType })
  }
}
