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
    
    let ptr = UnsafeMutablePointer<LLVMTypeRef?>.allocate(capacity: expr.fields.count)
    defer { free(ptr) }
    for (idx, member) in expr.fields.enumerated() {
      ptr[idx] = resolveLLVMType(member.type)
    }
    LLVMStructSetBody(structure, ptr, UInt32(expr.fields.count), 0)
    
    for method in expr.methods {
      codegenFunctionPrototype(method)
    }
    
    if let deinitiailizer = expr.deinitializer {
      codegenFunctionPrototype(deinitiailizer)
    }
    
    return structure!
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
