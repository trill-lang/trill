//
//  VarBinding.swift
//  Trill
//

import Foundation
import LLVMSwift

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
    let ref: LLVMValue
    let storage: Storage
    
    let read: () -> LLVMValue
    let write: (LLVMValue) -> Void
}

enum GlobalBinding {
    case primitive(VarBinding)
    case lazy(function: LLVMValue, global: VarBinding)
}

