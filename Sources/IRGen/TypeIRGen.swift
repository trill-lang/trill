//
//  TypeIRGen.swift
//  Trill
//

import Foundation

extension IRGenerator {
  
  /// Declares the prototypes of all methods and initializers,
  /// and deinitializer, in a type.
  /// - parameters:
  ///   - expr: The TypeDecl to declare.
  @discardableResult
  func codegenTypePrototype(_ expr: TypeDecl) -> LLVMTypeRef {
    let existing = LLVMGetTypeByName(module, expr.name.name)
    if existing != nil { return existing! }
    let structure = LLVMStructCreateNamed(llvmContext, expr.name.name)
    typeIRBindings[expr.type] = structure
    
    var fieldTys: [LLVMTypeRef?] = expr.fields.map { resolveLLVMType($0.type) }
    _ = fieldTys.withUnsafeMutableBufferPointer { buf in
      LLVMStructSetBody(structure, buf.baseAddress, UInt32(buf.count), 0)
    }
    
    for method in expr.methods {
      codegenFunctionPrototype(method)
    }
    
    if let deinitiailizer = expr.deinitializer {
      codegenFunctionPrototype(deinitiailizer)
    }
    
    return structure!
  }
  
  /// Generates type metadata for a given type and caches it.
  ///
  /// These are layout-compatible with the structs declared in runtime.cpp,
  /// namely:
  ///
  /// ```
  /// typedef struct FieldMetadata {
  ///   const char *name;
  ///   const void *type;
  /// } FieldMetadata;
  ///
  /// typedef struct TypeMetadata {
  ///   const char *name;
  ///   const void *fields;
  ///   uint64_t sizeInBits;
  ///   uint64_t fieldCount;
  ///   uint64_t pointerLevel;
  /// } TypeMetadata;
  /// ```
  ///
  /// There is a unique metadata record for every type at compile time.
  /// This function should only be called when generating the intrinsic
  /// typeOf(_: Any) function, as it will only generate the metadata requested.
  func codegenTypeMetadata(_ _type: DataType) -> LLVMValueRef? {
    let type = context.canonicalType(_type)
    if let cached = typeMetadataMap[type] { return cached }
    var pointerLevel = 0
    let fullName = "\(type)"
    let name = Mangler.mangle(type)
    var fields = [VarAssignDecl]()
    switch type {
    case .pointer:
      pointerLevel = type.pointerLevel()
    case .custom:
      guard let decl = context.decl(for: type) else { return nil }
      fields = decl.fields
    default:
      break
    }
    let llvmType = resolveLLVMType(type)
    let voidPointerTy = LLVMPointerType(LLVMInt8Type(), 0)
    var fieldMetaElts = [
      voidPointerTy,         // name string
      voidPointerTy          // type
    ]
    let fieldMetaTy = fieldMetaElts.withUnsafeMutableBufferPointer { buf in
      LLVMStructType(buf.baseAddress, UInt32(buf.count), 0)
    }
    
    let metaName = name + ".metadata"
    let nameValue = codegenGlobalStringPtr(fullName)
    var elementPtrs = [
      LLVMTypeOf(nameValue), // name string
      voidPointerTy,         // field types
      LLVMInt64Type(),       // size of type
      LLVMInt64Type(),       // number of fields
      LLVMInt64Type()        // pointer level
    ]
    let metaType = elementPtrs.withUnsafeMutableBufferPointer { buf in
       LLVMStructType(buf.baseAddress, UInt32(buf.count), 0)
    }
    
    let global = LLVMAddGlobal(module, metaType, metaName)!
    typeMetadataMap[type] = global
    
    var fieldVals = [LLVMValueRef?]()
    for field in fields {
      guard let meta = codegenTypeMetadata(field.type) else {
        LLVMDeleteGlobal(global)
        typeMetadataMap[type] = nil
        return nil
      }
      let name = codegenGlobalStringPtr(field.name.name)
      var values = [
        LLVMBuildBitCast(builder, name, voidPointerTy, ""),
        LLVMBuildBitCast(builder, meta, voidPointerTy, "")
      ]
      fieldVals.append(values.withUnsafeMutableBufferPointer { buf in
        LLVMConstStruct(buf.baseAddress, UInt32(buf.count), 0)
      })
    }
    
    
    let fieldVec = fieldVals.withUnsafeMutableBufferPointer { buf in
      LLVMConstArray(fieldMetaTy, buf.baseAddress, UInt32(buf.count))
    }
    
    let globalFieldVec = LLVMAddGlobal(module, LLVMTypeOf(fieldVec), "\(metaName).fields.metadata")
    
    LLVMSetInitializer(globalFieldVec, fieldVec)
    
    var index = LLVMConstNull(LLVMInt64Type())
    let gep = LLVMBuildInBoundsGEP(builder, globalFieldVec, &index, 1, "")
    
    var vals = [
      nameValue,
      LLVMBuildBitCast(builder, gep, LLVMPointerType(LLVMInt8Type(), 0), ""),
      LLVMConstInt(LLVMInt64Type(), LLVMSizeOfTypeInBits(layout, llvmType), 0),
      LLVMConstInt(LLVMInt64Type(), UInt64(fields.count), 1),
      LLVMConstInt(LLVMInt64Type(), UInt64(pointerLevel), 1)
    ]
    _ = vals.withUnsafeMutableBufferPointer { buf in
      LLVMSetInitializer(global, LLVMConstStruct(buf.baseAddress, UInt32(buf.count), 0))
    }
    return global
  }
  
