//
//  ValueIRGen.swift
//  Trill
//

import Foundation

extension IRGenerator {
  func codegenGlobalStringPtr(_ string: String) -> Result {
    if let global = globalStringMap[string] { return global }
    let length = UInt32(string.utf8.count)
    let globalArray = LLVMAddGlobal(module,
                                    LLVMArrayType(LLVMInt8Type(), length + 1),
                                    "str")!
    LLVMSetAlignment(globalArray, 1)
    var utf8String = string.utf8CString
    utf8String.withUnsafeMutableBufferPointer { buf in
      let str = LLVMConstStringInContext(llvmContext, buf.baseAddress, length, 0)
      LLVMSetInitializer(globalArray, str)
    }
    globalStringMap[string] = globalArray
    return globalArray
  }
  
  func codegenTupleType(_ type: DataType) -> LLVMTypeRef {
    guard case .tuple(let fields) = type else { fatalError("must be tuple type") }
    let name = Mangler.mangle(context.canonicalType(type))
    if let existing = LLVMGetTypeByName(module, name) { return existing }
    var types: [LLVMValueRef?] = fields.map(resolveLLVMType)
    let named = LLVMStructCreateNamed(llvmContext, name)!
    _ = types.withUnsafeMutableBufferPointer { buf in
      LLVMStructSetBody(named, buf.baseAddress, UInt32(buf.count), 1)
    }
    return named
  }
  
  func visitNumExpr(_ expr: NumExpr) -> Result {
    return LLVMConstInt(resolveLLVMType(expr.type!), unsafeBitCast(expr.value, to: UInt64.self), 1)
  }
  
  func visitCharExpr(_ expr: CharExpr) -> Result {
    return LLVMConstInt(typeIRBindings[.int8]!, UInt64(expr.value), 1)
  }
  
  func visitFloatExpr(_ expr: FloatExpr) -> Result {
    return LLVMConstReal(typeIRBindings[.double]!, expr.value)
  }
  
  func visitBoolExpr(_ expr: BoolExpr) -> Result {
    return LLVMConstInt(typeIRBindings[.bool]!, expr.value ? 1 : 0, 0)
  }
  
  func visitTupleExpr(_ expr: TupleExpr) -> LLVMValueRef? {
    let type = resolveLLVMType(expr.type!)
    var initial = LLVMConstNull(type)!
    for (idx, field) in expr.values.enumerated() {
      initial = LLVMBuildInsertValue(builder, initial, visit(field), UInt32(idx), "tuple-insert")
    }
    return initial
  }
  
