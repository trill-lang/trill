//
//  ValueIRGen.swift
//  Trill
//

import Foundation

extension IRGenerator {
  func codegenGlobalStringPtr(_ string: String) -> IRValue {
    if let global = globalStringMap[string] { return global }
    let length = string.utf8.count
    var globalArray = builder.addGlobal("str", type:
      ArrayType(elementType: IntType.int8, count: length + 1))
    globalArray.alignment = 1
    globalArray.initializer = string
    globalStringMap[string] = globalArray
    return globalArray
  }
  
  func codegenTupleType(_ type: DataType) -> IRType {
    guard case .tuple(let fields) = type else { fatalError("must be tuple type") }
    let name = Mangler.mangle(context.canonicalType(type))
    if let existing = module.type(named: name) { return existing }
    return builder.createStruct(name: name, types: fields.map(resolveLLVMType))
  }
  
  func visitNumExpr(_ expr: NumExpr) -> Result {
    let llvmTy = resolveLLVMType(expr.type!)
    switch llvmTy {
    case let type as FloatType:
      return type.constant(Double(expr.value))
    case let type as IntType:
      return type.constant(expr.value, signExtend: true)
    default:
      fatalError("non-number NumExpr")
    }
  }
  
  func visitCharExpr(_ expr: CharExpr) -> Result {
    return IntType.int8.constant(expr.value, signExtend: true)
  }
  
  func visitFloatExpr(_ expr: FloatExpr) -> Result {
    guard let type = resolveLLVMType(expr.type!) as? FloatType else {
      fatalError("non-float floatexpr?")
    }
    return type.constant(expr.value)
  }
  
  func visitBoolExpr(_ expr: BoolExpr) -> Result {
    return expr.value
  }
  
  func visitArrayExpr(_ expr: ArrayExpr) -> Result {
    guard case .array(let fieldTy, _)? = expr.type else {
      fatalError("invalid array type")
    }
    let irType = resolveLLVMType(expr.type!)
    var initial = irType.null()
    for (idx, value) in expr.values.enumerated() {
      var irValue = visit(value)!
      let index = IntType.int64.constant(idx)
      if case .any = context.canonicalType(fieldTy) {
        irValue = codegenPromoteToAny(value: irValue, type: value.type!)
      }
      initial = builder.buildInsertElement(vector: initial, element: irValue, index: index)
    }
    return initial
  }
  
  func visitTupleExpr(_ expr: TupleExpr) -> Result {
    let type = resolveLLVMType(expr.type!)
    guard case .tuple(let tupleTypes)? = expr.type else {
      fatalError("invalid tuple type")
    }
    var initial = type.null()
    for (idx, field) in expr.values.enumerated() {
      var val = visit(field)!
      let canTupleTy = context.canonicalType(tupleTypes[idx])
      if case .any = canTupleTy {
        val = codegenPromoteToAny(value: val, type: field.type!)
      }
      initial = builder.buildInsertValue(aggregate: initial,
                                         element: val,
                                         index: idx,
                                         name: "tuple-insert")
    }
    return initial
  }
  
