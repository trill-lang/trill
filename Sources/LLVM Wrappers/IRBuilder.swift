//
//  IRBuilder.swift
//  Trill
//
//  Created by Harlan Haskins on 1/6/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

enum OverflowBehavior {
  case `default`, noSignedWrap, noUnsignedWrap
}

enum IntPredicate {
  case eq, ne, ugt, uge, ult, ule, sgt, sge, slt, sle
  static let predicateMapping: [IntPredicate: LLVMIntPredicate] = [
    .eq: LLVMIntEQ, .ne: LLVMIntNE, .ugt: LLVMIntUGT, .uge: LLVMIntUGE,
    .ult: LLVMIntULT, .ule: LLVMIntULE, .sgt: LLVMIntSGT, .sge: LLVMIntSGE,
    .slt: LLVMIntSLT, .sle: LLVMIntSLE
  ]
  var llvm: LLVMIntPredicate {
    return IntPredicate.predicateMapping[self]!
  }
}

enum RealPredicate {
  case `false`, oeq, ogt, oge, olt, ole, one, ord, uno, ueq, ugt, uge, ult, ule
  case une, `true`
  
  static let predicateMapping: [RealPredicate: LLVMRealPredicate] = [
    .false: LLVMRealPredicateFalse, .oeq: LLVMRealOEQ, .ogt: LLVMRealOGT,
    .oge: LLVMRealOGE, .olt: LLVMRealOLT, .ole: LLVMRealOLE,
    .one: LLVMRealONE, .ord: LLVMRealORD, .uno: LLVMRealUNO,
    .ueq: LLVMRealUEQ, .ugt: LLVMRealUGT, .uge: LLVMRealUGE,
    .ult: LLVMRealULT, .ule: LLVMRealULE, .une: LLVMRealUNE,
    .true: LLVMRealPredicateTrue,
  ]
  
  var llvm: LLVMRealPredicate {
    return RealPredicate.predicateMapping[self]!
  }
}

class IRBuilder {
  let llvm: LLVMBuilderRef
  let module: Module
  
  init(module: Module) {
    self.module = module
    self.llvm = LLVMCreateBuilderInContext(module.context.llvm)
  }
  
  var insertBlock: BasicBlock? {
    guard let blockRef = LLVMGetInsertBlock(llvm) else { return nil }
    return BasicBlock(llvm: blockRef)
  }
  
  func buildAdd(_ lhs: LLVMValue, _ rhs: LLVMValue,
                overflowBehavior: OverflowBehavior = .default,
                name: String = "") -> LLVMValue {
    let lhsVal = lhs.asLLVM()
    let rhsVal = rhs.asLLVM()
    if lhs.type is IntType {
      switch overflowBehavior {
      case .noSignedWrap:
        return LLVMBuildNSWAdd(llvm, lhsVal, rhsVal, name)
      case .noUnsignedWrap:
        return LLVMBuildNUWAdd(llvm, lhsVal, rhsVal, name)
      case .default:
        return LLVMBuildAdd(llvm, lhsVal, rhsVal, name)
      }
    } else if lhs.type is FloatType {
      return LLVMBuildFAdd(llvm, lhsVal, rhsVal, name)
    }
    fatalError("Can only add value of int, float, or vector types")
  }
  
  func buildNeg(_ value: LLVMValue,
                overflowBehavior: OverflowBehavior = .default,
                name: String = "") -> LLVMValue {
    let val = value.asLLVM()
    if value.type is IntType {
      switch overflowBehavior {
      case .noSignedWrap:
        return LLVMBuildNSWNeg(llvm, val, name)
      case .noUnsignedWrap:
        return LLVMBuildNUWNeg(llvm, val, name)
      case .default:
        return LLVMBuildNeg(llvm, val, name)
      }
    } else if value.type is FloatType {
      return LLVMBuildFNeg(llvm, val, name)
    }
    fatalError("Can only negate value of int or float types")
  }
  
  func buildNot(_ val: LLVMValue, name: String = "") -> LLVMValue {
    return LLVMBuildNot(llvm, val.asLLVM(), name)
  }
  
