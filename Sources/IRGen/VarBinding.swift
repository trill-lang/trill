///
/// VarBinding.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import Foundation
import LLVM

/// Possible ways a binding should be accessed. Determines if a binding
/// is a value or reference type, and
enum Storage {
    /// The binding will always be passed by value into functions.
    case value

    /// The binding will always be passed by reference into functions
    case reference
}

/// Represents a variable binding and its corresponding binding type.
struct VarBinding {
    let ref: IRValue
    let storage: Storage

    let read: () -> IRValue
    let write: (IRValue) -> Void
}

enum GlobalBinding {
    case primitive(VarBinding)
    case lazy(function: IRValue, global: VarBinding)
}
