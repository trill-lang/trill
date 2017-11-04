///
/// ValueIRGen.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import LLVM
import Foundation

extension IRGenerator {
  func codegenGlobalStringPtr(_ string: String) -> (ptr: IRValue, length: Int) {
    if let global = globalStringMap[string] { return global }
    let globalStringPtr = builder.buildGlobalStringPtr(string)
    let length = string.utf8.count
    globalStringMap[string] = (globalStringPtr, length)
    return (globalStringPtr, length)
  }
  
  func codegenTupleType(_ type: DataType) -> IRType {
    guard case .tuple(let fields) = type else { fatalError("must be tuple type") }
    let name = Mangler.mangle(context.canonicalType(type))
    if let existing = module.type(named: name) { return existing }
    return builder.createStruct(name: name, types: fields.map(resolveLLVMType))
  }
  
  public func visitNumExpr(_ expr: NumExpr) -> Result {
    let llvmTy = resolveLLVMType(expr.type)
    switch llvmTy {
    case let type as FloatType:
      return type.constant(Double(expr.value))
    case let type as IntType:
      return type.constant(expr.value, signExtend: true)
    default:
      fatalError("non-number NumExpr")
    }
  }
  
  public func visitCharExpr(_ expr: CharExpr) -> Result {
    return IntType.int8.constant(expr.value, signExtend: true)
  }
  
  public func visitFloatExpr(_ expr: FloatExpr) -> Result {
    guard let type = resolveLLVMType(expr.type) as? FloatType else {
      fatalError("non-float floatexpr?")
    }
    return type.constant(expr.value)
  }
  
  public func visitBoolExpr(_ expr: BoolExpr) -> Result {
    return expr.value
  }
  
  public func visitArrayExpr(_ expr: ArrayExpr) -> Result {
    guard case .array(let fieldTy, _) = expr.type else {
      fatalError("invalid array type")
    }
    let irType = resolveLLVMType(expr.type)
    var initial = irType.null()
    for (idx, value) in expr.values.enumerated() {
      var irValue = visit(value)!
      let index = IntType.int64.constant(idx)
      if case .any = context.canonicalType(fieldTy) {
        irValue = codegenPromoteToAny(value: irValue, type: value.type)
      }
      initial = builder.buildInsertElement(vector: initial, element: irValue, index: index)
    }
    return initial
  }
  
  public func visitTupleExpr(_ expr: TupleExpr) -> Result {
    let type = resolveLLVMType(expr.type)
    guard case .tuple(let tupleTypes) = expr.type else {
      fatalError("invalid tuple type")
    }
    var initial = type.null()
    for (idx, field) in expr.values.enumerated() {
      var val = visit(field)!
      let canTupleTy = context.canonicalType(tupleTypes[idx])
      if case .any = canTupleTy {
        val = codegenPromoteToAny(value: val, type: field.type)
      }
      initial = builder.buildInsertValue(aggregate: initial,
                                         element: val,
                                         index: idx,
                                         name: "tuple-insert")
    }
    return initial
  }
  
