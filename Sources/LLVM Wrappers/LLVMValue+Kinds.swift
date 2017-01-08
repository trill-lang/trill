//
//  LLVMValue+Kinds.swift
//  Trill
//
//  Created by Harlan Haskins on 1/7/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

// Automatically generated from the macros in llvm/Core.h

extension LLVMValue {
  var isAArgument: Bool {
    return LLVMIsAArgument(asLLVM()) != nil
  }
  var isABasicBlock: Bool {
    return LLVMIsABasicBlock(asLLVM()) != nil
  }
  var isAInlineAsm: Bool {
    return LLVMIsAInlineAsm(asLLVM()) != nil
  }
  var isAUser: Bool {
    return LLVMIsAUser(asLLVM()) != nil
  }
  var isAConstant: Bool {
    return LLVMIsAConstant(asLLVM()) != nil
  }
  var isABlockAddress: Bool {
    return LLVMIsABlockAddress(asLLVM()) != nil
  }
  var isAConstantAggregateZero: Bool {
    return LLVMIsAConstantAggregateZero(asLLVM()) != nil
  }
  var isAConstantArray: Bool {
    return LLVMIsAConstantArray(asLLVM()) != nil
  }
  var isAConstantDataSequential: Bool {
    return LLVMIsAConstantDataSequential(asLLVM()) != nil
  }
  var isAConstantDataArray: Bool {
    return LLVMIsAConstantDataArray(asLLVM()) != nil
  }
  var isAConstantDataVector: Bool {
    return LLVMIsAConstantDataVector(asLLVM()) != nil
  }
  var isAConstantExpr: Bool {
    return LLVMIsAConstantExpr(asLLVM()) != nil
  }
  var isAConstantFP: Bool {
    return LLVMIsAConstantFP(asLLVM()) != nil
  }
  var isAConstantInt: Bool {
    return LLVMIsAConstantInt(asLLVM()) != nil
  }
  var isAConstantPointerNull: Bool {
    return LLVMIsAConstantPointerNull(asLLVM()) != nil
  }
  var isAConstantStruct: Bool {
    return LLVMIsAConstantStruct(asLLVM()) != nil
  }
  var isAConstantTokenNone: Bool {
    return LLVMIsAConstantTokenNone(asLLVM()) != nil
  }
  var isAConstantVector: Bool {
    return LLVMIsAConstantVector(asLLVM()) != nil
  }
  var isAGlobalValue: Bool {
    return LLVMIsAGlobalValue(asLLVM()) != nil
  }
  var isAGlobalAlias: Bool {
    return LLVMIsAGlobalAlias(asLLVM()) != nil
  }
  var isAGlobalObject: Bool {
    return LLVMIsAGlobalObject(asLLVM()) != nil
  }
  var isAFunction: Bool {
    return LLVMIsAFunction(asLLVM()) != nil
  }
  var isAGlobalVariable: Bool {
    return LLVMIsAGlobalVariable(asLLVM()) != nil
  }
  var isAUndefValue: Bool {
    return LLVMIsAUndefValue(asLLVM()) != nil
  }
  var isAInstruction: Bool {
    return LLVMIsAInstruction(asLLVM()) != nil
  }
  var isABinaryOperator: Bool {
    return LLVMIsABinaryOperator(asLLVM()) != nil
  }
  var isACallInst: Bool {
    return LLVMIsACallInst(asLLVM()) != nil
  }
  var isAIntrinsicInst: Bool {
    return LLVMIsAIntrinsicInst(asLLVM()) != nil
  }
  var isADbgInfoIntrinsic: Bool {
    return LLVMIsADbgInfoIntrinsic(asLLVM()) != nil
  }
  var isADbgDeclareInst: Bool {
    return LLVMIsADbgDeclareInst(asLLVM()) != nil
  }
  var isAMemIntrinsic: Bool {
    return LLVMIsAMemIntrinsic(asLLVM()) != nil
  }
  var isAMemCpyInst: Bool {
    return LLVMIsAMemCpyInst(asLLVM()) != nil
  }
  var isAMemMoveInst: Bool {
    return LLVMIsAMemMoveInst(asLLVM()) != nil
  }
  var isAMemSetInst: Bool {
    return LLVMIsAMemSetInst(asLLVM()) != nil
  }
  var isACmpInst: Bool {
    return LLVMIsACmpInst(asLLVM()) != nil
  }
  var isAFCmpInst: Bool {
    return LLVMIsAFCmpInst(asLLVM()) != nil
  }
  var isAICmpInst: Bool {
    return LLVMIsAICmpInst(asLLVM()) != nil
  }
  var isAExtractElementInst: Bool {
    return LLVMIsAExtractElementInst(asLLVM()) != nil
  }
  var isAGetElementPtrInst: Bool {
    return LLVMIsAGetElementPtrInst(asLLVM()) != nil
  }
  var isAInsertElementInst: Bool {
    return LLVMIsAInsertElementInst(asLLVM()) != nil
  }
  var isAInsertValueInst: Bool {
    return LLVMIsAInsertValueInst(asLLVM()) != nil
  }
  var isALandingPadInst: Bool {
    return LLVMIsALandingPadInst(asLLVM()) != nil
  }
  var isAPHINode: Bool {
    return LLVMIsAPHINode(asLLVM()) != nil
  }
  var isASelectInst: Bool {
    return LLVMIsASelectInst(asLLVM()) != nil
  }
  var isAShuffleVectorInst: Bool {
    return LLVMIsAShuffleVectorInst(asLLVM()) != nil
  }
  var isAStoreInst: Bool {
    return LLVMIsAStoreInst(asLLVM()) != nil
  }
  var isATerminatorInst: Bool {
    return LLVMIsATerminatorInst(asLLVM()) != nil
  }
  var isABranchInst: Bool {
    return LLVMIsABranchInst(asLLVM()) != nil
  }
  var isAIndirectBrInst: Bool {
    return LLVMIsAIndirectBrInst(asLLVM()) != nil
  }
  var isAInvokeInst: Bool {
    return LLVMIsAInvokeInst(asLLVM()) != nil
  }
  var isAReturnInst: Bool {
    return LLVMIsAReturnInst(asLLVM()) != nil
  }
  var isASwitchInst: Bool {
    return LLVMIsASwitchInst(asLLVM()) != nil
  }
  var isAUnreachableInst: Bool {
    return LLVMIsAUnreachableInst(asLLVM()) != nil
  }
  var isAResumeInst: Bool {
    return LLVMIsAResumeInst(asLLVM()) != nil
  }
  var isACleanupReturnInst: Bool {
    return LLVMIsACleanupReturnInst(asLLVM()) != nil
  }
  var isACatchReturnInst: Bool {
    return LLVMIsACatchReturnInst(asLLVM()) != nil
  }
  var isAFuncletPadInst: Bool {
    return LLVMIsAFuncletPadInst(asLLVM()) != nil
  }
  var isACatchPadInst: Bool {
    return LLVMIsACatchPadInst(asLLVM()) != nil
  }
  var isACleanupPadInst: Bool {
    return LLVMIsACleanupPadInst(asLLVM()) != nil
  }
  var isAUnaryInstruction: Bool {
    return LLVMIsAUnaryInstruction(asLLVM()) != nil
  }
  var isAAllocaInst: Bool {
    return LLVMIsAAllocaInst(asLLVM()) != nil
  }
  var isACastInst: Bool {
    return LLVMIsACastInst(asLLVM()) != nil
  }
  var isAAddrSpaceCastInst: Bool {
    return LLVMIsAAddrSpaceCastInst(asLLVM()) != nil
  }
  var isABitCastInst: Bool {
    return LLVMIsABitCastInst(asLLVM()) != nil
  }
  var isAFPExtInst: Bool {
    return LLVMIsAFPExtInst(asLLVM()) != nil
  }
  var isAFPToSIInst: Bool {
    return LLVMIsAFPToSIInst(asLLVM()) != nil
  }
  var isAFPToUIInst: Bool {
    return LLVMIsAFPToUIInst(asLLVM()) != nil
  }
  var isAFPTruncInst: Bool {
    return LLVMIsAFPTruncInst(asLLVM()) != nil
  }
  var isAIntToPtrInst: Bool {
    return LLVMIsAIntToPtrInst(asLLVM()) != nil
  }
  var isAPtrToIntInst: Bool {
    return LLVMIsAPtrToIntInst(asLLVM()) != nil
  }
  var isASExtInst: Bool {
    return LLVMIsASExtInst(asLLVM()) != nil
  }
  var isASIToFPInst: Bool {
    return LLVMIsASIToFPInst(asLLVM()) != nil
  }
  var isATruncInst: Bool {
    return LLVMIsATruncInst(asLLVM()) != nil
  }
  var isAUIToFPInst: Bool {
    return LLVMIsAUIToFPInst(asLLVM()) != nil
  }
  var isAZExtInst: Bool {
    return LLVMIsAZExtInst(asLLVM()) != nil
  }
  var isAExtractValueInst: Bool {
    return LLVMIsAExtractValueInst(asLLVM()) != nil
  }
  var isALoadInst: Bool {
    return LLVMIsALoadInst(asLLVM()) != nil
  }
  var isAVAArgInst: Bool {
    return LLVMIsAVAArgInst(asLLVM()) != nil
  }
}
