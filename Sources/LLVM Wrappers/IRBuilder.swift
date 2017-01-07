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
    } else if lhs is FloatType {
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
                 _ predicate: IntPredicate,
                 name: String = "") -> LLVMValue {
    let lhsVal = lhs.asLLVM()
    let rhsVal = rhs.asLLVM()
    guard lhs.type is IntType else {
      fatalError("Can only build ICMP instruction with int types")
    }
    return LLVMBuildICmp(llvm, predicate.llvm, lhsVal, rhsVal, name)
  }
  
  func addFunction(_ name: String, type: FunctionType) -> LLVMValue {
    return LLVMAddFunction(module.llvm, name, type.asLLVM())
  }
  
  func addGlobal(_ name: String, type: LLVMType) -> LLVMValue {
    return LLVMAddGlobal(module.llvm, type.asLLVM(), name)
  }
  
  func buildCall(_ fn: LLVMValue, args: [LLVMValue], name: String = "") -> LLVMValue {
    var args = args.map { $0.asLLVM() as Optional }
    return args.withUnsafeMutableBufferPointer { buf in
      return LLVMBuildCall(llvm, fn.asLLVM(), buf.baseAddress!, UInt32(buf.count), name)
    }
  }
  
  func createStruct(name: String, types: [LLVMType]) -> LLVMValue {
    let struct =  LLVMStructCreateNamed(module.context.llvm, name)
  }
  
  func buildTruncOrBitCast(_ val: LLVMValue, type: LLVMType, name: String = "") -> LLVMValue {
    return LLVMBuildTruncOrBitCast(llvm, val.asLLVM(), type.asLLVM(), name)
  }
  
  func buildGlobalString(_ string: String, name: String = "") -> LLVMValue {
    return LLVMBuildGlobalString(llvm, string, name)
  }
  
  func buildGlobalStringPtr(_ string: String, name: String = "") -> LLVMValue {
    return LLVMBuildGlobalStringPtr(llvm, string, name)
  }
}
