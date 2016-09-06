//
//  FunctionIRGen.swift
//  Trill
//

import Foundation

extension IRGenerator {
  
  func createEntryBlockAlloca(_ function: LLVMValueRef,
                              type: LLVMTypeRef,
                              name: String,
                              storage: Storage,
                              initial: LLVMValueRef? = nil) -> VarBinding {
    let currentBlock = LLVMGetInsertBlock(builder)
    let entryBlock = LLVMGetEntryBasicBlock(function)
    LLVMPositionBuilder(builder, entryBlock, LLVMGetFirstInstruction(entryBlock))
    let alloca = LLVMBuildAlloca(builder, type, name)!
    LLVMPositionBuilderAtEnd(builder, currentBlock)
    if let initial = initial {
      LLVMBuildStore(builder, initial, alloca)
    }
    return VarBinding(ref: alloca, storage: storage)
  }
  
  @discardableResult
  func codegenFunctionPrototype(_ expr: FuncDecl) -> Result {
    let mangled = Mangler.mangle(expr)
    let existing = LLVMGetNamedFunction(module, mangled)
    if existing != nil { return existing }
    var argTys = [LLVMTypeRef?]()
    for arg in expr.args {
      var type = resolveLLVMType(arg.type)
      if arg.isImplicitSelf && storage(for: arg.type) != .reference {
        type = LLVMPointerType(type, 0)
      }
      argTys.append(type)
    }
    let type = resolveLLVMType(expr.returnType)
    let fType = argTys.withUnsafeMutableBufferPointer { buf in
      LLVMFunctionType(type, buf.baseAddress, UInt32(buf.count),
                                 expr.hasVarArgs ? 1 : 0)
    }
    return LLVMAddFunction(module, mangled, fType)
  }
  
  func visitBreakStmt(_ expr: BreakStmt) -> Result {
    guard currentBreakTarget != nil else {
      fatalError("break outside loop")
    }
    return LLVMBuildBr(builder, currentBreakTarget)
  }
  
  func visitContinueStmt(_ stmt: ContinueStmt) -> Result {
    guard currentContinueTarget != nil else {
      fatalError("continue outside loop")
    }
    return LLVMBuildBr(builder, currentContinueTarget)
  }

  func synthesizeIntializer(_ expr: FuncDecl, function: LLVMValueRef) -> LLVMValueRef {
    guard expr.isInitializer,
        let body = expr.body,
        body.exprs.isEmpty,
      let type = expr.returnType.type,
        let typeDecl = context.decl(for: type) else {
      fatalError("must synthesize an empty initializer")
    }
    let entryBB = LLVMAppendBasicBlock(function, "entry")
    LLVMPositionBuilderAtEnd(builder, entryBB)
    
    var retLLVMType = resolveLLVMType(type)
    if typeDecl.isIndirect {
      retLLVMType = LLVMGetElementType(retLLVMType)
    }
    var initial = LLVMConstNull(retLLVMType)!
    for (idx, arg) in expr.args.enumerated() {
      let param = LLVMGetParam(function, UInt32(idx))!
      LLVMSetValueName(param, arg.name.name)
      initial = LLVMBuildInsertValue(builder, initial, param, UInt32(idx), "init-insert")
    }
    if typeDecl.isIndirect {
      let result = codegenAlloc(type: type).ref
      LLVMBuildStore(builder, initial, result)
      LLVMBuildRet(builder, result)
    } else {
      LLVMBuildRet(builder, initial)
    }
    return function
  }
  
  func visitOperatorDecl(_ decl: OperatorDecl) -> LLVMValueRef? {
    return visitFuncDecl(decl)
  }
  
