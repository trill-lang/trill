///
/// ConstraintSystem.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import Foundation

struct ConstraintSystem {
  private(set) var constraints: [Constraint]

  init(constraints: [Constraint] = []) {
    self.constraints = constraints
  }

  mutating func constrainConforms(_ d: Decl, _ t: DataType,
                                  isExplicitTypeVariable: Bool = false,
                                  caller: StaticString = #function) {
    constrainConforms(d.type, t, node: d,
                      isExplicitTypeVariable: isExplicitTypeVariable,
                      caller: caller)
  }

  mutating func constrainConforms(_ e: Expr, _ t: DataType,
                                  isExplicitTypeVariable: Bool = false,
                                  caller: StaticString = #function) {
    constrainConforms(e.type, t, node: e,
                      isExplicitTypeVariable: isExplicitTypeVariable,
                      caller: caller)
  }

  mutating func constrainConforms(_ t1: DataType, _ t2: DataType,
                                  node: ASTNode?,
                                  isExplicitTypeVariable: Bool = false,
                                  caller: StaticString = #function) {
    constraints.append(Constraint(kind: .conforms(t1, t2), location: caller,
                                  attachedNode: node,
                                  isExplicitTypeVariable: isExplicitTypeVariable))
  }

  mutating func constrainEqual(_ d: Decl, _ t: DataType,
                               isExplicitTypeVariable: Bool = false,
                               caller: StaticString = #function) {
    constrainEqual(d.type, t, node: d,
                   isExplicitTypeVariable: isExplicitTypeVariable,
                   caller: caller)
  }

  mutating func constrainEqual(_ e: Expr, _ t: DataType,
                               isExplicitTypeVariable: Bool = false,
                               caller: StaticString = #function) {
    constrainEqual(e.type, t, node: e,
                   isExplicitTypeVariable: isExplicitTypeVariable,
                   caller: caller)
  }

  mutating func constrainEqual(_ t1: DataType, _ t2: DataType,
                               node: ASTNode? = nil,
                               isExplicitTypeVariable: Bool = false,
                               caller: StaticString = #function) {

    // Don't generate trivially equal constraints.
    if t1 == t2 {
      return
    }

    constraints.append(Constraint(kind: .equal(t1, t2),
                                  location: caller, attachedNode: node,
                                  isExplicitTypeVariable: isExplicitTypeVariable))
  }

  func dump() {
    for constraint in constraints {
      switch constraint.kind {
      case let .equal(t1, t2):
        print("\(t1) == \(t2)")
      case let .conforms(t1, t2):
        print("\(t1): \(t2)")
      }
      print("  declared in: \(constraint.location)")
      if let node = constraint.attachedNode {
        print("  for node: \(node)")
      }
      if constraint.isExplicitTypeVariable {
        print("  explicit type variable: true")
      }
    }
  }
}
