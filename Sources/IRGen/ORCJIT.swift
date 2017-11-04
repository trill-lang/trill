///
/// ORCJIT.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import cllvm

// HACK:
@testable import LLVM
import LLVMWrappers

public class ORCJIT {
    internal let llvm: LLVMExecutionEngineRef

    public init?(module: Module, machine: TargetMachine) {
        let rawModule = UnsafeMutableRawPointer(module.llvm)
        let rawMachine = UnsafeMutableRawPointer(machine.llvm)
        guard let jit = LLVMCreateOrcMCJITReplacement(rawModule, rawMachine) else {
            return nil
        }
        self.llvm = LLVMExecutionEngineRef(jit)
    }

    public func runFunctionAsMain(_ function: Function, argv: [String]) -> Int {
        return argv.withCArrayOfCStrings { ptr in
            // FIXME: Allow passing in envp
            return Int(LLVMRunFunctionAsMain(llvm, function.llvm, UInt32(argv.count), ptr, nil))
        }
    }

    public func runFunction(_ function: Function, args: [IRValue]) -> IRValue {
        var args = args.map { $0.asLLVM() as Optional }
        return args.withUnsafeMutableBufferPointer { buf in
            return LLVMRunFunction(llvm, function.llvm, UInt32(buf.count), buf.baseAddress)
        }
    }
}