  func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) -> Result {
    let ptr = resolvePtr(expr.lhs)
    let gep = builder.buildStructGEP(ptr, index: expr.field, name: "tuple-gep")
    return builder.buildLoad(gep, name: "tuple-load")
  }
  
  func visitVarExpr(_ expr: VarExpr) -> Result {
    guard let binding = resolveVarBinding(expr) else { return nil }
    return binding.read()
  }
  
  func visitSizeofExpr(_ expr: SizeofExpr) -> Result {
    return byteSize(of: expr.valueType!)
  }
  
  func byteSize(of type: DataType) -> IRValue {
    if case .array(let subtype, let length?) = type {
      let subSize = byteSize(of: subtype)
      return builder.buildMul(subSize, IntType.int64.constant(length))
    }
    let irType = resolveLLVMType(type)
    return builder.buildTruncOrBitCast(builder.buildSizeOf(irType),
                                       type: IntType.int64)
  }
  
  func visitVoidExpr(_ expr: VoidExpr) -> Result {
    return nil
  }
  
  func visitNilExpr(_ expr: NilExpr) -> Result {
    let type = resolveLLVMType(expr.type!)
    return type.null()
  }
  
  func coerce(_ value: IRValue, from fromType: DataType, to type: DataType) -> Result {
    let irType = resolveLLVMType(type)
    switch (context.canonicalType(fromType), context.canonicalType(type)) {
    case (.int(let lhsWidth, _), .int(let rhsWidth, _)):
      if lhsWidth == rhsWidth { return value }
      if lhsWidth < rhsWidth {
        return builder.buildSExt(value, type: irType, name: "sext-coerce")
      } else {
        return builder.buildTrunc(value, type: irType, name: "trunc-coerce")
      }
    case (.int(_, let signed), .floating):
      return builder.buildIntToFP(value, type: irType as! FloatType,
                                  signed: signed, name: "inttofp-coerce")
    case (.floating, .int(_, let signed)):
      return builder.buildFPToInt(value, type: irType as! IntType,
                                  signed: signed, name: "fptoint-coerce")
    case (.pointer, .int):
      return builder.buildPtrToInt(value, type: irType as! IntType,
                                   name: "ptrtoint-coerce")
    case (.int, .pointer):
      return builder.buildIntToPtr(value, type: irType as! PointerType,
                                   name: "inttoptr-coerce")
    case (.pointer, .pointer):
      return builder.buildBitCast(value, type: irType, name: "bitcast-coerce")
    case (.any, let other):
      return codegenCheckedCast(binding: value, type: other)
    case (_, .any):
      return codegenPromoteToAny(value: value, type: fromType)
    default:
      return builder.buildBitCast(value, type: irType, name: "bitcast-coerce")
    }
  }
  
  func visitStringExpr(_ expr: StringExpr) -> Result {
    let globalPtr = codegenGlobalStringPtr(expr.value)
    let zero = IntType.int64.zero()
    let indices = [zero, zero]
    return globalPtr.constGEP(indices: indices)
  }
  
  func visitSubscriptExpr(_ expr: SubscriptExpr) -> Result {
    if expr.decl == nil {
      let ptr = resolvePtr(expr)
      return builder.buildLoad(ptr, name: "subscript-load")
    } else {
      return visitFuncCallExpr(expr)
    }
  }
  
  func codegen(_ decl: OperatorDecl, lhs: IRValue, rhs: IRValue, type: DataType) -> Result {
    if !decl.has(attribute: .implicit) {
      let function = codegenFunctionPrototype(decl)
      return builder.buildCall(function, args: [lhs, rhs], name: "optmp")
    }
    let signed: Bool
    let overflowBehavior: OverflowBehavior
    if case .int(_, let _signed) = type {
      signed = _signed
      overflowBehavior =
        signed ? .noSignedWrap : .noUnsignedWrap
    } else {
      signed = false
      overflowBehavior = .default
    }
    switch decl.op {
    case .plus:
      return builder.buildAdd(lhs, rhs, overflowBehavior: overflowBehavior)
    case .minus:
      return builder.buildSub(lhs, rhs, overflowBehavior: overflowBehavior)
    case .star:
      return builder.buildMul(lhs, rhs, overflowBehavior: overflowBehavior)
    case .divide:
      return builder.buildDiv(lhs, rhs, signed: signed)
    case .mod:
      return builder.buildRem(lhs, rhs, signed: signed)
    case .equalTo:
      if case .floating = type {
        return builder.buildFCmp(lhs, rhs, .orderedEqual)
      } else if case .int = type {
        return builder.buildICmp(lhs, rhs, .equal)
      }
    case .notEqualTo:
      if case .floating = type {
        return builder.buildFCmp(lhs, rhs, .orderedNotEqual)
      } else if case .int = type {
        return builder.buildICmp(lhs, rhs, .notEqual)
      }
    case .lessThan:
      if case .floating = type {
        return builder.buildFCmp(lhs, rhs, .orderedLessThan)
      } else if case .int(_, let signed) = type {
        return builder.buildICmp(lhs, rhs, signed ? .signedLessThan : .unsignedLessThan)
      }
    case .lessThanOrEqual:
      if case .floating = type {
        return builder.buildFCmp(lhs, rhs, .orderedLessThanOrEqual)
      } else if case .int(_, let signed) = type {
        return builder.buildICmp(lhs, rhs, signed ? .signedLessThanOrEqual : .unsignedLessThanOrEqual)
      }
    case .greaterThan:
      if case .floating = type {
        return builder.buildFCmp(lhs, rhs, .orderedGreaterThan)
      } else if case .int(_, let signed) = type {
        return builder.buildICmp(lhs, rhs, signed ? .signedGreaterThan : .unsignedGreaterThan)
      }
    case .greaterThanOrEqual:
      if case .floating = type {
        return builder.buildFCmp(lhs, rhs, .orderedGreaterThanOrEqual)
      } else if case .int(_, let signed) = type {
        return builder.buildICmp(lhs, rhs, signed ? .signedGreaterThanOrEqual : .unsignedGreaterThanOrEqual)
      }
    case .xor:
      if decl.has(attribute: .implicit) {
        return builder.buildXor(lhs, rhs)
      }
    case .ampersand:
      if decl.has(attribute: .implicit) {
        return builder.buildAnd(lhs, rhs)
      }
    case .bitwiseOr:
      if decl.has(attribute: .implicit) {
        return builder.buildOr(lhs, rhs)
      }
    case .leftShift:
      if decl.has(attribute: .implicit) {
        return builder.buildShl(lhs, rhs)
      }
    case .rightShift:
      if decl.has(attribute: .implicit) {
        return builder.buildShr(lhs, rhs)
      }
    default:
      break
    }
    fatalError("unknown decl \(decl)")
  }
  
  func codegenShortCircuit(_ expr: InfixOperatorExpr) -> PhiNode {
    guard let block = builder.insertBlock else {
      fatalError("no insert block?")
    }
    guard let function = currentFunction?.functionRef else {
      fatalError("outside function")
    }
    let secondCaseBB = function.appendBasicBlock(named: "secondcase", in: llvmContext)
    let endBB = function.appendBasicBlock(named: "end", in: llvmContext)
    let lhs = visit(expr.lhs)!
    if expr.op == .and {
      builder.buildCondBr(condition: lhs, then: secondCaseBB, else: endBB)
    } else {
      builder.buildCondBr(condition: lhs, then: endBB, else: secondCaseBB)
    }
    builder.positionAtEnd(of: secondCaseBB)
    let rhs = visit(expr.rhs)!
    builder.buildBr(endBB)
    builder.positionAtEnd(of: endBB)
    let phi = builder.buildPhi(IntType.int1, name: "op-phi")
    phi.addIncoming([
      (lhs, block),
      (rhs, secondCaseBB)
    ])
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
      let lhs: IRValue
      
      // To support casting between indirect types and void pointers,
      // don't actually load the lhs here. Just get a pointer to it.
      if let decl = context.decl(for: expr.lhs.type!), decl.isIndirect {
        lhs = resolvePtr(expr.lhs)
      } else {
        lhs = visit(expr.lhs)!
      }
      return coerce(lhs, from: expr.lhs.type!, to: expr.type!)
    }
    
    if case .is = expr.op {
      let lhs = visit(expr.lhs)!
      return codegenTypeCheck(lhs, type: expr.rhs.type!)
    }
    
    var rhs = visit(expr.rhs)!
    
    if case .assign = expr.op {
      if case .any? = expr.lhs.type {
        rhs = codegenPromoteToAny(value: rhs, type: expr.rhs.type!)
      }
      let ptr = resolvePtr(expr.lhs)
      return builder.buildStore(rhs, to: ptr)
    } else if context.canBeNil(expr.lhs.type!) && expr.rhs is NilExpr {
      let lhs = visit(expr.lhs)!
      if case .equalTo = expr.op {
        return builder.buildIsNull(lhs)
      } else if case .notEqualTo = expr.op {
        return builder.buildIsNotNull(lhs)
      }
    } else if expr.op.associatedOp != nil {
      let ptr = resolvePtr(expr.lhs)
      let lhsVal = builder.buildLoad(ptr, name: "cmpassignload")
      let performed = codegen(expr.decl!, lhs: lhsVal, rhs: rhs, type: expr.lhs.type!)!
      return builder.buildStore(performed, to: ptr)
    }
    
    let lhs = visit(expr.lhs)!
    return codegen(expr.decl!, lhs: lhs, rhs: rhs, type: expr.lhs.type!)
  }
  
  func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) -> Result {
    return visitStringExpr(expr) // It should have a value by now.
  }
  
  func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) -> Result {
    switch expr.op {
    case .minus:
      let val = visit(expr.rhs)!
      return builder.buildNeg(val)
    case .bitwiseNot:
      let val = visit(expr.rhs)!
      return builder.buildNot(val)
    case .not:
      let val = visit(expr.rhs)!
      return builder.buildNot(val)
    case .star:
      let val = visit(expr.rhs)!
      return builder.buildLoad(val, name: "deref")
    case .ampersand:
      return resolvePtr(expr.rhs)
    default:
      fatalError("unknown operator \(expr.op)")
    }
  }
  
  func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    guard let function = currentFunction?.functionRef else { fatalError("no function") }
    guard let type = expr.type else { fatalError("no ternary type") }
    let irType = resolveLLVMType(type)
    let cond = visit(expr.condition)!
    let truebb = function.appendBasicBlock(named: "true-case", in: llvmContext)
    let falsebb = function.appendBasicBlock(named: "false-case", in: llvmContext)
    let endbb = function.appendBasicBlock(named: "ternary-end", in: llvmContext)
    builder.buildCondBr(condition: cond, then: truebb, else: falsebb)
    builder.positionAtEnd(of: truebb)
    let trueVal = visit(expr.trueCase)!
    builder.buildBr(endbb)
    builder.positionAtEnd(of: falsebb)
    let falseVal = visit(expr.falseCase)!
    builder.buildBr(endbb)
    builder.positionAtEnd(of: endbb)
    let phi = builder.buildPhi(irType, name: "ternary-phi")
    phi.addIncoming([
      (trueVal, truebb),
      (falseVal, falsebb)
    ])
    return phi
  }
}
