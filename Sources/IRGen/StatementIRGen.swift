//
//  StatementIRGen.swift
//  Trill
//

import Foundation

extension IRGenerator {
  @discardableResult
  func codegenGlobalPrototype(_ decl: VarAssignDecl) -> VarBinding {
    if let binding = globalVarIRBindings[decl.name] { return binding }
    let type = resolveLLVMType(decl.type)
    let global = LLVMAddGlobal(module, type, decl.name.name)!
    LLVMSetAlignment(global, 8)
    let binding = VarBinding(ref: global, storage: .value)
    globalVarIRBindings[decl.name] = binding
    return binding
  }
  
  func storage(for type: DataType) -> Storage {
    if let decl = context.decl(for: context.canonicalType(type)),
           decl.isIndirect {
      return .reference
    }
    return .value
  }
  
  func visitGlobal(_ decl: VarAssignDecl) -> VarBinding {
    let binding = codegenGlobalPrototype(decl)
    if decl.has(attribute: .foreign) && decl.rhs != nil {
      LLVMSetExternallyInitialized(binding.ref, 1)
      return binding
    }
    LLVMGetMetadata(binding.ref, 0)
    let llvmType = resolveLLVMType(decl.type)
    guard let rhs = decl.rhs else {
      LLVMSetInitializer(binding.ref, LLVMConstNull(llvmType))
      return binding
    }
    if rhs is NumExpr || rhs is StringExpr || rhs is CharExpr {
      LLVMSetInitializer(binding.ref, visit(rhs))
    } else {
      LLVMSetInitializer(binding.ref, LLVMConstNull(llvmType))
      let globalInit = codegenGlobalInit()
      let currentBB = LLVMGetInsertBlock(builder)
      let entry = LLVMGetFirstBasicBlock(globalInit)!
      LLVMPositionBuilderAtEnd(builder, entry)
      let value = visit(rhs)!
      LLVMBuildStore(builder, value, binding.ref)
      LLVMPositionBuilderAtEnd(builder, currentBB)
    }
    return binding
  }
  
  func visitGlobalVarAssignExpr(_ decl: VarAssignDecl) -> Result {
    return visitGlobal(decl).ref
  }
  
  func visitVarAssignDecl(_ decl: VarAssignDecl) -> Result {
    let function = currentFunction!.functionRef!
    let type = decl.type
    let irType = resolveLLVMType(type)
    var value: LLVMValueRef
    if let rhs = decl.rhs, let val = visit(rhs) {
      value = val
      if rhs.type! != type {
        value = coerce(value, from: rhs.type!, to: type)!
      }
    } else {
      value = LLVMConstNull(irType)
    }
    var binding = varIRBindings[decl.name]
    if binding == nil {
      binding = createEntryBlockAlloca(function, type: irType,
                                       name: decl.name.name,
                                       storage: storage(for: type),
                                       loc: decl.startLoc())
    }
    varIRBindings[decl.name] = binding
    LLVMBuildStore(builder, value, binding!.ref)
    return binding!.ref
  }
  