  func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) -> LLVMValueRef? {
    let ptr = resolvePtr(expr.lhs)
    let gep = LLVMBuildStructGEP(builder, ptr, UInt32(expr.field), "tuple-gep")
    return LLVMBuildLoad(builder, gep, "tuple-load")
  }
  
  func visitVarExpr(_ expr: VarExpr) -> Result {
    let (shouldLoad, _binding) = resolveVarBinding(expr)
    guard let binding = _binding else { return nil }
    if !shouldLoad { return binding.ref }
    return LLVMBuildLoad(builder, binding.ref, expr.name.name)
  }
  
  func visitSizeofExpr(_ expr: SizeofExpr) -> Result {
    return LLVMBuildTruncOrBitCast(builder, LLVMSizeOf(resolveLLVMType(expr.valueType!)), LLVMInt64Type(), "")
  }
  
  func visitVoidExpr(_ expr: VoidExpr) -> Result {
    return nil
  }
  
  func visitNilExpr(_ expr: NilExpr) -> Result {
    let type = resolveLLVMType(expr.type!)
    return LLVMConstNull(type)
  }
  
  func coerce(_ value: LLVMValueRef, from fromType: DataType, to type: DataType) -> Result {
    let llvmType = resolveLLVMType(type)
    switch (context.canonicalType(fromType), context.canonicalType(type)) {
    case (.int(let lhsWidth), .int(let rhsWidth)):
      if lhsWidth == rhsWidth { return value }
      if lhsWidth < rhsWidth {
        return LLVMBuildSExt(builder, value, llvmType, "sext-coerce")
      } else {
        return LLVMBuildTrunc(builder, value, llvmType, "trunc-coerce")
      }
    case (.int, .floating):
      return LLVMBuildSIToFP(builder, value, llvmType, "inttofp-coerce")
    case (.floating, .int):
      return LLVMBuildFPToSI(builder, value, llvmType, "fptoint-coerce")
    case (.pointer, .int):
      return LLVMBuildPtrToInt(builder, value, llvmType, "ptrtoint-coerce")
    case (.int, .pointer):
      return LLVMBuildIntToPtr(builder, value, llvmType, "inttoptr-coerce")
    case (.pointer, .pointer):
      return LLVMBuildBitCast(builder, value, llvmType, "bitcast-coerce")
    default:
      return LLVMBuildBitCast(builder, value, llvmType, "bitcast-coerce")
    }
  }
  
  func visitStringExpr(_ expr: StringExpr) -> Result {
    let globalPtr = codegenGlobalStringPtr(expr.value)
    let zero = LLVMConstNull(typeIRBindings[.int64]!)
    var indices = [zero, zero]
    return indices.withUnsafeMutableBufferPointer { buf in
      return LLVMConstGEP(globalPtr, buf.baseAddress, UInt32(buf.count))
    }
  }
  
  func visitSubscriptExpr(_ expr: SubscriptExpr) -> Result {
    let ptr = resolvePtr(expr)
    return LLVMBuildLoad(builder, ptr, "subscript-load")
  }
  
  // 100 + x
  
  // %0 = i64 100
  // %x = load i64* %x-alloca
  // %addtmp = add i64 %0, i64 %x
  
  func codegen(_ op: BuiltinOperator, lhs: LLVMValueRef, rhs: LLVMValueRef, type: DataType) -> Result {
    switch op {
    case .plus:
      if case .floating = type {
        return LLVMBuildFAdd(builder, lhs, rhs, "addtmp")
      } else {
        return LLVMBuildAdd(builder, lhs, rhs, "addtmp")
      }
    case .minus:
      if case .floating = type {
        return LLVMBuildFSub(builder, lhs, rhs, "subtmp")
      } else {
        return LLVMBuildSub(builder, lhs, rhs, "subtmp")
      }
    case .star:
      if case .floating = type {
        return LLVMBuildFMul(builder, lhs, rhs, "multmp")
      } else {
        return LLVMBuildMul(builder, lhs, rhs, "multmp")
      }
    case .divide:
      if case .floating = type {
        return LLVMBuildFDiv(builder, lhs, rhs, "divtmp")
      } else {
        return LLVMBuildSDiv(builder, lhs, rhs, "divtmp")
      }
    case .mod:
      return LLVMBuildSRem(builder, lhs, rhs, "modtmp")
    case .equalTo:
      if case .floating = type {
        return LLVMBuildFCmp(builder, LLVMRealOEQ, lhs, rhs, "eqtmp")
      } else {
        return LLVMBuildICmp(builder, LLVMIntEQ, lhs, rhs, "eqtmp")
      }
    case .notEqualTo:
      if case .floating = type {
        return LLVMBuildFCmp(builder, LLVMRealONE, lhs, rhs, "eqtmp")
      } else {
        return LLVMBuildICmp(builder, LLVMIntNE, lhs, rhs, "eqtmp")
      }
    case .lessThan:
      if case .floating = type {
        return LLVMBuildFCmp(builder, LLVMRealOLT, lhs, rhs, "eqtmp")
      } else {
        return LLVMBuildICmp(builder, LLVMIntSLT, lhs, rhs, "eqtmp")
      }
    case .lessThanOrEqual:
      if case .floating = type {
        return LLVMBuildFCmp(builder, LLVMRealOLE, lhs, rhs, "eqtmp")
      } else {
        return LLVMBuildICmp(builder, LLVMIntSLE, lhs, rhs, "eqtmp")
      }
    case .greaterThan:
      if case .floating = type {
        return LLVMBuildFCmp(builder, LLVMRealOGT, lhs, rhs, "eqtmp")
      } else {
        return LLVMBuildICmp(builder, LLVMIntSGT, lhs, rhs, "eqtmp")
      }
    case .greaterThanOrEqual:
      if case .floating = type {
        return LLVMBuildFCmp(builder, LLVMRealOGE, lhs, rhs, "eqtmp")
      } else {
        return LLVMBuildICmp(builder, LLVMIntSGE, lhs, rhs, "eqtmp")
      }
    case .xor:
      return LLVMBuildXor(builder, lhs, rhs, "xortmp")
    case .ampersand:
      return LLVMBuildAnd(builder, lhs, rhs, "andtmp")
    case .bitwiseOr:
      return LLVMBuildOr(builder, lhs, rhs, "ortmp")
    case .leftShift:
      return LLVMBuildShl(builder, lhs, rhs, "shltmp")
    case .rightShift:
      return LLVMBuildLShr(builder, lhs, rhs, "lshrtmp")
    default:
      fatalError("unknown operator \(op)")
    }
  }
  
  func codegenShortCircuit(_ expr: InfixOperatorExpr) -> Result {
    let block = LLVMGetInsertBlock(builder)
    guard let function = LLVMGetBasicBlockParent(block) else {
      fatalError("outside function")
    }
    let secondCaseBB = LLVMAppendBasicBlockInContext(llvmContext, function, "secondcase")
    let endBB = LLVMAppendBasicBlockInContext(llvmContext, function, "end")
    let lhs = visit(expr.lhs)
    if expr.op == .and {
      LLVMBuildCondBr(builder, lhs, secondCaseBB, endBB)
    } else {
      LLVMBuildCondBr(builder, lhs, endBB, secondCaseBB)
    }
    LLVMPositionBuilderAtEnd(builder, secondCaseBB)
    let rhs = visit(expr.rhs)
    LLVMBuildBr(builder, endBB)
    LLVMPositionBuilderAtEnd(builder, endBB)
    let phi = LLVMBuildPhi(builder, LLVMInt1Type(), "op-phi")
    var values = [lhs, rhs]
    var blocks = [block, secondCaseBB]
    values.withUnsafeMutableBufferPointer { valueBuf in
      _ = blocks.withUnsafeMutableBufferPointer { blockBuf in
        LLVMAddIncoming(phi, valueBuf.baseAddress, blockBuf.baseAddress, UInt32(valueBuf.count))
      }
    }
    return phi
  }
  
  func visitParenExpr(_ expr: ParenExpr) -> Result {
    return visit(expr.value)
  }
  
  func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) -> Result {
    if [.and, .or].contains(expr.op) {
      return codegenShortCircuit(expr)
    }
    
    if case .as = expr.op {
      let lhs: LLVMValueRef
      
      // To support casting between indirect types and void pointers,
      // don't actually load the lhs here. Just get a pointer to it.
      if let decl = context.decl(for: expr.lhs.type!), decl.isIndirect {
        lhs = resolvePtr(expr.lhs)!
      } else {
        lhs = visit(expr.lhs)!
      }
      return coerce(lhs, from: expr.lhs.type!, to: expr.type!)
    }
    
    let rhs = visit(expr.rhs)!
    
    if case .assign = expr.op {
      let ptr = resolvePtr(expr.lhs)
      return LLVMBuildStore(builder, rhs, ptr)
    } else if let associated = expr.op.associatedOp {
      let ptr = resolvePtr(expr.lhs)
      let lhsVal = LLVMBuildLoad(builder, ptr, "cmpassignload")!
      let performed = codegen(associated, lhs: lhsVal, rhs: rhs, type: expr.lhs.type!)!
      return LLVMBuildStore(builder, performed, ptr)
    }
    
    let lhs = visit(expr.lhs)!
    return codegen(expr.op, lhs: lhs, rhs: rhs, type: expr.lhs.type!)
  }
  
  func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) -> Result {
    return visitStringExpr(expr) // It should have a value by now.
  }
  
  func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) -> Result {
    switch expr.op {
    case .minus:
      let val = visit(expr.rhs)
      if case .floating = expr.rhs.type! {
        return LLVMBuildFNeg(builder, val, "neg")
      } else {
        return LLVMBuildNeg(builder, val, "neg")
      }
    case .bitwiseNot:
      let val = visit(expr.rhs)
      return LLVMBuildNot(builder, val, "bit-not")
    case .not:
      let val = visit(expr.rhs)
      return LLVMBuildNot(builder, val, "not")
    case .star:
      let val = visit(expr.rhs)
      return LLVMBuildLoad(builder, val, "deref")
    case .ampersand:
      return resolvePtr(expr.rhs)
    default:
      fatalError("unknown operator \(expr.op)")
    }
  }
  
  func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    guard let function = currentFunction?.functionRef else { fatalError("no function") }
    guard let type = expr.type else { fatalError("no ternary type") }
    let llvmType = resolveLLVMType(type)
    let cond = visit(expr.condition)
    let truebb = LLVMAppendBasicBlockInContext(llvmContext, function, "true-case")
    let falsebb = LLVMAppendBasicBlockInContext(llvmContext, function, "false-case")
    let endbb = LLVMAppendBasicBlockInContext(llvmContext, function, "ternary-end")
    LLVMBuildCondBr(builder, cond, truebb, falsebb)
    LLVMPositionBuilderAtEnd(builder, truebb)
    let trueVal = visit(expr.trueCase)
    LLVMBuildBr(builder, endbb)
    LLVMPositionBuilderAtEnd(builder, falsebb)
    let falseVal = visit(expr.falseCase)
    LLVMBuildBr(builder, endbb)
    LLVMPositionBuilderAtEnd(builder, endbb)
    let phi = LLVMBuildPhi(builder, llvmType, "ternary-phi")
    var values = [trueVal, falseVal]
    var blocks = [truebb, falsebb]
    values.withUnsafeMutableBufferPointer { valueBuf in
      _ = blocks.withUnsafeMutableBufferPointer { blockBuf in
        LLVMAddIncoming(phi, valueBuf.baseAddress, blockBuf.baseAddress, UInt32(valueBuf.count))
      }
    }
    return phi
  }
}