  /// Declares the prototypes of all methods in an extension.
  /// - parameters:
  ///   - expr: The ExtensionDecl to declare.
  @discardableResult
  func codegenExtensionPrototype(_ expr: ExtensionDecl) {
    for method in expr.methods {
      codegenFunctionPrototype(method)
    }
  }
  
  @discardableResult
  func visitTypeDecl(_ expr: TypeDecl) -> Result {
    let structure = codegenTypePrototype(expr)
    
    if expr.has(attribute: .foreign) { return structure }
    
    _ = expr.initializers.map(visitFuncDecl)
    _ = expr.methods.map(visitFuncDecl)
    _ = expr.deinitializer.map(visitFuncDecl)
    
    return structure
  }
  
  @discardableResult
  func visitExtensionDecl(_ expr: ExtensionDecl) -> Result {
    for method in expr.methods {
      _ = visit(method)
    }
    return nil
  }
  
  /// Gives a valid pointer to any given Expr.
  /// FieldLookupExpr: it will yield a getelementptr instruction.
  /// VarExpr: it'll look through any variable bindings to find the
  ///          pointer that represents the value. For reference bindings, it'll
  ///          yield the underlying pointer. For value bindings, it'll yield the
  ///          global or stack binding.
  /// Dereference: It will get a pointer to the dereferenced value and load it
  /// Subscript: It will codegen the argument and get the pointer it represents,
  ///            and build a getelementptr for the offset.
  /// Anything else: It will create a new stack object and return that pointer.
  ///                This allows you to call a method on an rvalue, even though
  ///                it doesn't necessarily have a stack variable.
  func resolvePtr(_ expr: Expr) -> Result {
    switch expr {
    case let expr as FieldLookupExpr:
      return elementPtr(expr)
    case let expr as VarExpr:
      guard case (_, let binding?) = resolveVarBinding(expr) else {
        fatalError("no binding?")
      }
      return binding.ref
    case let expr as PrefixOperatorExpr where expr.op == .star:
      return LLVMBuildLoad(builder, resolvePtr(expr.rhs), "deref-load")
    case let expr as SubscriptExpr:
      let lhs = visit(expr.lhs)
      var indices = visit(expr.amount)
      return LLVMBuildGEP(builder, lhs, &indices, 1, "gep")
    case let expr as TupleFieldLookupExpr:
      let lhs = resolvePtr(expr.lhs)
      return LLVMBuildStructGEP(builder, lhs, UInt32(expr.field), "tuple-ptr")
    default:
      guard let type = expr.type else { fatalError("unknown type") }
      let llvmType = resolveLLVMType(type)
      let alloca =  createEntryBlockAlloca(currentFunction!.functionRef!,
                                           type: llvmType, name: "ptrtmp",
                                           storage: .value)
      LLVMBuildStore(builder, visit(expr), alloca.ref)
      return alloca.ref
    }
  }
  
  /// Builds a getelementptr instruction for a FieldLookupExpr.
  /// This will perform the arithmetic necessary to get at a struct field.
  func elementPtr(_ expr: FieldLookupExpr) -> Result {
    guard let decl = expr.typeDecl else { fatalError("unresolved type") }
    guard let idx = decl.indexOf(fieldName: expr.name) else {
      fatalError("invalid index in decl fields")
    }
    var ptr = resolvePtr(expr.lhs)
    let isImplicitSelf = (expr.lhs as? VarExpr)?.isSelf ?? false
    if case .reference = storage(for: expr.lhs.type!),
      !isImplicitSelf {
      ptr = LLVMBuildLoad(builder, ptr, "field-load")
    }
    return LLVMBuildStructGEP(builder, ptr, UInt32(idx), "field-gep")
  }
  
  func visitFieldLookupExpr(_ expr: FieldLookupExpr) -> Result {
    let gep = elementPtr(expr)
    return LLVMBuildLoad(builder, gep, expr.name.name)
  }
}
