//
//  LLVMValue.swift
//  Trill
//

import Foundation

protocol LLVMValue {
  func asLLVM() -> LLVMValueRef
}

extension LLVMValue {
  var type: LLVMType {
    return convertType(LLVMTypeOf(asLLVM()))
  }
  var alignment: Int {
    get { return Int(LLVMGetAlignment(asLLVM())) }
    set { LLVMSetAlignment(asLLVM(), UInt32(newValue)) }
  }
  var initializer: LLVMValue {
    get { return LLVMGetInitializer(asLLVM()) }
    set { LLVMSetInitializer(asLLVM(), newValue.asLLVM()) }
  }
  
  func dump() {
    LLVMDumpValue(asLLVM())
  }
}

extension LLVMValueRef: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return self
  }
}

extension Int: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return IntType(width: MemoryLayout<Int>.size * 8).constant(UInt64(self))
  }
}

extension Int8: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return IntType(width: MemoryLayout<Int8>.size * 8).constant(UInt64(self))
  }
}

extension Int16: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return IntType(width: MemoryLayout<Int16>.size * 8).constant(UInt64(self))
  }
}

extension Int32: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return IntType(width: MemoryLayout<Int32>.size * 8).constant(UInt64(self))
  }
}

extension Int64: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return IntType(width: MemoryLayout<Int64>.size * 8).constant(UInt64(self))
  }
}

extension UInt: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return IntType(width: MemoryLayout<UInt>.size * 8).constant(UInt64(self))
  }
}

extension UInt8: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return IntType(width: MemoryLayout<UInt8>.size * 8).constant(UInt64(self))
  }
}

extension UInt16: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return IntType(width: MemoryLayout<UInt16>.size * 8).constant(UInt64(self))
  }
}

extension UInt32: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return IntType(width: MemoryLayout<UInt32>.size * 8).constant(UInt64(self))
  }
}

extension UInt64: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return IntType(width: MemoryLayout<UInt64>.size * 8).constant(self)
  }
}

extension Bool: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return IntType(width: 1).constant(UInt64(self ? 1 : 0))
  }
}

extension String: LLVMValue {
  func asLLVM() -> LLVMValueRef {
    return LLVMConstString(self, UInt32(self.utf8.count), 0)
  }
}

enum Attribute {
  case zExt, sExt, noReturn, inReg, structRet, noUnwind, noAlias
  case byVal, nest, readOnly, noInline, alwaysInline, optimizeForSize
  case stackProtect, stackProtectReq, alignment, noCapture, noRedZone
  case noImplicitFloat, naked, inlineHint, stackAlignment, returnsTwice
  case uwTable, nonLazyBind
  
  /* FIXME: These attributes are currently not included in the C API as
   a temporary measure until the API/ABI impact to the C API is understood
   and the path forward agreed upon.
   case sanitizeAddress, stackProtectStrong, cold, optimizeNone, inAlloca
   case nonNull, jumpTable, convergent, safeStack, swiftSelf, swiftError
   */
  
  static let mapping: [Attribute: LLVMAttribute] = [
    .zExt: LLVMZExtAttribute, .sExt: LLVMSExtAttribute, .noReturn: LLVMNoReturnAttribute,
    .inReg: LLVMInRegAttribute, .structRet: LLVMStructRetAttribute, .noUnwind: LLVMNoUnwindAttribute,
    .noAlias: LLVMNoAliasAttribute, .byVal: LLVMByValAttribute, .nest: LLVMNestAttribute,
    .readOnly: LLVMReadOnlyAttribute, .noInline: LLVMNoInlineAttribute, .alwaysInline: LLVMAlwaysInlineAttribute,
    .optimizeForSize: LLVMOptimizeForSizeAttribute, .stackProtect: LLVMStackProtectAttribute,
    .stackProtectReq: LLVMStackProtectReqAttribute, .alignment: LLVMAlignment,
    .noCapture: LLVMNoCaptureAttribute, .noRedZone: LLVMNoRedZoneAttribute,
    .noImplicitFloat: LLVMNoImplicitFloatAttribute, .naked: LLVMNakedAttribute,
    .inlineHint: LLVMInlineHintAttribute, .stackAlignment: LLVMStackAlignment,
    .returnsTwice: LLVMReturnsTwice, .uwTable: LLVMUWTable, .nonLazyBind: LLVMNonLazyBind
  ]
  
  func asLLVM() -> LLVMAttribute {
    return Attribute.mapping[self]!
  }
}

class Function {
  let llvm: LLVMValueRef
  internal init(llvm: LLVMValueRef) {
    self.llvm = llvm
  }
  
  func addAttribute(_ attr: Attribute) {
    LLVMAddAttribute(llvm, attr.asLLVM())
  }
}
