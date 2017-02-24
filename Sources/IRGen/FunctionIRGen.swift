//
//  FunctionIRGen.swift
//  Trill
//

import Foundation

extension IRGenerator {
  
  func createEntryBlockAlloca(_ function: Function,
                              type: IRType,
                              name: String,
                              storage: Storage,
                              initial: IRValue? = nil) -> VarBinding {
    let currentBlock = builder.insertBlock
    let entryBlock = function.entryBlock!
    if let firstInst = entryBlock.firstInstruction {
      builder.position(firstInst, block: entryBlock)
    }
    let alloca = builder.buildAlloca(type: type, name: name)
    if let block = currentBlock {
      builder.positionAtEnd(of: block)
    }
    if let initial = initial {
      builder.buildStore(initial, to: alloca)
    }
    return VarBinding(ref: alloca,
                      storage: storage,
                      read: { self.builder.buildLoad(alloca) },
                      write: { self.builder.buildStore($0, to: alloca) })
  }
  
  @discardableResult
  func codegenFunctionPrototype(_ expr: FuncDecl) -> Function {
    let mangled = Mangler.mangle(expr)
    if let existing = module.function(named: mangled) {
      return existing
    }
    var argTys = [IRType]()
    for arg in expr.args {
      var type = resolveLLVMType(arg.type)
      if arg.isImplicitSelf && storage(for: arg.type) != .reference {
        type = PointerType(pointee: type)
      }
      argTys.append(type)
    }
    let type = resolveLLVMType(expr.returnType)
    let fType = FunctionType(argTypes: argTys, returnType: type, isVarArg: expr.hasVarArgs)
    return builder.addFunction(mangled, type: fType)
  }
  
  func visitBreakStmt(_ expr: BreakStmt) -> Result {
    guard let target = currentBreakTarget else {
      fatalError("break outside loop")
    }
    return builder.buildBr(target)
  }
  
  func visitContinueStmt(_ stmt: ContinueStmt) -> Result {
    guard let target = currentContinueTarget else {
      fatalError("continue outside loop")
    }
    return builder.buildBr(target)
  }

  func synthesizeIntializer(_ decl: FuncDecl, function: Function) -> IRValue {
    guard decl is InitializerDecl,
        let body = decl.body,
        body.stmts.isEmpty,
      let type = decl.returnType.type,
        let typeDecl = context.decl(for: type) else {
      fatalError("must synthesize an empty initializer")
    }
    let entryBB = function.appendBasicBlock(named: "entry")
    builder.positionAtEnd(of: entryBB)
    var retLLVMType = resolveLLVMType(type)
    if typeDecl.isIndirect {
      retLLVMType = (retLLVMType as! PointerType).pointee
    }
    var initial = retLLVMType.null()
    for (idx, arg) in decl.args.enumerated() {
      var param = function.parameter(at: idx)!
      param.name = arg.name.name
      initial = builder.buildInsertValue(aggregate: initial,
                                         element: param,
                                         index: idx,
                                         name: "init-insert")
    }
    if typeDecl.isIndirect {
      let result = codegenAlloc(type: type).ref
      builder.buildStore(initial, to: result)
      builder.buildRet(result)
    } else {
      builder.buildRet(initial)
    }
    return function
  }
  
  func visitOperatorDecl(_ decl: OperatorDecl) -> Result {
    return visitFuncDecl(decl)
  }
  
