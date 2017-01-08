//
//  Switch.swift
//  Trill
//
//  Created by Harlan Haskins on 1/7/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

public struct Switch: LLVMValue {
    internal let llvm: LLVMValueRef
    
    public func addCase(_ value: LLVMValue, _ block: BasicBlock) {
        LLVMAddCase(llvm, value.asLLVM(), block.asLLVM())
    }
    
    public func asLLVM() -> LLVMValueRef {
        return llvm
    }
}