  public func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) -> Result {
    let ptr = resolvePtr(expr.lhs)
    let gep = builder.buildStructGEP(ptr, index: expr.field, name: "tuple-gep")
    return builder.buildLoad(gep, name: "tuple-load")
  }
  
  public func visitVarExpr(_ expr: VarExpr) -> Result {
    guard let binding = resolveVarBinding(expr) else { return nil }
    return binding.read()
  }
  
  public func visitSizeofExpr(_ expr: SizeofExpr) -> Result {
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
  
  public func visitVoidExpr(_ expr: VoidExpr) -> Result {
    return nil
  }
  
  public func visitNilExpr(_ expr: NilExpr) -> Result {
    let type = resolveLLVMType(expr.type)
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
  
  public func visitStringExpr(_ expr: StringExpr) -> Result {
    let globalString = codegenGlobalStringPtr(expr.value)
    if case .pointer(type: DataType.int8) = expr.type {
      return globalString.ptr
    }

    guard let stringInitializer = context.stdlib?.staticStringInitializer else {
      fatalError("attempting to codegen String without stdlib")
    }
    let function = codegenFunctionPrototype(stringInitializer)

    return builder.buildCall(function, args: [globalString.ptr, globalString.length], name: "string-init")
  }
  
  public func visitStringInterpolationExpr(_ expr: StringInterpolationExpr) -> Result {
    guard let stringInitializer = context.stdlib?.staticStringInterpolationSegmentsInitializer else {
      fatalError("attempting to codegen String w/ interpolation segments without stdlib")
    }
    let function = codegenFunctionPrototype(stringInitializer)
    
    guard let arrayInitializer = context.stdlib?.anyArrayCapacityInitializer else {
      fatalError()
    }
    let paramInitializer = codegenFunctionPrototype(arrayInitializer)
    let segmentsParam = builder.buildCall(paramInitializer, args: [expr.segments.count + 1], name: "string-interpolation-segments-init")
    guard let arrayAppend = context.stdlib?.anyArrayAppendElement else {
      fatalError()
    }
    let alloca = self.createEntryBlockAlloca(self.currentFunction!.functionRef!,
                                             type: resolveLLVMType(arrayInitializer.parentType), name: "segments-param-ptr",
                                             storage: .value)
    self.builder.buildStore(segmentsParam, to: alloca.ref)
    expr.segments.forEach { segment in
      let arg = codegenPromoteToAny(value: visit(segment)!, type: segment.type)
      let _ = builder.buildCall(codegenFunctionPrototype(arrayAppend), args: [alloca.ref, arg])
    }
    
    return builder.buildCall(function, args: [alloca.read()], name: "string-interpolation-init")
  }
  
  public func visitSubscriptExpr(_ expr: SubscriptExpr) -> Result {
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
    let type = context.canonicalType(type)
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
      } else if case .bool = type {
        return builder.buildICmp(lhs, rhs, .equal)
      }
    case .notEqualTo:
      if case .floating = type {
        return builder.buildFCmp(lhs, rhs, .orderedNotEqual)
      } else if case .int = type {
        return builder.buildICmp(lhs, rhs, .notEqual)
      } else if case .bool = type {
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
  
  func codegenShortCircuit(_ expr: InfixOperatorExpr) -> IRValue {
    guard let function = currentFunction?.functionRef else {
      fatalError("outside function")
    }
    let secondCaseBB = function.appendBasicBlock(named: "secondcase", in: llvmContext)
    let endBB = function.appendBasicBlock(named: "end", in: llvmContext)
    let result = createEntryBlockAlloca(function, type: IntType.int1,
                                        name: "op-result", storage: .value)
    let lhs = visit(expr.lhs)!
    result.write(lhs)
    if expr.op == .and {
      builder.buildCondBr(condition: lhs, then: secondCaseBB, else: endBB)
    } else {
      builder.buildCondBr(condition: lhs, then: endBB, else: secondCaseBB)
    }
    builder.positionAtEnd(of: secondCaseBB)
    let rhs = visit(expr.rhs)!
    result.write(rhs)
    builder.buildBr(endBB)
    builder.positionAtEnd(of: endBB)
    return result.read()
  }
  
  public func visitParenExpr(_ expr: ParenExpr) -> Result {
    return visit(expr.value)
  }

  public func visitIsExpr(_ expr: IsExpr) -> Result {
    let lhs = visit(expr.lhs)!
    return codegenTypeCheck(lhs, type: expr.rhs.type)
  }

  public func visitCoercionExpr(_ expr: CoercionExpr) -> Result {
    let lhs = visit(expr.lhs)!
    return coerce(lhs, from: expr.lhs.type, to: expr.type)
  }
  
  public func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) -> Result {
    if [.and, .or].contains(expr.op) {
      return codegenShortCircuit(expr)
    }
    
    var rhs = visit(expr.rhs)!
    
    if case .assign = expr.op {
      if case .any = context.canonicalType(expr.lhs.type) {
        rhs = codegenPromoteToAny(value: rhs, type: expr.rhs.type)
      }
      if let propRef = expr.lhs as? PropertyRefExpr,
         let propDecl = propRef.decl as? PropertyDecl,
         let propSetter = propDecl.setter {
        let setterFn = codegenFunctionPrototype(propSetter)
        let implicitSelf = resolvePtr(propRef.lhs)
        return builder.buildCall(setterFn, args: [implicitSelf, rhs])
      }
      let ptr = resolvePtr(expr.lhs)
      return builder.buildStore(rhs, to: ptr)
    } else if context.canBeNil(expr.lhs.type) && expr.rhs is NilExpr {
      let lhs = visit(expr.lhs)!
      if case .equalTo = expr.op {
        return builder.buildIsNull(lhs)
      } else if case .notEqualTo = expr.op {
        return builder.buildIsNotNull(lhs)
      }
    } else if expr.op.associatedOp != nil {
      let ptr = resolvePtr(expr.lhs)
      let lhsVal = builder.buildLoad(ptr, name: "cmpassignload")
      let performed = codegen(expr.decl!, lhs: lhsVal, rhs: rhs, type: expr.lhs.type)!
      return builder.buildStore(performed, to: ptr)
    }
    
    let lhs = visit(expr.lhs)!
    return codegen(expr.decl!, lhs: lhs, rhs: rhs, type: expr.lhs.type)
  }
  
  public func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) -> Result {
    return visitStringExpr(expr) // It should have a value by now.
  }
  
  public func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) -> Result {
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
  
  public func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    guard let function = currentFunction?.functionRef else { fatalError("no function") }
    let irType = resolveLLVMType(expr.type)
    let cond = visit(expr.condition)!
    let result = createEntryBlockAlloca(function, type: irType,
                                        name: "ternary-result", storage: .value)
    let truebb = function.appendBasicBlock(named: "true-case", in: llvmContext)
    let falsebb = function.appendBasicBlock(named: "false-case", in: llvmContext)
    let endbb = function.appendBasicBlock(named: "ternary-end", in: llvmContext)
    builder.buildCondBr(condition: cond, then: truebb, else: falsebb)
    builder.positionAtEnd(of: truebb)
    let trueVal = coerce(visit(expr.trueCase)!, from: expr.trueCase.type, to: expr.type)!
    result.write(trueVal)
    builder.buildBr(endbb)
    builder.positionAtEnd(of: falsebb)
    let falseVal = coerce(visit(expr.falseCase)!, from: expr.falseCase.type, to: expr.type)!
    result.write(falseVal)
    builder.buildBr(endbb)
    builder.positionAtEnd(of: endbb)
    return result.read()
  }
}
