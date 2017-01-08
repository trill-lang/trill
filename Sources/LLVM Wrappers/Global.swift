//
//  Global.swift
//  Trill
//
//  Created by Harlan Haskins on 1/7/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

struct Global: LLVMValue {
    let llvm: LLVMValueRef
    
    var isExternallyInitialized: Bool {
        get { return LLVMIsExternallyInitialized(llvm) != 0 }
        set { LLVMSetExternallyInitialized(llvm, newValue.llvm) }
    }
    
    var initializer: LLVMValue {
        get { return LLVMGetInitializer(asLLVM()) }
        set { LLVMSetInitializer(asLLVM(), newValue.asLLVM()) }
    }
    
    var isGlobalConstant: Bool {
        get { return LLVMIsGlobalConstant(asLLVM()) != 0 }
        set { LLVMSetGlobalConstant(asLLVM(), newValue.llvm) }
    }
    
    var isThreadLocal: Bool {
        get { return LLVMIsThreadLocal(asLLVM()) != 0 }
        set { LLVMSetThreadLocal(asLLVM(), newValue.llvm) }
    }
    
    func asLLVM() -> LLVMValueRef {
        return llvm
    }
}
