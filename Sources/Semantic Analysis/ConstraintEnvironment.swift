//
//  ConstraintEnvironment.swift
//  trill
//
//  Created by Harlan Haskins on 4/12/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

struct ConstraintEnvironment {
  private var typeVariablePool = 0
  private(set) var mapping = [Identifier: DataType]()

  subscript(_ name: Identifier) -> DataType? {
    get { return mapping[name] }
    set { mapping[name] = newValue }
  }

  mutating func freshTypeVariable() -> DataType {
    defer { typeVariablePool += 1 }
    return .typeVariable(name: "T\(typeVariablePool)")
  }
}
