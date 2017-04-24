//
//  ConstraintSystem.swift
//  trill
//
//  Created by Harlan Haskins on 4/13/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

struct ConstraintSystem {
  private(set) var constraints: [Constraint]

  init(constraints: [Constraint] = []) {
    self.constraints = constraints
  }

  mutating func constrainConforms(_ d: Decl, _ t: DataType,
                                  caller: StaticString = #function) {
    constrainConforms(d.type, t, node: d, caller: caller)
  }

  mutating func constrainConforms(_ e: Expr, _ t: DataType,
                                  caller: StaticString = #function) {
    constrainConforms(e.type, t, node: e, caller: caller)
  }

  mutating func constrainConforms(_ t1: DataType, _ t2: DataType,
                                  node: ASTNode?,
                                  caller: StaticString = #function) {
    constraints.append(Constraint(kind: .conforms(t1, t2), location: caller,
                                  node: node))
  }

  mutating func constrainEqual(_ d: Decl, _ t: DataType,
                               caller: StaticString = #function) {
    constrainEqual(d.type, t, node: d, caller: caller)
  }

  mutating func constrainEqual(_ e: Expr, _ t: DataType,
                               caller: StaticString = #function) {
    constrainEqual(e.type, t, node: e, caller: caller)
  }

  mutating func constrainEqual(_ t1: DataType, _ t2: DataType,
                               node: ASTNode? = nil,
                               caller: StaticString = #function) {

    // Don't generate trivially equal constraints.
    if t1 == t2 {
      return
    }

    constraints.append(Constraint(kind: .equal(t1, t2),
                                  location: caller, node: node))
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
      if let node = constraint.node {
        print("  for node: \(node)")
      }
      print()
    }
  }
}
