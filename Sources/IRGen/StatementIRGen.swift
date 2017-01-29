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
    var global = builder.addGlobal(decl.name.name, type: type)
    global.alignment = 8
    let binding = VarBinding(ref: global,
                             storage: .value,
                             read: {
                              return self.builder.buildLoad(global)
    },
                             write: { val in self.builder.buildStore(val, to: global) })
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
    guard var global = binding.ref as? Global else {
      fatalError("global binding is not a Global?")
    }
    if decl.has(attribute: .foreign) && decl.rhs != nil {
      global.isExternallyInitialized = true
      return binding
    }
    let irType = resolveLLVMType(decl.type)
    guard let rhs = decl.rhs else {
      global.initializer = irType.null()
      global.isGlobalConstant = !decl.mutable
      return binding
    }
    if context.isGlobalConstant(rhs) {
      global.initializer = visit(rhs)!
      global.isGlobalConstant = !decl.mutable
      return binding
    } else {
      global.initializer = irType.null()
      let currentBlock = builder.insertBlock
      
      let initFn = builder.addFunction(Mangler.mangle(global: decl,
                                                      kind: .initializer),
                                       type: FunctionType(argTypes: [],
                                                          returnType: VoidType()))
      builder.positionAtEnd(of: initFn.appendBasicBlock(named: "entry"))
      builder.buildStore(visit(rhs)!, to: binding.ref)
      builder.buildRetVoid()
      
      let lazyInit = builder.addFunction(Mangler.mangle(global: decl,
                                                        kind: .accessor),
                                         type: FunctionType(argTypes: [],
                                                            returnType: irType))
      builder.positionAtEnd(of: lazyInit.appendBasicBlock(named: "entry", in: llvmContext))
      codegenOnceCall(function: initFn)
      builder.buildRet(builder.buildLoad(binding.ref, name: "global-res"))
      
      if let block = currentBlock {
        builder.positionAtEnd(of: block)
      }
      return VarBinding(ref: binding.ref, storage: binding.storage,
                        read: { return self.builder.buildCall(lazyInit, args: []) },
                        write: { self.builder.buildStore($0, to: binding.ref) })
    }
  }
  
  func visitGlobalVarAssignExpr(_ decl: VarAssignDecl) -> Result {
    return nil
  }
  
  func visitVarAssignDecl(_ decl: VarAssignDecl) -> Result {
    let function = currentFunction!.functionRef!
    let type = decl.type
    let irType = resolveLLVMType(type)
    var value: IRValue
    if let rhs = decl.rhs, let val = visit(rhs) {
      value = val
      if case .any = type {
        value = codegenPromoteToAny(value: value, type: rhs.type!)
      } else if rhs.type! != type {
        value = coerce(value, from: rhs.type!, to: type)!
      }
    } else {
      value = irType.null()
    }
    let binding = varIRBindings[decl.name] ??
        createEntryBlockAlloca(function, type: irType,
                               name: decl.name.name,
                               storage: storage(for: type))
    varIRBindings[decl.name] = binding
    builder.buildStore(value, to: binding.ref)
    return binding.ref
  }
  
  func visitIfStmt(_ stmt: IfStmt) -> Result {
    guard let function = currentFunction?.functionRef else {
      fatalError("if outside function?")
    }
    let conditions = stmt.blocks.map { $0.0 }
    let bodies = stmt.blocks.map { $0.1 }
    var bodyBlocks = [BasicBlock]()
    let currentBlock = builder.insertBlock!
    let elsebb = function.appendBasicBlock(named: "else", in: llvmContext)
    let mergebb = function.appendBasicBlock(named: "merge", in: llvmContext)
    for body in bodies {
      let bb = function.appendBasicBlock(named: "then", in: llvmContext)
      bodyBlocks.append(bb)
      builder.positionAtEnd(of: bb)
      withScope { visitCompoundStmt(body) }
      let currBlock = builder.insertBlock!
      if !currBlock.endsWithTerminator {
        builder.buildBr(mergebb)
      }
    }
    builder.positionAtEnd(of: currentBlock)
    for (idx, condition) in conditions.enumerated() {
      let cond = visit(condition)!
      let next = function.appendBasicBlock(named: "next", in: llvmContext)
      builder.buildCondBr(condition: cond,
                          then: bodyBlocks[idx],
                          else: next)
      builder.positionAtEnd(of: next)
    }
    if let elseBody = stmt.elseBody {
      builder.buildBr(elsebb)
      builder.positionAtEnd(of: elsebb)
      withScope {
        visitCompoundStmt(elseBody)
      }
      
      if let lastInst = elsebb.lastInstruction {
        if !lastInst.isATerminatorInst {
          builder.buildBr(mergebb)
        }
      } else {
        builder.buildBr(mergebb)
      }
    } else {
      builder.buildBr(mergebb)
      elsebb.delete()
    }
    builder.positionAtEnd(of: mergebb)
    return nil
  }
  
  func visitWhileStmt(_ stmt: WhileStmt) -> Result {
    guard let function = currentFunction?.functionRef else {
      fatalError("while loop outside function?")
    }
    let condbb = function.appendBasicBlock(named: "cond", in: llvmContext)
    let bodybb = function.appendBasicBlock(named: "body", in: llvmContext)
    let endbb = function.appendBasicBlock(named: "end", in: llvmContext)
    builder.buildBr(condbb)
    builder.positionAtEnd(of: condbb)
    let cond = visit(stmt.condition)!
    builder.buildCondBr(condition: cond, then: bodybb, else: endbb)
    builder.positionAtEnd(of: bodybb)
    withScope {
      currentBreakTarget = endbb
      currentContinueTarget = condbb
      visit(stmt.body)
    }
    let insertBlock = builder.insertBlock!
    if !insertBlock.endsWithTerminator {
      builder.buildBr(condbb)
    }
    builder.positionAtEnd(of: endbb)
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
      let condbb = function.appendBasicBlock(named: "cond", in: llvmContext)
      let bodybb = function.appendBasicBlock(named: "body", in: llvmContext)
      let incrbb = function.appendBasicBlock(named: "incr", in: llvmContext)
      let endbb = function.appendBasicBlock(named: "end", in: llvmContext)
      builder.buildBr(condbb)
      builder.positionAtEnd(of: condbb)
      currentContinueTarget = incrbb
      currentBreakTarget = endbb
      let cond = visit(stmt.condition ?? BoolExpr(value: true))!
      builder.buildCondBr(condition: cond, then: bodybb, else: endbb)
      builder.positionAtEnd(of: bodybb)
      currentBreakTarget = endbb
      visit(stmt.body)
      let insertBlock = builder.insertBlock!
      if !insertBlock.endsWithTerminator {
        builder.buildBr(incrbb)
      }
      builder.positionAtEnd(of: incrbb)
      if let incrementer = stmt.incrementer {
        visit(incrementer)
      }
      builder.buildBr(condbb)
      builder.positionAtEnd(of: endbb)
    }
    return nil
  }

  func visitDeclStmt(_ stmt: DeclStmt) -> Result {
    return visit(stmt.decl)
  }

  func visitExprStmt(_ stmt: ExprStmt) -> Result {
    return visit(stmt.expr)
  }
  
  func visitPoundDiagnosticStmt(_ stmt: PoundDiagnosticStmt) -> Result {
    return nil
  }
  
  func visitSwitchStmt(_ stmt: SwitchStmt) -> Result {
    guard let function = currentFunction?.functionRef else {
      fatalError("switch outside function")
    }
    let currentBlock = builder.insertBlock!
    let endbb = function.appendBasicBlock(named: "switch-end", in: llvmContext)
    let defaultBlock: BasicBlock
    if let defaultBody = stmt.defaultBody {
      defaultBlock = function.appendBasicBlock(named: "default", in: llvmContext)
      builder.positionAtEnd(of: defaultBlock)
      visit(defaultBody)
      builder.positionAtEnd(of: defaultBlock)
      if !defaultBlock.endsWithTerminator {
        builder.buildBr(endbb)
      }
      builder.positionAtEnd(of: currentBlock)
    } else {
      defaultBlock = endbb
    }
    var constants = [IRValue]()
    for c in stmt.cases {
      constants.append(visit(c.constant)!)
    }
    let switchRef = builder.buildSwitch(visit(stmt.value)!,
                                        else: defaultBlock,
                                        caseCount: stmt.cases.count)
    for (i, c) in stmt.cases.enumerated() {
      let block = function.appendBasicBlock(named: "case-\(i)", in: llvmContext)
      builder.positionAtEnd(of: block)
      visit(c.body)
      builder.buildBr(endbb)
      switchRef.addCase(constants[i], block)
    }
    builder.positionAtEnd(of: endbb)
    return nil
  }
  
  func visitCaseStmt(_ stmt: CaseStmt) -> Result {
    // never called directly
    return nil
  }
}