  func visitFuncDecl(_ decl: FuncDecl) -> Result {
    let function = codegenFunctionPrototype(decl)
    
    if decl === context.mainFunction {
      mainFunction = function
    }
    
    if decl.has(attribute: .foreign) { return function }
    
    if decl is InitializerDecl, let body = decl.body, body.stmts.isEmpty {
      return synthesizeIntializer(decl, function: function)
    }
    
    let entrybb = function.appendBasicBlock(named: "entry", in: llvmContext)
    let retbb = function.appendBasicBlock(named: "return", in: llvmContext)
    let returnType = decl.returnType.type!
    let type = resolveLLVMType(decl.returnType)
    var res: VarBinding? = nil
    let storageKind = storage(for: returnType)
    let isReferenceInitializer = decl is InitializerDecl && storage(for: returnType) == .reference
    withFunction {
      builder.positionAtEnd(of: entrybb)
      if decl.returnType != .void {
        if isReferenceInitializer {
          res = codegenAlloc(type: returnType)
        } else {
          res = createEntryBlockAlloca(function, type: type,
                                       name: "res", storage: storageKind)
        }
        if decl is InitializerDecl {
          varIRBindings["self"] = res!
        }
      }
      for (idx, arg) in decl.args.enumerated() {
        var param = function.parameter(at: idx)!
        param.name = arg.name.name
        let type = arg.type
        let argType = resolveLLVMType(type)
        let storageKind = storage(for: type)
        let read: () -> IRValue
        if arg.isImplicitSelf && storageKind == .reference {
          read = { param }
        } else {
          read = { self.builder.buildLoad(param) }
        }
        var ptr = VarBinding(ref: param,
                             storage: storageKind,
                             read: read,
                             write: { self.builder.buildStore($0, to: param) })
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
        function: decl,
        functionRef: function,
        returnBlock: retbb,
        resultAlloca: res?.ref
      )
      _ = visit(decl.body!)
      let insertBlock = builder.insertBlock!
      
      // break to the return block
      if !insertBlock.endsWithTerminator {
        builder.buildBr(retbb)
      }
      
      // build the ret in the return block.
      retbb.moveAfter(function.lastBlock!)
      builder.positionAtEnd(of: retbb)
      if decl.has(attribute: .noreturn) {
        builder.buildUnreachable()
      } else if decl.returnType.type == .void {
        builder.buildRetVoid()
      } else {
        let val: IRValue
        if isReferenceInitializer {
          val = res!.ref
        } else {
          val = builder.buildLoad(res!.ref, name: "resval")
        }
        builder.buildRet(val)
      }
      currentFunction = nil
    }
    passManager.run(on: function)
    return function
  }
  
  func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result {
    guard let decl = expr.decl else { fatalError("no decl on funccall") }
    
    if decl === IntrinsicFunctions.typeOf {
      return codegenTypeOfCall(expr)
    }
    
    var function: IRValue? = nil
    var args = expr.args
    
    let findImplicitSelf: (FuncCallExpr) -> Expr? = { expr in
      guard let decl = expr.decl as? MethodDecl else { return nil }
      if decl.has(attribute: .static) { return nil }
      switch decl {
      case _ as SubscriptDecl:
        return expr.lhs
      default:
        if let property = expr.lhs as? PropertyRefExpr {
          return property.lhs
        }
        return nil
      }
    }

    if
      let method = decl as? MethodDecl,
      var implicitSelf = findImplicitSelf(expr) {
      if storage(for: method.parentType) == .value {
        implicitSelf = PrefixOperatorExpr(op: .ampersand, rhs: implicitSelf)
        implicitSelf.type = .pointer(type: method.parentType)
      }
      args.insert(Argument(val: implicitSelf, label: nil), at: 0)
    }

    if decl.isPlaceholder {
      function = visit(expr.lhs)
    } else {
      function = codegenFunctionPrototype(decl)
    }

    if function == nil {
      function = visit(expr.lhs)
    }
    
    var argVals = [IRValue]()
    for (idx, arg) in args.enumerated() {
      var val = visit(arg.val)!
      var type = arg.val.type!
      if case .array(let field, _) = type {
        let alloca = createEntryBlockAlloca(currentFunction!.functionRef!,
                                            type: val.type,
                                            name: "",
                                            storage: .value,
                                            initial: val)
        type = .pointer(type: field)
        val = builder.buildBitCast(alloca.ref, type: PointerType(pointee: resolveLLVMType(field)))
      }
      if let declArg = decl.args[safe: idx], declArg.type == .any {
        val = codegenPromoteToAny(value: val, type: type)
      }
      argVals.append(val)
    }
    let name = expr.type == .void ? "" : "calltmp"
    let call = builder.buildCall(function!, args: argVals, name: name)
    if decl.has(attribute: .noreturn) {
      builder.buildUnreachable()
    }
    return call
  }
  
  func visitParamDecl(_ decl: ParamDecl) -> Result {
    fatalError("handled while generating function")
  }
  
  func visitReturnStmt(_ expr: ReturnStmt) -> Result {
    guard let currentFunction = currentFunction,
          let currentDecl = currentFunction.function else {
      fatalError("return outside function?")
    }
    var store: IRValue? = nil
    if !(expr.value is VoidExpr) {
      var val = visit(expr.value)!
      if let type = expr.value.type,
         case .any = context.canonicalType(currentDecl.returnType.type!) {
        val = codegenPromoteToAny(value: val, type: type)
      }
      if !(currentDecl is InitializerDecl) {
        store = builder.buildStore(val, to: currentFunction.resultAlloca!)
      }
    }
    defer {
      builder.buildBr(currentFunction.returnBlock!)
    }
    return store
  }
}

extension Array {
  subscript(safe index: Int) -> Element? {
    guard index < count else { return nil }
    return self[index]
  }
}
