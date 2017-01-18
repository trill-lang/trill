public class ORCJIT {
    internal let llvm: LLVMExecutionEngineRef
    
    public init?(module: Module, machine: TargetMachine) {
        guard let jit = LLVMCreateOrcMCJITReplacement(module.llvm, machine.llvm) else {
            return nil
        }
        self.llvm = jit
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
