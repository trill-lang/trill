//
//  RuntimeIRGen.swift
//  Trill
//

import Foundation

extension IRGenerator {
  
  func codegenIntrinsic(named name: String) -> LLVMValueRef {
    guard let decl = context.functions(named: Identifier(name: name)).first else {
      fatalError("No intrinsic \(name)")
    }
    return codegenFunctionPrototype(decl)!
  }
  
  /// Allocates a heap box in the garbage collector, and registers a finalizer
  /// specified by that type's deinit.
  func codegenAlloc(type: DataType) -> VarBinding {
    let irType = resolveLLVMType(type)
    let alloc = codegenIntrinsic(named: "trill_alloc")
    let register = codegenIntrinsic(named: "trill_registerDeinitializer")
    guard let typeDecl = context.decl(for: type, canonicalized: true) else { fatalError("no decl?") }
    var size = LLVMBuildTruncOrBitCast(builder, LLVMSizeOf(irType), LLVMInt32Type(), "")
    let ptr = LLVMBuildCall(builder, alloc, &size, 1, "ptr")!
    var res = ptr
    if type != .pointer(type: .int8) {
      res = LLVMBuildBitCast(builder, res, irType, "alloc-cast")
    }
    
    if let deinitializer = typeDecl.deinitializer {
      var voidPointerTy = LLVMPointerType(LLVMInt8Type(), 0)
      var deinitializerTy = LLVMFunctionType(LLVMVoidType(), &voidPointerTy, 1, 0)
      let deinitializer = codegenFunctionPrototype(deinitializer)
      let args = UnsafeMutablePointer<LLVMValueRef?>.allocate(capacity: 2)
      let deinitializerCast = LLVMBuildBitCast(builder, deinitializer,
                                            LLVMPointerType(deinitializerTy, 0),
                                            "deinitializer-cast")
      defer { free(args) }
      args[0] = ptr
      args[1] = deinitializerCast
      LLVMBuildCall(builder, register, args, 2, "")
    }
    return VarBinding(ref: res, storage: .reference)
  }
}
