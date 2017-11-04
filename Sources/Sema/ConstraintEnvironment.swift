///
/// ConstraintEnvironment.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
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
