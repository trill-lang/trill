//
//  RuntimeIRGen.swift
//  Trill
//

import Foundation

extension IRGenerator {
  
  func codegenIntrinsic(named name: String) -> Function {
    let identifier = Identifier(name: name)
    let matchingDecls = context.functions(named: identifier)
    let intrinsicDecl = matchingDecls.first { decl in
      decl.has(attribute: .implicit)
    }
    guard let decl = intrinsicDecl else {
      fatalError("No intrinsic \(name)")
    }
    return codegenFunctionPrototype(decl)
  }
  
  @discardableResult
  func codegenOnceCall(function: IRValue) -> (token: IRValue, call: IRValue) {
    var token = builder.addGlobal("once_token", type: IntType.int64)
    token.initializer = IntType.int64.zero()
    let call = builder.buildCall(codegenIntrinsic(named: "trill_once"),
                                 args: [token, function])
    return (token: token, call: call)
  }

  func createMemset() -> Function {
    let name = "llvm.memset.p0i8.i64"
    if let existing = module.function(named: name) {
      return existing
    }
    let type = FunctionType(argTypes: [PointerType.toVoid, IntType.int8,
                                       IntType.int64, IntType.int32, IntType.int1],
                            returnType: VoidType())
    return builder.addFunction(name, type: type)
  }

  func codegenMemset(pointer: IRValue, type: DataType, initial: Int8) {
    let memsetFn = createMemset()
    let cast = builder.buildBitCast(pointer, type: PointerType.toVoid)
    let irType = resolveLLVMType(type)
    _ = builder.buildCall(memsetFn, args: [
      cast, initial,
      module.dataLayout.abiSizeOfType(irType),
      IntType.int32.constant(0),
      false
    ])
  }
  
  func codegenPromoteToAny(value: IRValue, type: DataType) -> IRValue {
    if case .any = type {
      // If we're promoting an existing Any value of a reference type, just
      // thread it through.
      return value
    }
    let irType = resolveLLVMType(type)
    let meta = codegenTypeMetadata(type)
    let castMeta = builder.buildBitCast(meta,
                                        type: PointerType.toVoid,
                                        name: "meta-cast")
    let anyTy = createAnyType()
    let anyPtr = createEntryBlockAlloca(currentFunction!.functionRef!,
                                        type: anyTy,
                                        name: "any",
                                        storage: .value)
    codegenMemset(pointer: anyPtr.ref, type: .any, initial: 0)

    let metaGEP = builder.buildStructGEP(anyPtr.ref, index: 1,
                                         name: "any-meta-gep")
    builder.buildStore(castMeta, to: metaGEP)

    let anyGEP = builder.buildBitCast(builder.buildStructGEP(anyPtr.ref, index: 0,
                                                             name: "any-value-gep"),
                                      type: PointerType.toVoid,
                                      name: "any-cast-value-gep")

    // Any includes a 24-byte payload. If the size of this type is going to
    // be larger than that, we need to heap-allocate the value and use it to
    // initialize the any.
    if targetMachine.dataLayout.sizeOfTypeInBits(irType) > 24 * 8 {
      let alloc = codegenAlloc(type: type)
      let store = builder.buildBitCast(anyGEP, type: alloc.ref.type,
                                       name: "any-cast-store-box")
      alloc.write(value)
      builder.buildStore(alloc.read(), to: store)
    } else {
      let cast = builder.buildBitCast(anyGEP,
                                      type: PointerType(pointee: irType),
                                      name: "any-cast-store-value")
      builder.buildStore(value, to: cast)
    }
    return anyPtr.read()
  }
  
  func codegenAnyValuePtr(_ binding: IRValue, type: DataType) -> IRValue {
    let irType = resolveLLVMType(type)
    let pointerType = PointerType(pointee: irType)
    let ptrValue = builder.buildCall(codegenIntrinsic(named: "trill_getAnyValuePtr"),
                                     args: [binding])
    return builder.buildBitCast(ptrValue, type: pointerType, name: "cast-ptr")
  }
  
  /// Creates a runtime type check expression between an Any expression and
  /// a data type
  ///
  /// - Parameters:
  ///   - binding: The Any binding
  ///   - type: The type to check
  /// - Returns: An i1 value telling if the Any value has the same underlying
  ///            type as the passed-in type
  func codegenTypeCheck(_ binding: IRValue, type: DataType) -> IRValue {
    let typeCheck = codegenIntrinsic(named: "trill_checkTypes")
    let meta = codegenTypeMetadata(type)
    let castMeta = builder.buildBitCast(meta, type: PointerType.toVoid, name: "meta-cast")
    let result = builder.buildCall(typeCheck, args: [binding, castMeta])
    return builder.buildICmp(result, IntType.int8.zero(), .notEqual, name: "type-check-result")
  }
  
  func codegenCheckedCast(binding: IRValue, type: DataType) -> IRValue {
    let checkedCast = codegenIntrinsic(named: "trill_checkedCast")
    let meta = codegenTypeMetadata(type)
    let castMeta = builder.buildBitCast(meta,
                                        type: PointerType.toVoid,
                                        name: "meta-cast")
    let res = builder.buildCall(checkedCast, args: [binding, castMeta])
    let irType = resolveLLVMType(type)
    let castResult = builder.buildBitCast(res,
                                          type: PointerType(pointee: irType),
                                          name: "cast-result")
    return builder.buildLoad(castResult, name: "cast-load")
  }
  
  /// Allocates a heap box in the garbage collector, and registers a finalizer
  /// specified by that type's deinit.
  func codegenAlloc(type: DataType) -> VarBinding {
    var irType = resolveLLVMType(type)
    if !context.isIndirect(type) {
      irType = PointerType(pointee: irType)
    }
    let alloc = codegenIntrinsic(named: "trill_alloc")
    let register = codegenIntrinsic(named: "trill_registerDeinitializer")
    guard let typeDecl = context.decl(for: type, canonicalized: true) else {
      fatalError("no decl?")
    }
    let size = byteSize(of: type)
    let ptr = builder.buildCall(alloc, args: [size], name: "ptr")
    var res = ptr
    if type != .pointer(type: .int8) {
      res = builder.buildBitCast(res, type: irType, name: "alloc-cast")
    }
    
    if let deinitializer = typeDecl.deinitializer {
      let deinitializerTy = FunctionType(argTypes: [PointerType.toVoid],
                                         returnType: VoidType())
      let deinitializer = codegenFunctionPrototype(deinitializer)
      let deinitializerCast = builder.buildBitCast(deinitializer,
                                                   type: PointerType(pointee: deinitializerTy),
                                                   name: "deinitializer-cast")
      _ = builder.buildCall(register, args: [ptr, deinitializerCast])
    }
    return VarBinding(ref: res,
                      storage: .reference,
                      read: { self.builder.buildLoad(res) },
                      write: { self.builder.buildStore($0, to: res) })
  }
    
  
}
