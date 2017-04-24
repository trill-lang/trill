//
//  OverloadResolver.swift
//  trill
//
//  Created by Harlan Haskins on 4/23/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

struct OverloadSolution {
  let constraintSolution: ConstraintSolution
  let chosenDecl: FuncDecl
}

enum OverloadResolution {
  case resolved(FuncDecl)
  case noCandidates
  case noMatchingCandidates
  case ambiguity([FuncDecl])
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

  /// Resolves the appropriate overload for the given function call.
  ///
  /// - Parameters:
  ///   - call: The call being resolved
  ///   - candidates: The candidates through which to search.
  /// - Returns: A resolution decision explaining exactly what was chosen by
  ///            the overload system.
  func resolve(call: FuncCallExpr, candidates: [FuncDecl]) -> OverloadResolution {
    guard !candidates.isEmpty else {
      return .noCandidates
    }

    let isMethodCall = call.lhs.semanticsProvidingExpr is PropertyRefExpr
    var solutions = [OverloadSolution]()

    candidateSearch: for candidate in candidates {
      var declArgs = candidate.args

      if isMethodCall {
        // Ensure we're calling a method when we have a propertyref.
        guard candidate is MethodDecl else { continue }

        // Remove the "implicit self" parameter when we're matching methods.
        declArgs.remove(at: 0)
      }

      if candidate.hasVarArgs {
        // Ensure the call has at least as many arguments as the candidate.
        guard call.args.count >= declArgs.count else { continue }
      } else {
        // Ensure the call has exactly as many arguments as the candidate.
        guard call.args.count == declArgs.count else { continue }
      }

      // Walk the arguments of both the call and the decl's arguments
      var index = 0
      while index < declArgs.count {
        let callArg = call.args[index]
        let declArg = declArgs[index]

        // Make sure the labels match for each argument
        guard callArg.label == declArg.externalName else {
          continue candidateSearch
        }
        index += 1
      }

      // For all the extra arguments in a varargs call, make sure they don't
      // have a label.
      while index < call.args.count {
        guard call.args[index].label == nil else {
          continue
        }
        index += 1
      }

      // If that all passed, solve the types of the function and add it to the
      // list of solutions.
      call.decl = candidate
      csGen.reset(with: ConstraintEnvironment())
      csGen.visitFuncCallExpr(call)
      guard let solution = ConstraintSolver(context: context)
                            .solveSystem(csGen.system) else {
        call.decl = nil
        continue
      }
      solutions.append(OverloadSolution(constraintSolution: solution,
                                        chosenDecl: candidate))
    }

    if solutions.isEmpty {
      return .noMatchingCandidates
    }

    // Keep a list of all scores that we've seen
    var minScore = Int.max
    var minScoreCandidates = [OverloadSolution]()

    // Go through each generated solution and look for
    // the candidate(s) with the lowest score.
    for solution in solutions {
      let score = solution.constraintSolution.score

      if score == minScore {
        minScoreCandidates.append(solution)
      } else if score < minScore {
        minScore = score
        minScoreCandidates = [solution]
      } else {
        continue
      }
    }

    // If we found a single candidate with the lowest score, it's our decl!
    if minScoreCandidates.count == 1 {
      return .resolved(minScoreCandidates[0].chosenDecl)
    }

    // Otherwise, we have to flag an ambiguity.
    return .ambiguity(minScoreCandidates.map { $0.chosenDecl })
  }
}
