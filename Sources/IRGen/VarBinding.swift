//
//  VarBinding.swift
//  Trill
//

import Foundation

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
    let ref: LLVMValueRef
    let storage: Storage
    
    let read: () -> LLVMValueRef
    let write: (LLVMValueRef) -> Void
}

enum GlobalBinding {
    case primitive(VarBinding)
    case lazy(function: LLVMValueRef, global: VarBinding)
}

