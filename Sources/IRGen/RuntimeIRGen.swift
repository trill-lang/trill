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

  @discardableResult
  func codegenRetain(_ value: IRValue) -> IRValue {
    let cast = builder.buildBitCast(value, type: PointerType.toVoid)
    return builder.buildCall(codegenIntrinsic(named: "trill_retain"), args: [cast])
  }

  @discardableResult
  func codegenRelease(_ value: IRValue) -> IRValue {
    let cast = builder.buildBitCast(value, type: PointerType.toVoid)
    return builder.buildCall(codegenIntrinsic(named: "trill_release"), args: [cast])
  }
  
  func codegenPromoteToAny(value: IRValue, type: DataType) -> IRValue {
    if case .any = type {
      if storage(for: type) == .reference {
        // If we're promoting an existing Any value of a reference type, just
        // thread it through.
        return value
      } else {
        // If we're promoting an existing Any value of a value type, 
        // then this should just be a copy of the existing value.
        return codegenCopyAny(value: value)
      }
    }
    let allocateAny = codegenIntrinsic(named: "trill_allocateAny")
    let meta = codegenTypeMetadata(type)
    let castMeta = builder.buildBitCast(meta,
                                        type: PointerType.toVoid,
                                        name: "meta-cast")
    let res = builder.buildCall(allocateAny, args: [castMeta],
                                name: "allocate-any")
    let valPtr = codegenAnyValuePtr(res, type: type)
    builder.buildStore(value, to: valPtr)
    return res
  }
  
  func codegenCopyAny(value: IRValue) -> IRValue {
    return builder.buildCall(codegenIntrinsic(named: "trill_copyAny"),
                             args: [value], name: "copy-any")
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
  
  /// Allocates a reference-counted heap box and registers the type's
  /// deinitializer to be called when the object is deallocated.
  func codegenAllocateIndirect(type: DataType) -> VarBinding {
    let irType = resolveLLVMType(type)
    let alloc = codegenIntrinsic(named: "trill_allocateIndirectType")
    guard let typeDecl = context.decl(for: type) else {
      fatalError("no decl?")
    }

    let deinitializerTy = FunctionType(argTypes: [PointerType.toVoid],
                                       returnType: VoidType())

    let size = byteSize(of: type)
    var args = [size]
    
    if let deinitializer = typeDecl.deinitializer {
      let deinitializer = codegenFunctionPrototype(deinitializer)
      let deinitializerCast = builder.buildBitCast(deinitializer,
                                                   type: PointerType(pointee: deinitializerTy),
                                                   name: "deinitializer-cast")
      args.append(deinitializerCast)
    } else {
      args.append(PointerType(pointee: deinitializerTy).null())
    }
    let ptr = builder.buildCall(alloc, args: args, name: "ptr")
    var res = ptr
    if type != .pointer(type: .int8) {
      res = builder.buildBitCast(res, type: irType, name: "alloc-cast")
    }
    return VarBinding(ref: res,
                      storage: .reference,
                      read: { self.builder.buildLoad(res) },
                      write: { self.builder.buildStore($0, to: res) })
  }
    
  
}
