//
//  PhiNode.swift
//  Trill
//

import Foundation

struct PhiNode: LLVMValue {
  let llvm: LLVMValueRef
  
  func addIncoming(_ valueMap: [(LLVMValue, BasicBlock)]) {
    var values = valueMap.map { $0.0.asLLVM() as Optional }
    var blocks = valueMap.map { $0.1.asLLVM() as Optional }
    
    values.withUnsafeMutableBufferPointer { valueBuf in
      blocks.withUnsafeMutableBufferPointer { blockBuf in
        LLVMAddIncoming(llvm,
                        valueBuf.baseAddress,
                        blockBuf.baseAddress,
                        UInt32(valueMap.count))
      }
    }
  }
  
  var incoming: [(LLVMValue, BasicBlock)] {
    let count = Int(LLVMCountIncoming(llvm))
    var values = [(LLVMValue, BasicBlock)]()
    for i in 0..<count {
      guard let value = incomingValue(at: i),
            let block = incomingBlock(at: i) else { continue }
      values.append((value, block))
    }
    return values
  }
  
  func incomingValue(at index: Int) -> LLVMValue? {
    return LLVMGetIncomingValue(llvm, UInt32(index))
  }
  
  func incomingBlock(at index: Int) -> BasicBlock? {
    guard let blockRef = LLVMGetIncomingBlock(llvm, UInt32(index)) else { return nil }
    return BasicBlock(llvm: blockRef)
  }
  
  func asLLVM() -> LLVMValueRef {
    return llvm
  }
}
