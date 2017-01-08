//
//  Switch.swift
//  Trill
//
//  Created by Harlan Haskins on 1/7/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

struct Switch: LLVMValue {
    let llvm: LLVMValueRef
    
    func addCase(_ value: LLVMValue, _ block: BasicBlock) {
        LLVMAddCase(llvm, value.asLLVM(), block.asLLVM())
    }
    
    func asLLVM() -> LLVMValueRef {
        return llvm
    }
}
