//
//  Use.swift
//  Trill
//

import Foundation

struct Use {
    let llvm: LLVMUseRef
    
    func next() -> Use? {
        guard let next = LLVMGetNextUse(llvm) else { return nil }
        return Use(llvm: next)
    }
    
    func user() -> LLVMValue? {
        return LLVMGetUser(llvm)
    }
    
    func usedValue() -> LLVMValue? {
        return LLVMGetUsedValue(llvm)
    }
}
