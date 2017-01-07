//
//  TargetData.swift
//  Trill
//
//  Created by Harlan Haskins on 1/7/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

enum CodegenFileType {
    case object, assembly
    
    func asLLVM() -> LLVMCodeGenFileType {
        switch self {
        case .object: return LLVMObjectFile
        case .assembly: return LLVMAssemblyFile
        }
    }
}

enum TargetMachineError: Error, CustomStringConvertible {
    case couldNotEmit(String)
    
    var description: String {
        switch self {
        case .couldNotEmit(let message):
            return "could not emit object file: \(message)"
        }
    }
}

class TargetMachine {
    let llvm: LLVMTargetMachineRef
    init(llvm: LLVMTargetMachineRef) {
        self.llvm = llvm
    }
    private var _dataLayout: TargetData!
    var dataLayout: TargetData {
        if _dataLayout == nil {
            _dataLayout = TargetData(machine: self)
        }
        return _dataLayout
    }
    
    func emitToFile(module: Module, type: CodegenFileType, path: String) throws {
        var err: UnsafeMutablePointer<Int8>?
        let status = path.withCString { cStr -> LLVMBool in
            var mutable = strdup(cStr)
            defer { free(mutable) }
            return LLVMTargetMachineEmitToFile(llvm, module.llvm, mutable, type.asLLVM(), &err)
        }
        if let err = err, status != 0 {
            defer { LLVMDisposeMessage(err) }
            throw TargetMachineError.couldNotEmit(String(cString: err))
        }
    }
}

class TargetData {
    let llvm: LLVMTargetDataRef
    init(llvm: LLVMTargetDataRef) {
        self.llvm = llvm
    }
    init(machine: TargetMachine) {
        self.llvm = LLVMCreateTargetDataLayout(machine.llvm)
    }
}