  func visitIfStmt(_ stmt: IfStmt) -> Result {
    let function = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder))
    guard function != nil else {
      fatalError("if outside function?")
    }
    let conditions = stmt.blocks.map { $0.0 }
    let bodies = stmt.blocks.map { $0.1 }
    var bodyBlocks = [LLVMValueRef]()
    let currentBlock = LLVMGetInsertBlock(builder)
    let elsebb = LLVMAppendBasicBlockInContext(llvmContext, function, "else")
    let mergebb = LLVMAppendBasicBlockInContext(llvmContext, function, "merge")
    for body in bodies {
      let bb = LLVMAppendBasicBlockInContext(llvmContext, function, "then")
      bodyBlocks.append(bb!)
      LLVMPositionBuilderAtEnd(builder, bb)
      withScope { visitCompoundStmt(body) }
      let currBlock = LLVMGetInsertBlock(builder)!
      if !currBlock.endsWithTerminator {
        LLVMBuildBr(builder, mergebb)
      }
    }
    LLVMPositionBuilderAtEnd(builder, currentBlock)
    for (idx, condition) in conditions.enumerated() {
      let cond = visit(condition)
      let next = LLVMAppendBasicBlockInContext(llvmContext, function, "next")
      LLVMBuildCondBr(builder, cond, bodyBlocks[idx], next)
      LLVMPositionBuilderAtEnd(builder, next)
    }
    if let elseBody = stmt.elseBody {
      LLVMBuildBr(builder, elsebb)
      LLVMPositionBuilderAtEnd(builder, elsebb)
      withScope {
        visitCompoundStmt(elseBody)
      }
      let lastInst = LLVMGetLastInstruction(elsebb)
      if LLVMIsABranchInst(lastInst) == nil {
        LLVMBuildBr(builder, mergebb)
      }
    } else {
      LLVMBuildBr(builder, mergebb)
      LLVMDeleteBasicBlock(elsebb)
    }
    LLVMPositionBuilderAtEnd(builder, mergebb)
    return nil
  }
  
  func visitWhileStmt(_ stmt: WhileStmt) -> Result {
    guard let function = currentFunction?.functionRef else {
      fatalError("while loop outside function?")
    }
    let condbb = LLVMAppendBasicBlockInContext(llvmContext, function, "cond")
    let bodybb = LLVMAppendBasicBlockInContext(llvmContext, function, "body")
    let endbb = LLVMAppendBasicBlockInContext(llvmContext, function, "end")
    LLVMBuildBr(builder, condbb)
    LLVMPositionBuilderAtEnd(builder, condbb)
    let cond = visit(stmt.condition)
    LLVMBuildCondBr(builder, cond, bodybb, endbb)
    LLVMPositionBuilderAtEnd(builder, bodybb)
    withScope {
      currentBreakTarget = endbb!
      currentContinueTarget = condbb!
      visit(stmt.body)
    }
    let insertBlock = LLVMGetInsertBlock(builder)!
    if !insertBlock.endsWithTerminator {
      LLVMBuildBr(builder, condbb)
    }
    LLVMPositionBuilderAtEnd(builder, endbb)
    return nil
  }
  
  func visitForStmt(_ stmt: ForStmt) -> Result {
    guard let function = currentFunction?.functionRef else {
      fatalError("for loop outside function")
    }
    withScope {
      if let initializer = stmt.initializer {
        visit(initializer)
      }
      let condbb = LLVMAppendBasicBlockInContext(llvmContext, function, "cond")
      let bodybb = LLVMAppendBasicBlockInContext(llvmContext, function, "body")
      let incrbb = LLVMAppendBasicBlockInContext(llvmContext, function, "incr")
      let endbb = LLVMAppendBasicBlockInContext(llvmContext, function, "end")
      LLVMBuildBr(builder, condbb)
      LLVMPositionBuilderAtEnd(builder, condbb)
      currentContinueTarget = incrbb!
      currentBreakTarget = endbb!
      let cond = visit(stmt.condition ?? BoolExpr(value: true))
      LLVMBuildCondBr(builder, cond, bodybb, endbb)
      LLVMPositionBuilderAtEnd(builder, bodybb)
      currentBreakTarget = endbb!
      visit(stmt.body)
      let insertBlock = LLVMGetInsertBlock(builder)!
      if !insertBlock.endsWithTerminator {
        LLVMBuildBr(builder, incrbb)
      }
      LLVMPositionBuilderAtEnd(builder, incrbb)
      if let incrementer = stmt.incrementer {
        visit(incrementer)
      }
      LLVMBuildBr(builder, condbb)
      LLVMPositionBuilderAtEnd(builder, endbb)
    }
    return nil
  }
  
  func visitPoundDiagnosticStmt(_ stmt: PoundDiagnosticStmt) -> LLVMValueRef? {
    return nil
  }
  
  func visitSwitchStmt(_ stmt: SwitchStmt) -> Result {
    guard let function = currentFunction?.functionRef else {
      fatalError("switch outside function")
    }
    let currentBlock = LLVMGetInsertBlock(builder)
    let endbb = LLVMAppendBasicBlockInContext(llvmContext, function, "switch-end")
    let defaultBlock: LLVMBasicBlockRef
    if let defaultBody = stmt.defaultBody {
      defaultBlock = LLVMAppendBasicBlockInContext(llvmContext, function, "default")
      LLVMPositionBuilderAtEnd(builder, defaultBlock)
      visit(defaultBody)
      LLVMPositionBuilderAtEnd(builder, defaultBlock)
      if !defaultBlock.endsWithTerminator {
        LLVMBuildBr(builder, endbb)
      }
      LLVMPositionBuilderAtEnd(builder, currentBlock)
    } else {
      defaultBlock = endbb!
    }
    let switchRef = LLVMBuildSwitch(builder, visit(stmt.value), defaultBlock, UInt32(stmt.cases.count))
    for (i, c) in stmt.cases.enumerated() {
      let block = LLVMAppendBasicBlockInContext(llvmContext, function, "case-\(i)")
      LLVMPositionBuilderAtEnd(builder, block)
      visit(c.body)
      LLVMBuildBr(builder, endbb)
      LLVMAddCase(switchRef, visit(c.constant), block)
    }
    LLVMPositionBuilderAtEnd(builder, endbb)
    return nil
  }
  
  func visitCaseStmt(_ stmt: CaseStmt) -> Result {
    // never called directly
    return nil
  }
}