  func visitFuncDecl(_ expr: FuncDecl) -> Result {
    let function = codegenFunctionPrototype(expr)!
    
    if expr === context.mainFunction {
      mainFunction = function
    }
    
    if expr.has(attribute: .foreign) { return function }
    
    if expr.isInitializer, let body = expr.body, body.exprs.isEmpty {
      return synthesizeIntializer(expr, function: function)
    }
    
    let entrybb = LLVMAppendBasicBlock(function, "entry")!
    let retbb = LLVMAppendBasicBlock(function, "return")!
    let returnType = expr.returnType.type!
    let type = resolveLLVMType(expr.returnType)
    var res: VarBinding? = nil
    let storageKind = storage(for: returnType)
    let isReferenceInitializer = expr.isInitializer && storage(for: returnType) == .reference
    withFunction {
      LLVMPositionBuilderAtEnd(builder, entrybb)
      if expr.returnType != .void {
        if isReferenceInitializer {
          res = codegenAlloc(type: returnType)
        } else {
          res = createEntryBlockAlloca(function, type: type,
                                       name: "res", storage: storageKind)
        }
        if expr.isInitializer {
          varIRBindings["self"] = res!
        }
      }
      for (idx, arg) in expr.args.enumerated() {
        let param = LLVMGetParam(function, UInt32(idx))!
        LLVMSetValueName(param, arg.name.name)
        let type = arg.type
        let argType = resolveLLVMType(type)
        let storageKind = storage(for: type)
        var ptr = VarBinding(ref: param, storage: storageKind)
        if !arg.isImplicitSelf {
          ptr = createEntryBlockAlloca(function,
                                       type: argType,
                                       name: arg.name.name,
                                       storage: storageKind,
                                       initial: param)
        }
        varIRBindings[arg.name] = ptr
      }
      currentFunction = FunctionState(
        function: expr,
        functionRef: function,
        returnBlock: retbb,
        resultAlloca: res?.ref
      )
      _ = visit(expr.body!)
      let insertBlock = LLVMGetInsertBlock(builder)!
      
      // break to the return block
      if !insertBlock.endsWithTerminator {
        LLVMBuildBr(builder, retbb)
      }
      
      // build the ret in the return block.
      LLVMMoveBasicBlockAfter(retbb, LLVMGetLastBasicBlock(function))
      LLVMPositionBuilderAtEnd(builder, retbb)
      if expr.has(attribute: .noreturn) {
        LLVMBuildUnreachable(builder)
      } else if expr.returnType.type == .void {
        LLVMBuildRetVoid(builder)
      } else {
        let val: LLVMValueRef!
        if isReferenceInitializer {
          val = res?.ref
        } else {
          val = LLVMBuildLoad(builder, res?.ref, "resval")
        }
        LLVMBuildRet(builder, val)
      }
      currentFunction = nil
    }
    LLVMRunFunctionPassManager(passManager, function)
    return function
  }
  
  func codegenGlobalInit() -> Result {
    let name = Mangler.mangle(FuncDecl(name: "globalInit", returnType: DataType.void.ref(), args: []))
    let existing = LLVMGetNamedFunction(module, name)
    if existing != nil { return existing! }
    let fType = LLVMFunctionType(LLVMVoidType(), nil, 0, 0)
    let function = LLVMAddFunction(module, name, fType)
    let currBB = LLVMGetInsertBlock(builder)
    let bb = LLVMAppendBasicBlockInContext(llvmContext, function, "entry")
    LLVMPositionBuilderAtEnd(builder, bb)
    let decl = codegenIntrinsic(named: "trill_init")
    LLVMBuildCall(builder, decl, nil, 0, "")
    LLVMPositionBuilderAtEnd(builder, currBB)
    return function!
  }
  
  func finalizeGlobalInit() {
    let globalInit = codegenGlobalInit()
    let entry = LLVMGetEntryBasicBlock(globalInit)
    LLVMPositionBuilderAtEnd(builder, entry)
    LLVMBuildRetVoid(builder)
  }
  
  func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result {
    guard let decl = expr.decl else { fatalError("no decl on funccall") }
    
    if decl === IntrinsicFunctions.typeOf {
      return codegenTypeOfCall(expr)
    }
    
    var function: LLVMValueRef? = nil
    var args = expr.args
    if
      let type = decl.parentType,
      let field = expr.lhs as? FieldLookupExpr {
      var implicitSelf = field.lhs
      if storage(for: type) == .value {
        implicitSelf = PrefixOperatorExpr(op: .ampersand, rhs: implicitSelf)
      }
      args.insert(Argument(val: implicitSelf, label: nil), at: 0)
    }
    function = codegenFunctionPrototype(decl)
    if function == nil {
      function = visit(expr.lhs)
    }
    
    var argVals = [LLVMValueRef?]()
    for arg in args {
      var val = visit(arg.val)
      if case .array(let field, _)? = arg.val.type {
        let alloca = createEntryBlockAlloca(currentFunction!.functionRef!,
                                            type: LLVMTypeOf(val),
                                            name: "",
                                            storage: .value,
                                            initial: val)
        val = LLVMBuildBitCast(builder,
                               alloca.ref,
                               LLVMPointerType(resolveLLVMType(field), 0),
                               "")
      }
      argVals.append(val)
    }
    let name = expr.type == .void ? "" : "calltmp"
    let call = argVals.withUnsafeMutableBufferPointer { buf in
      LLVMBuildCall(builder, function, buf.baseAddress,
                    UInt32(buf.count), name)
    }
    if decl.has(attribute: .noreturn) {
      LLVMBuildUnreachable(builder)
    }
    return call
  }
  
  func visitFuncArgumentAssignDecl(_ decl: FuncArgumentAssignDecl) -> Result {
    fatalError("handled while generating function")
  }
  
  func visitReturnStmt(_ expr: ReturnStmt) -> Result {
    guard let currentFunction = currentFunction,
          let currentDecl = currentFunction.function else {
      fatalError("return outside function?")
    }
    var store: LLVMValueRef? = nil
    if !(expr.value is VoidExpr) {
      let val = visit(expr.value)
      if !currentDecl.isInitializer {
        store = LLVMBuildStore(builder, val, currentFunction.resultAlloca)
      }
    }
    defer {
      LLVMBuildBr(builder, currentFunction.returnBlock)
    }
    return store
  }
}
