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
  func codegenTypePrototype(_ expr: TypeDecl) -> IRType {
    if let existing = module.type(named: expr.name.name) {
      return existing
    }
    let structure = builder.createStruct(name: expr.name.name)
    typeIRBindings[expr.type] = structure
    let fieldTypes = expr.properties.map { resolveLLVMType($0.type) }
    structure.setBody(fieldTypes)
    
    for method in expr.methods + expr.staticMethods {
      codegenFunctionPrototype(method)
    }
    
    if let deinitiailizer = expr.deinitializer {
      codegenFunctionPrototype(deinitiailizer)
    }
    
    return structure
  }

  /// Generates type metadata for a given protocol and caches it.
  ///
  /// These are layout-compatible with the structs declared in
  /// `metadata_private.h`, namely:
  /// 
  /// ```
  /// typedef struct ProtocolMetadata {
  ///   const char *name;
  ///   const char **methodNames;
  ///   size_t methodCount;
  /// } ProtocolMetadata;
  /// ```
  /// There is a unique metadata record for every protocol at compile time.
  func codegenProtocolMetadata(_ proto: ProtocolDecl) -> Global {
    let symbol = Mangler.mangle(proto) + ".metadata"
    if let cached = module.global(named: symbol) { return cached }
    let name = builder.buildGlobalStringPtr(proto.name.name)
    let methodNames = proto.methods.map { $0.formattedName }.map {
      builder.buildGlobalStringPtr($0)
    }
    let methodNamesType = ArrayType(elementType: PointerType.toVoid,
                                    count: proto.methods.count)
    var metaNames = builder.addGlobal("\(symbol).methods", type: methodNamesType)
    metaNames.initializer = ArrayType.constant(methodNames, type: PointerType.toVoid)

    let metadata = StructType.constant(values: [
      name,
      builder.buildBitCast(metaNames, type: PointerType.toVoid),
      IntType.int64.constant(proto.methods.count)
    ])

    var metaGlobal = builder.addGlobal(symbol, type: metadata.type)
    metaGlobal.initializer = metadata

    return metaGlobal
  }
  
  /// Generates type metadata for a given type and caches it.
  ///
  /// These are layout-compatible with the structs declared in
  /// `metadata_private.h`, namely:
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
  ///   uint8_t isReferenceType;
  ///   uint64_t sizeInBits;
  ///   uint64_t fieldCount;
  ///   uint64_t pointerLevel;
  /// } TypeMetadata;
  /// ```
  ///
  /// There is a unique metadata record for every type at compile time.
  func codegenTypeMetadata(_ _type: DataType) -> Global {
    let type = context.canonicalType(_type)
    if let cached = typeMetadataMap[type] { return cached }
    var pointerLevel = 0
    let fullName = type.description
    let name = Mangler.mangle(type)
    var properties = [(String, DataType)]()
    switch type {
    case .pointer:
      pointerLevel = type.pointerLevel()
    case .custom:
      guard let decl = context.decl(for: type) else {
        fatalError("no decl?")
      }
      properties = decl.properties
                       .lazy
                       .filter { !$0.isComputed }
                       .map { ($0.name.name, $0.type) }
    case .tuple(let types):
      properties = types.enumerated().map { (".\($0.offset)", $0.element) }
    default:
      break
    }
    var irType = resolveLLVMType(type)
    var isIndirect = storage(for: type) == .reference
    
    if case .custom = type, let pointerType = irType as? PointerType {
      isIndirect = true
      irType = pointerType.pointee
    }
    
    let metaName = name + ".metadata"
    let nameValue = codegenGlobalStringPtr(fullName)
    let elementPtrs: [IRType] = [
      nameValue.type,        // name string
      PointerType.toVoid,    // field types
      IntType.int8,          // isReferenceType
      IntType.int64,         // size of type
      IntType.int64,         // number of fields
      IntType.int64          // pointer level
    ]
    let metaType = StructType(elementTypes: elementPtrs)
    
    var global = builder.addGlobal(metaName, type: metaType)
    typeMetadataMap[type] = global
    
    let propertyMetaType = StructType(elementTypes: [
      PointerType.toVoid,   // name string
      PointerType.toVoid,   // field type metadata
      IntType.int64         // field count
    ])
    
    var propertyVals = [IRValue]()
    for (idx, (propName, type)) in properties.enumerated() {
      let meta = codegenTypeMetadata(type)
      
      let name = codegenGlobalStringPtr(propName)

      propertyVals.append(StructType.constant(values: [
        builder.buildBitCast(name, type: PointerType.toVoid),
        builder.buildBitCast(meta, type: PointerType.toVoid),
        IntType.int64.constant(
          layout.offsetOfElement(at: idx, type: irType as! StructType))
      ]))
    }
    let propVec = ArrayType.constant(propertyVals, type: propertyMetaType)
    
    var globalFieldVec = builder.addGlobal("\(metaName).fields.metadata", type: propVec.type)
    globalFieldVec.initializer = propVec
    
    let gep = builder.buildInBoundsGEP(globalFieldVec, indices: [IntType.int64.zero()])
    
    global.initializer = StructType.constant(values: [
      nameValue,
      builder.buildBitCast(gep, type: PointerType.toVoid),
      IntType.int8.constant(isIndirect ? 1 : 0, signExtend: true),
      IntType.int64.constant(layout.sizeOfTypeInBits(irType), signExtend: true),
      IntType.int64.constant(properties.count, signExtend: true),
      IntType.int64.constant(pointerLevel, signExtend: true),
    ])
    return global
  }
  
  /// Declares the prototypes of all methods in an extension.
  /// - parameters:
  ///   - expr: The ExtensionDecl to declare.
  func codegenExtensionPrototype(_ expr: ExtensionDecl) {
    for method in expr.methods + expr.staticMethods {
      codegenFunctionPrototype(method)
    }
  }
  
  @discardableResult
  func visitTypeDecl(_ expr: TypeDecl) -> Result {
    codegenTypePrototype(expr)
    
    if expr.has(attribute: .foreign) { return nil }
    
    _ = expr.initializers.map(visitFuncDecl)
    _ = expr.methods.map(visitFuncDecl)
    _ = expr.deinitializer.map(visitFuncDecl)
    _ = expr.subscripts.map(visitFuncDecl)
    _ = expr.staticMethods.map(visitFuncDecl)
    _ = expr.properties.map(visitPropertyDecl)

    _ = codegenWitnessTables(expr)
    
    return nil
  }
  
  @discardableResult
  func visitExtensionDecl(_ expr: ExtensionDecl) -> Result {
    for method in expr.methods + expr.staticMethods {
      _ = visit(method)
    }
    for subscriptDecl in expr.subscripts {
      _ = visit(subscriptDecl)
    }
    return nil
  }
  
  /// Gives a valid pointer to any given Expr.
  /// PropertyRefExpr: If the property is a computed property with a getter,
  ///                  it will execute the getter, store the result in a
  ///                  stack variable, and give a pointer to that.
  ///                  Otherwise it will yield a getelementptr instruction to
  ///                  the specific field.
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
  func resolvePtr(_ expr: Expr) -> IRValue {
    let createTmpPointer: (Expr) -> IRValue = { expr in
      guard let type = expr.type else { fatalError("unknown type") }
      let value = self.visit(expr)!
      if case .any = self.context.canonicalType(type) {
        return self.codegenAnyValuePtr(value, type: .pointer(type: .int8))
      }
      let irType = self.resolveLLVMType(type)
      let alloca =  self.createEntryBlockAlloca(self.currentFunction!.functionRef!,
                                                type: irType, name: "ptrtmp",
                                                storage: .value)
      self.builder.buildStore(value, to: alloca.ref)
      return alloca.ref
    }
    switch expr {
    case let expr as PropertyRefExpr:
      // If we need to indirect through a property getter, then apply the
      // getter and store the result in a temporary mutable variable
      if let decl = expr.decl as? PropertyDecl, decl.getter != nil {
        return createTmpPointer(expr)
      }
      return elementPtr(expr)
    case let expr as VarExpr:
      guard let binding = resolveVarBinding(expr) else {
        fatalError("no binding?")
      }
      return binding.ref
    case let expr as PrefixOperatorExpr where expr.op == .star:
      return builder.buildLoad(resolvePtr(expr.rhs), name: "deref-load")
    case let expr as TupleFieldLookupExpr:
      let lhs = resolvePtr(expr.lhs)
      return builder.buildStructGEP(lhs, index: expr.field, name: "tuple-ptr")
    case let expr as InfixOperatorExpr where expr.op == .as:
      if let type = expr.type, case .any = context.canonicalType(type) {
        return codegenAnyValuePtr(visit(expr)!, type: expr.rhs.type!)
      }
      return createTmpPointer(expr)
    case let expr as SubscriptExpr:
      let lhs = visit(expr.lhs)!
      switch expr.lhs.type! {
      case .pointer, .array:
        return builder.buildGEP(lhs, indices: [visit(expr.args[0].val)!],
                                name: "gep")
      default:
        return createTmpPointer(expr)
      }
    default:
      return createTmpPointer(expr)
    }
  }
  
  /// Builds a getelementptr instruction for a PropertyRefExpr.
  /// This will perform the arithmetic necessary to get at a struct field.
  func elementPtr(_ expr: PropertyRefExpr) -> IRValue {
    guard let decl = expr.typeDecl else { fatalError("unresolved type") }
    guard let idx = decl.indexOfProperty(named: expr.name) else {
      fatalError("invalid index in decl fields")
    }
    var ptr = resolvePtr(expr.lhs)
    let isImplicitSelf = (expr.lhs as? VarExpr)?.isSelf ?? false
    if case .reference = storage(for: expr.lhs.type!),
      !isImplicitSelf {
      ptr = builder.buildLoad(ptr, name: "\(expr.name)-load")
    }
    return builder.buildStructGEP(ptr, index: idx, name: "\(expr.name)-gep")
  }
  
  func visitPropertyRefExpr(_ expr: PropertyRefExpr) -> Result {
    if let propDecl = expr.decl as? PropertyDecl,
       let getterDecl = propDecl.getter {
      let implicitSelf = resolvePtr(expr.lhs)
      let getterFn = codegenFunctionPrototype(getterDecl)
      return builder.buildCall(getterFn, args: [implicitSelf])
    }
    return builder.buildLoad(elementPtr(expr), name: expr.name.name)
  }
}
