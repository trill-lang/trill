//
//  ORCJIT.swift
//  Trill
//
//  Created by Harlan Haskins on 1/7/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

class ORCJIT {
    let llvm: LLVMExecutionEngineRef
    init?(module: Module, machine: TargetMachine) {
        guard let jit = LLVMCreateOrcMCJITReplacement(module.llvm, machine.llvm) else {
            return nil
        }
        self.llvm = jit
    }
    
    func runFunctionAsMain(_ function: Function, argv: [String]) -> Int {
        return argv.withCArrayOfCStrings { ptr in
            // FIXME: Allow passing in envp
            return Int(LLVMRunFunctionAsMain(llvm, function.llvm, UInt32(argv.count), ptr, nil))
        }
    }
    
    func runFunction(_ function: Function, args: [LLVMValue]) -> LLVMValue {
        var args = args.map { $0.asLLVM() as Optional }
        return args.withUnsafeMutableBufferPointer { buf in
            return LLVMRunFunction(llvm, function.llvm, UInt32(buf.count), buf.baseAddress)
        }
    }
}
