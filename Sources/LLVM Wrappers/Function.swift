import Foundation

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

class Function: LLVMValue {
  let llvm: LLVMValueRef
  internal init(llvm: LLVMValueRef) {
    self.llvm = llvm
  }
  
  var entryBlock: BasicBlock? {
    guard let blockRef = LLVMGetEntryBasicBlock(llvm) else { return nil }
    return BasicBlock(llvm: blockRef)
  }
  
  var firstBlock: BasicBlock? {
    guard let blockRef = LLVMGetFirstBasicBlock(llvm) else { return nil }
    return BasicBlock(llvm: blockRef)
  }
  
  var lastBlock: BasicBlock? {
    guard let blockRef = LLVMGetLastBasicBlock(llvm) else { return nil }
    return BasicBlock(llvm: blockRef)
  }
  
  var basicBlocks: [BasicBlock] {
    var blocks = [BasicBlock]()
    var current = firstBlock
    while let block = current {
      blocks.append(block)
      current = block.next()
    }
    return blocks
  }
  
  func parameter(at index: Int) -> Parameter? {
    guard let value = LLVMGetParam(llvm, UInt32(index)) else { return nil }
    return Parameter(llvm: value)
  }
  
  var firstParameter: Parameter? {
    guard let value = LLVMGetFirstParam(llvm) else { return nil }
    return Parameter(llvm: value)
  }
  
  var lastParameter: Parameter? {
    guard let value = LLVMGetLastParam(llvm) else { return nil }
    return Parameter(llvm: value)
  }
  
  var parameters: [LLVMValue] {
    var current = firstParameter
    var params = [Parameter]()
    while let param = current {
      params.append(param)
      current = param.next()
    }
    return params
  }
  
  func appendBasicBlock(named name: String, in context: Context? = nil) -> BasicBlock {
    let block: LLVMBasicBlockRef
    if let context = context {
      block = LLVMAppendBasicBlockInContext(context.llvm, llvm, name)
    } else {
      block = LLVMAppendBasicBlock(llvm, name)
    }
    return BasicBlock(llvm: block)
  }
  
  func asLLVM() -> LLVMValueRef {
    return llvm
  }
}

struct Parameter: LLVMValue {
  let llvm: LLVMValueRef
  
  func next() -> Parameter? {
    guard let param = LLVMGetNextParam(llvm) else { return nil }
    return Parameter(llvm: param)
  }
  
  func asLLVM() -> LLVMValueRef {
    return llvm
  }
}
