//
//  BasicBlock.swift
//  Trill
//
//  Created by Harlan Haskins on 1/7/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

struct BasicBlock: LLVMValue, Sequence {
    let llvm: LLVMBasicBlockRef
    init(llvm: LLVMBasicBlockRef) {
        self.llvm = llvm
    }
    
    var firstInstruction: Instruction? {
        guard let val = LLVMGetFirstInstruction(llvm) else { return nil }
        return Instruction(llvm: val)
    }
    
    var lastInstruction: Instruction? {
        guard let val = LLVMGetLastInstruction(llvm) else { return nil }
        return Instruction(llvm: val)
    }
    
    func parent() -> BasicBlock? {
        guard let blockRef = LLVMGetBasicBlockParent(llvm) else { return nil }
        return BasicBlock(llvm: blockRef)
    }
    
    func asLLVM() -> LLVMValueRef {
        return llvm
    }
    
    func next() -> BasicBlock? {
        guard let blockRef = LLVMGetNextBasicBlock(llvm) else { return nil }
        return BasicBlock(llvm: blockRef)
    }
    
    func delete() {
        LLVMDeleteBasicBlock(llvm)
    }
    
    func removeFromParent() {
        LLVMRemoveBasicBlockFromParent(llvm)
    }
    
    func moveBefore(_ block: BasicBlock) {
        LLVMMoveBasicBlockBefore(llvm, block.llvm)
    }
    
    func moveAfter(_ block: BasicBlock) {
        LLVMMoveBasicBlockAfter(llvm, block.llvm)
    }
    
    func makeIterator() -> AnyIterator<Instruction> {
        var current = firstInstruction
        return AnyIterator {
            defer { current = current?.next() }
            return current
        }
    }
}

struct Instruction: LLVMValue {
    let llvm: LLVMValueRef
    
    init(llvm: LLVMValueRef) {
        self.llvm = llvm
    }
    
    func asLLVM() -> LLVMValueRef {
        return llvm
    }
    
    func previous() -> Instruction? {
        guard let val = LLVMGetPreviousInstruction(llvm) else { return nil }
        return Instruction(llvm: val)
    }
    
    func next() -> Instruction? {
        guard let val = LLVMGetNextInstruction(llvm) else { return nil }
        return Instruction(llvm: val)
    }
}