  func buildSub(_ lhs: LLVMValue, _ rhs: LLVMValue,
                overflowBehavior: OverflowBehavior = .default,
                name: String = "") -> LLVMValue {
    let lhsVal = lhs.asLLVM()
    let rhsVal = rhs.asLLVM()
    if lhs.type is IntType {
      switch overflowBehavior {
      case .noSignedWrap:
        return LLVMBuildNSWSub(llvm, lhsVal, rhsVal, name)
      case .noUnsignedWrap:
        return LLVMBuildNSWSub(llvm, lhsVal, rhsVal, name)
      case .default:
        return LLVMBuildSub(llvm, lhsVal, rhsVal, name)
      }
    } else if lhs.type is FloatType {
      return LLVMBuildFSub(llvm, lhsVal, rhsVal, name)
    }
    fatalError("Can only subtract value of int or float types")
  }
  
  func buildMul(_ lhs: LLVMValue, _ rhs: LLVMValue,
                overflowBehavior: OverflowBehavior = .default,
                name: String = "") -> LLVMValue {
    let lhsVal = lhs.asLLVM()
    let rhsVal = rhs.asLLVM()
    if lhs.type is IntType {
      switch overflowBehavior {
      case .noSignedWrap:
        return LLVMBuildNSWMul(llvm, lhsVal, rhsVal, name)
      case .noUnsignedWrap:
        return LLVMBuildNUWMul(llvm, lhsVal, rhsVal, name)
      case .default:
        return LLVMBuildMul(llvm, lhsVal, rhsVal, name)
      }
    } else if lhs.type is FloatType {
      return LLVMBuildFMul(llvm, lhsVal, rhsVal, name)
    }
    fatalError("Can only multiply value of int or float types")
  }
  
  func buildXor(_ lhs: LLVMValue, _ rhs: LLVMValue, name: String = "") -> LLVMValue {
    return LLVMBuildXor(llvm, lhs.asLLVM(), rhs.asLLVM(), name)
  }
  
  func buildOr(_ lhs: LLVMValue, _ rhs: LLVMValue, name: String = "") -> LLVMValue {
    return LLVMBuildOr(llvm, lhs.asLLVM(), rhs.asLLVM(), name)
  }
  
  func buildAnd(_ lhs: LLVMValue, _ rhs: LLVMValue, name: String = "") -> LLVMValue {
    return LLVMBuildAnd(llvm, lhs.asLLVM(), rhs.asLLVM(), name)
  }
  func buildShl(_ lhs: LLVMValue, _ rhs: LLVMValue,
                name: String = "") -> LLVMValue {
    return LLVMBuildShl(llvm, lhs.asLLVM(), rhs.asLLVM(), name)
  }
  func buildShr(_ lhs: LLVMValue, _ rhs: LLVMValue,
                 isArithmetic: Bool = false,
                 name: String = "") -> LLVMValue {
    if isArithmetic {
      return LLVMBuildAShr(llvm, lhs.asLLVM(), rhs.asLLVM(), name)
    } else {
      return LLVMBuildLShr(llvm, lhs.asLLVM(), rhs.asLLVM(), name)
    }
  }
  
  func buildRem(_ lhs: LLVMValue, _ rhs: LLVMValue,
                signed: Bool = true,
                name: String = "") -> LLVMValue {
    let lhsVal = lhs.asLLVM()
    let rhsVal = rhs.asLLVM()
    if lhs.type is IntType {
      if signed {
        return LLVMBuildSRem(llvm, lhsVal, rhsVal, name)
      } else {
        return LLVMBuildURem(llvm, lhsVal, rhsVal, name)
      }
    } else if lhs.type is FloatType {
      return LLVMBuildFRem(llvm, lhsVal, rhsVal, name)
    }
    fatalError("Can only take remainder of int or float types")
  }
  
  func buildDiv(_ lhs: LLVMValue, _ rhs: LLVMValue,
                signed: Bool = true, name: String = "") -> LLVMValue {
    let lhsVal = lhs.asLLVM()
    let rhsVal = rhs.asLLVM()
    if lhs.type is IntType {
      if signed {
        return LLVMBuildSDiv(llvm, lhsVal, rhsVal, name)
      } else {
        return LLVMBuildUDiv(llvm, lhsVal, rhsVal, name)
      }
    } else if lhs.type is FloatType {
      return LLVMBuildFDiv(llvm, lhsVal, rhsVal, name)
    }
    fatalError("Can only divide values of int or float types")
  }
  
  func buildICmp(_ lhs: LLVMValue, _ rhs: LLVMValue,
                 _ predicate: IntPredicate,
                 name: String = "") -> LLVMValue {
    let lhsVal = lhs.asLLVM()
    let rhsVal = rhs.asLLVM()
    guard lhs.type is IntType else {
      fatalError("Can only build ICMP instruction with int types")
    }
    return LLVMBuildICmp(llvm, predicate.llvm, lhsVal, rhsVal, name)
  }
  
