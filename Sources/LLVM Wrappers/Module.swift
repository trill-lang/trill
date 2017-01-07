//
//  Module.swift
//  Trill
//
//  Created by Harlan Haskins on 1/6/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

class Context {
    let llvm: LLVMContextRef
    static let global = Context(llvm: LLVMGetGlobalContext()!)
    init(llvm: LLVMContextRef) {
        self.llvm = llvm
    }
}

enum ModuleError: Error, CustomStringConvertible {
    case didNotPassVerification(String)
    case couldNotPrint(path: String, error: String)
    case couldNotEmitBitCode(path: String)
    
    var description: String {
        switch self {
        case .didNotPassVerification(let message):
            return "module did not pass verification: \(message)"
        case .couldNotPrint(let path, let error):
            return "could not print to file \(path): \(error)"
        case .couldNotEmitBitCode(let path):
            return "could not emit bitcode to file \(path) for an unknown reason"
        }
    }
}

class Module {
    let llvm: LLVMModuleRef
    init(name: String, context: Context? = nil) {
        if let context = context {
            llvm = LLVMModuleCreateWithNameInContext(name, context.llvm)
            self.context = context
        } else {
            llvm = LLVMModuleCreateWithName(name)
            self.context = Context(llvm: LLVMGetModuleContext(llvm)!)
        }
    }
    let context: Context
    var dataLayout: LLVMTargetDataRef {
        return LLVMGetModuleDataLayout(llvm)
    }
    
    func print(to path: String) throws {
        var err: UnsafeMutablePointer<Int8>?
        path.withCString { cString in
            let mutable = strdup(cString)
            LLVMPrintModuleToFile(llvm, mutable, &err)
            free(mutable)
        }
        if let err = err {
            defer { LLVMDisposeMessage(err) }
            throw ModuleError.couldNotPrint(path: path, error: String(cString: err))
        }
    }
    
    func emitBitCode(to path: String) throws {
        let status = path.withCString { cString -> Int32 in
            let mutable = strdup(cString)
            defer { free(mutable) }
            return LLVMWriteBitcodeToFile(llvm, mutable)
        }
        
        if status != 0 {
            throw ModuleError.couldNotEmitBitCode(path: path)
        }
    }
    
    func verify() throws {
        var message: UnsafeMutablePointer<Int8>?
        let status = Int(LLVMVerifyModule(llvm, LLVMReturnStatusAction, &message))
        if let message = message, status == 1 {
            defer { LLVMDisposeMessage(message) }
            throw ModuleError.didNotPassVerification(String(cString: message))
        }
    }
    
    func dump() {
        LLVMDumpModule(llvm)
    }
}

extension Bool {
    var llvm: LLVMBool {
        return self ? 0 : 1
    }
}
