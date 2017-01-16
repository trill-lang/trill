import cllvm

// HAAAAAAACK because this file
@testable import LLVM

public class ORCJIT {
    internal let llvm: LLVMExecutionEngineRef
    
    public init?(module: Module, machine: TargetMachine) {
        guard let jit = LLVMCreateOrcMCJITReplacement(
            unsafeBitCast(module.llvm, to: UnsafeMutableRawPointer.self),
            unsafeBitCast(machine.llvm, to: UnsafeMutableRawPointer.self)) else {
            return nil
        }
        self.llvm = unsafeBitCast(jit, to: LLVMExecutionEngineRef.self)
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