  func buildFCmp(_ lhs: LLVMValue, _ rhs: LLVMValue,
                 _ predicate: RealPredicate,
                 name: String = "") -> LLVMValue {
    let lhsVal = lhs.asLLVM()
    let rhsVal = rhs.asLLVM()
    guard lhs.type is FloatType else {
      fatalError("Can only build FCMP instruction with float types")
    }
    return LLVMBuildFCmp(llvm, predicate.llvm, lhsVal, rhsVal, name)
  }
  
  func buildPhi(_ type: LLVMType, name: String = "") -> PhiNode {
    let value = LLVMBuildPhi(llvm, type.asLLVM(), name)!
    return PhiNode(llvm: value)
  }
  
  func addFunction(_ name: String, type: FunctionType) -> Function {
    return Function(llvm: LLVMAddFunction(module.llvm, name, type.asLLVM()))
  }
  
  func addGlobal(_ name: String, type: LLVMType) -> Global {
    return Global(llvm: LLVMAddGlobal(module.llvm, type.asLLVM(), name))
  }
  
  func buildAlloca(type: LLVMType, name: String = "") -> LLVMValue {
    return LLVMBuildAlloca(llvm, type.asLLVM(), name)
  }
  
  @discardableResult
  func buildBr(_ block: BasicBlock) -> LLVMValue {
    return LLVMBuildBr(llvm, block.llvm)
  }
  
  @discardableResult
  func buildCondBr(condition: LLVMValue, then: BasicBlock, `else`: BasicBlock) -> LLVMValue {
    return LLVMBuildCondBr(llvm, condition.asLLVM(), then.asLLVM(), `else`.asLLVM())
  }
  
  @discardableResult
  func buildRet(_ val: LLVMValue) -> LLVMValue {
    return LLVMBuildRet(llvm, val.asLLVM())
  }
  
  @discardableResult
  func buildRetVoid() -> LLVMValue {
    return LLVMBuildRetVoid(llvm)
  }
  
  @discardableResult
  func buildUnreachable() -> LLVMValue {
    return LLVMBuildUnreachable(llvm)
  }
  
  @discardableResult
  func buildCall(_ fn: LLVMValue, args: [LLVMValue], name: String = "") -> LLVMValue {
    var args = args.map { $0.asLLVM() as Optional }
    return args.withUnsafeMutableBufferPointer { buf in
      return LLVMBuildCall(llvm, fn.asLLVM(), buf.baseAddress!, UInt32(buf.count), name)
    }
  }
  
  func buildSwitch(_ value: LLVMValue, else: BasicBlock, caseCount: Int) -> Switch {
    return Switch(llvm: LLVMBuildSwitch(llvm,
                                        value.asLLVM(),
                                        `else`.asLLVM(),
                                        UInt32(caseCount))!)
  }
  
  func createStruct(name: String, types: [LLVMType]? = nil, isPacked: Bool = false) -> StructType {
    let named = LLVMStructCreateNamed(module.context.llvm, name)!
    let type = StructType(llvm: named)
    if let types = types {
      type.setBody(types)
    }
    return type
  }
  
  @discardableResult
  func buildStore(_ val: LLVMValue, to ptr: LLVMValue) -> LLVMValue {
    return LLVMBuildStore(llvm, val.asLLVM(), ptr.asLLVM())
  }
  
  func buildLoad(_ ptr: LLVMValue, name: String = "") -> LLVMValue {
    return LLVMBuildLoad(llvm, ptr.asLLVM(), name)
  }
  
  func buildInBoundsGEP(_ ptr: LLVMValue, indices: [LLVMValue], name: String = "") -> LLVMValue {
    var vals = indices.map { $0.asLLVM() as Optional }
    return vals.withUnsafeMutableBufferPointer { buf in
      return LLVMBuildInBoundsGEP(llvm, ptr.asLLVM(), buf.baseAddress, UInt32(buf.count), name)
    }
  }
  
  func buildGEP(_ ptr: LLVMValue, indices: [LLVMValue], name: String = "") -> LLVMValue {
    var vals = indices.map { $0.asLLVM() as Optional }
    return vals.withUnsafeMutableBufferPointer { buf in
      return LLVMBuildGEP(llvm, ptr.asLLVM(), buf.baseAddress, UInt32(buf.count), name)
    }
  }
  
