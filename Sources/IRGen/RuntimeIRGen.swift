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
  
  func codegenPromoteToAny(value: LLVMValueRef, type: DataType) -> LLVMValueRef {
    if case .any = type {
      // If we're promoting an existing Any value, then this should just be a
      // copy of the existing value.
      return codegenCopyAny(value: value)
    }
    let irType = resolveLLVMType(type)
    let allocateAny = codegenIntrinsic(named: "trill_allocateAny")
    let meta = codegenTypeMetadata(type)
    var castMeta = LLVMBuildBitCast(builder, meta, LLVMPointerType(LLVMInt8Type(), 0), "meta-cast")
    let res = LLVMBuildCall(builder, allocateAny, &castMeta,
                            1, "allocate-any")!
    let valPtr = codegenAnyValuePtr(res, type: type)
    let ptr = LLVMBuildBitCast(builder, valPtr,
                               LLVMPointerType(irType, 0), "")
    LLVMBuildStore(builder, value, ptr)
    return res
  }
  
  func codegenCopyAny(value: LLVMValueRef) -> LLVMValueRef {
    return buildCall(codegenIntrinsic(named: "trill_copyAny"), args: [value])
  }
  
  @discardableResult
  func buildCall(_ function: LLVMValueRef, args: [LLVMValueRef], resultName: String = "") -> LLVMValueRef {
    var mutArgs: [LLVMValueRef?] = args
    return mutArgs.withUnsafeMutableBufferPointer { buf in
      LLVMBuildCall(builder, function, buf.baseAddress, UInt32(buf.count), resultName)
    }
  }
  
  func codegenAnyValuePtr(_ binding: LLVMValueRef, type: DataType) -> LLVMValueRef {
    let irType = resolveLLVMType(type)
    let pointerType = LLVMPointerType(irType, 0)
    let ptrValue = buildCall(codegenIntrinsic(named: "trill_getAnyValuePtr"), args: [binding])
    return LLVMBuildBitCast(builder, ptrValue, pointerType, "cast-ptr")
  }
  
  /// Creates a runtime type check expression between an Any expression and
  /// a data type
  ///
  /// - Parameters:
  ///   - binding: The Any binding
  ///   - type: The type to check
  /// - Returns: An i1 value telling if the Any value has the same underlying
  ///            type as the passed-in type
  func codegenTypeCheck(_ binding: LLVMValueRef, type: DataType) -> LLVMValueRef {
    let typeCheck = codegenIntrinsic(named: "trill_checkTypes")
    let meta = codegenTypeMetadata(type)
    let castMeta = LLVMBuildBitCast(builder, meta, LLVMPointerType(LLVMInt8Type(), 0), "meta-cast")!
    var args: [LLVMValueRef?] = [binding, castMeta]
    let result = args.withUnsafeMutableBufferPointer { buf in
      LLVMBuildCall(builder, typeCheck, buf.baseAddress, UInt32(buf.count), "type-check")!
    }
    return LLVMBuildICmp(builder, LLVMIntNE, result, LLVMConstNull(LLVMInt8Type()), "type-check-result")
  }
  
  func codegenCheckedCast(binding: LLVMValueRef, type: DataType) -> LLVMValueRef {
    let checkedCast = codegenIntrinsic(named: "trill_checkedCast")
    let meta = codegenTypeMetadata(type)
    let castMeta = LLVMBuildBitCast(builder, meta, LLVMPointerType(LLVMInt8Type(), 0), "meta-cast")
    var args = [binding, castMeta]
    let res = args.withUnsafeMutableBufferPointer { buf in
      return LLVMBuildCall(builder, checkedCast, buf.baseAddress,
                           UInt32(buf.count), "checked-cast")!
    }
    let irType = resolveLLVMType(type)
    let castResult = LLVMBuildBitCast(builder, res, LLVMPointerType(irType, 0), "cast-result")
    return LLVMBuildLoad(builder, castResult, "cast-load")!
  }
  
  /// Allocates a heap box in the garbage collector, and registers a finalizer
  /// specified by that type's deinit.
  func codegenAlloc(type: DataType) -> VarBinding {
    let irType = resolveLLVMType(type)
    let alloc = codegenIntrinsic(named: "trill_alloc")
    let register = codegenIntrinsic(named: "trill_registerDeinitializer")
    guard let typeDecl = context.decl(for: type, canonicalized: true) else { fatalError("no decl?") }
    var size = byteSize(of: type)
    let ptr = LLVMBuildCall(builder, alloc, &size, 1, "ptr")!
    var res = ptr
    if type != .pointer(type: .int8) {
      res = LLVMBuildBitCast(builder, res, irType, "alloc-cast")
    }
    
    if let deinitializer = typeDecl.deinitializer {
      var voidPointerTy = LLVMPointerType(LLVMInt8Type(), 0)
      let deinitializerTy = LLVMFunctionType(LLVMVoidType(), &voidPointerTy, 1, 0)
      let deinitializer = codegenFunctionPrototype(deinitializer)
      let deinitializerCast = LLVMBuildBitCast(builder, deinitializer,
                                            LLVMPointerType(deinitializerTy, 0),
                                            "deinitializer-cast")
      var args: [LLVMValueRef?] = [ptr, deinitializerCast]
      _ = args.withUnsafeMutableBufferPointer { buf in
        LLVMBuildCall(builder, register, buf.baseAddress, UInt32(buf.count), "")
      }
    }
    return VarBinding(ref: res, storage: .reference)
  }
    
  
}