  func buildStructGEP(_ ptr: LLVMValue, index: Int, name: String = "") -> LLVMValue {
      return LLVMBuildStructGEP(llvm, ptr.asLLVM(), UInt32(index), name)
  }
  
  func buildIsNull(_ val: LLVMValue, name: String = "") -> LLVMValue {
    return LLVMBuildIsNull(llvm, val.asLLVM(), name)
  }
  
  func buildIsNotNull(_ val: LLVMValue, name: String = "") -> LLVMValue {
    return LLVMBuildIsNotNull(llvm, val.asLLVM(), name)
  }
  
  func buildTruncOrBitCast(_ val: LLVMValue, type: LLVMType, name: String = "") -> LLVMValue {
    return LLVMBuildTruncOrBitCast(llvm, val.asLLVM(), type.asLLVM(), name)
  }
  
  func buildBitCast(_ val: LLVMValue, type: LLVMType, name: String = "") -> LLVMValue {
    return LLVMBuildBitCast(llvm, val.asLLVM(), type.asLLVM(), name)
  }
  
  func buildSExt(_ val: LLVMValue, type: LLVMType, name: String = "") -> LLVMValue {
    return LLVMBuildSExt(llvm, val.asLLVM(), type.asLLVM(), name)
  }
  
  func buildZExt(_ val: LLVMValue, type: LLVMType, name: String = "") -> LLVMValue {
    return LLVMBuildZExt(llvm, val.asLLVM(), type.asLLVM(), name)
  }
  
  func buildTrunc(_ val: LLVMValue, type: LLVMType, name: String = "") -> LLVMValue {
    return LLVMBuildTrunc(llvm, val.asLLVM(), type.asLLVM(), name)
  }
  
  func buildIntToPtr(_ val: LLVMValue, type: PointerType, name: String = "") -> LLVMValue {
    return LLVMBuildIntToPtr(llvm, val.asLLVM(), type.asLLVM(), name)
  }
  
  func buildPtrToInt(_ val: LLVMValue, type: IntType, name: String = "") -> LLVMValue {
    return LLVMBuildIntToPtr(llvm, val.asLLVM(), type.asLLVM(), name)
  }
  
  func buildIntToFP(_ val: LLVMValue, type: FloatType, signed: Bool, name: String = "") -> LLVMValue {
    if signed {
      return LLVMBuildSIToFP(llvm, val.asLLVM(), type.asLLVM(), name)
    } else {
      return LLVMBuildUIToFP(llvm, val.asLLVM(), type.asLLVM(), name)
    }
  }
  
  func buildFPToInt(_ val: LLVMValue, type: IntType, signed: Bool, name: String = "") -> LLVMValue {
    if signed {
      return LLVMBuildFPToSI(llvm, val.asLLVM(), type.asLLVM(), name)
    } else {
      return LLVMBuildFPToUI(llvm, val.asLLVM(), type.asLLVM(), name)
    }
  }
  
  func buildSizeOf(_ val: LLVMType) -> LLVMValue {
    return LLVMSizeOf(val.asLLVM())
  }
  
  func buildInsertValue(aggregate: LLVMValue, element: LLVMValue, index: Int, name: String = "") -> LLVMValue {
    return LLVMBuildInsertValue(llvm, aggregate.asLLVM(), element.asLLVM(), UInt32(index), name)
  }
  
  func buildInsertElement(vector: LLVMValue, element: LLVMValue, index: LLVMValue, name: String = "") -> LLVMValue {
    return LLVMBuildInsertElement(llvm, vector.asLLVM(), element.asLLVM(), index.asLLVM(), name)
  }
  
  func buildGlobalString(_ string: String, name: String = "") -> LLVMValue {
    return LLVMBuildGlobalString(llvm, string, name)
  }
  
  func buildGlobalStringPtr(_ string: String, name: String = "") -> LLVMValue {
    return LLVMBuildGlobalStringPtr(llvm, string, name)
  }
  
  func positionAtEnd(of block: BasicBlock) {
    LLVMPositionBuilderAtEnd(llvm, block.llvm)
  }
  
  func positionBefore(_ inst: LLVMValue) {
    LLVMPositionBuilderBefore(llvm, inst.asLLVM())
  }
  
  func position(_ inst: LLVMValue, block: BasicBlock) {
    LLVMPositionBuilder(llvm, block.llvm, inst.asLLVM())
  }
}
