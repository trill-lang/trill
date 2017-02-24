//
//  BaseSema.swift
//  Trill
//

import Foundation

enum SemaError: Error, CustomStringConvertible {
  case unknownFunction(name: Identifier)
  case unknownType(type: DataType)
  case callNonFunction(type: DataType?)
  case unknownField(typeDecl: TypeDecl, expr: FieldLookupExpr)
  case unknownVariableName(name: Identifier)
  case invalidOperands(op: BuiltinOperator, invalid: DataType)
  case cannotSubscript(type: DataType)
  case cannotCoerce(type: DataType, toType: DataType)
  case varArgsInNonForeignDecl
  case foreignFunctionWithBody(name: Identifier)
  case nonForeignFunctionWithoutBody(name: Identifier)
  case foreignVarWithRHS(name: Identifier)
  case dereferenceNonPointer(type: DataType)
  case cannotSwitch(type: DataType)
  case nonPointerNil(type: DataType)
  case notAllPathsReturn(type: DataType)
  case caseMustBeConstant
  case noViableOverload(name: Identifier, args: [Argument])
  case candidates([FuncDecl])
  case ambiguousReference(name: Identifier)
  case addressOfRValue
  case breakNotAllowed
  case continueNotAllowed
  case fieldOfFunctionType(type: DataType)
  case duplicateMethod(name: Identifier, type: DataType)
  case duplicateField(name: Identifier, type: DataType)
  case referenceSelfInProp(name: Identifier)
  case poundFunctionOutsideFunction
  case assignToConstant(name: Identifier?)
  case deinitOnStruct(name: Identifier?)
  case incompleteTypeAccess(type: DataType, operation: String)
  case indexIntoNonTuple
  case outOfBoundsTupleField(field: Int, max: Int)
  case nonMatchingArrayType(DataType, DataType)
  case ambiguousType
  case operatorsMustHaveTwoArgs(op: BuiltinOperator)
  case cannotOverloadOperator(op: BuiltinOperator, type: String)
  case isCheckAlways(fails: Bool)
  case pointerFieldAccess(lhs: DataType, field: Identifier)
  
  var description: String {
    switch self {
    case .unknownFunction(let name):
      return "unknown function '\(name)'"
    case .unknownType(let type):
      return "unknown type '\(type)'"
    case .unknownVariableName(let name):
      return "unknown variable '\(name)'"
    case .unknownField(let typeDecl, let expr):
      return "unknown field name '\(expr.name)' in type '\(typeDecl.type)'"
    case .invalidOperands(let op, let invalid):
      return "invalid argument for operator '\(op)' (got '\(invalid)')"
    case .cannotSubscript(let type):
      return "cannot subscript value of type '\(type)'"
    case .cannotCoerce(let type, let toType):
      return "cannot coerce '\(type)' to '\(toType)'"
    case .cannotSwitch(let type):
      return "cannot switch over values of type '\(type)'"
    case .foreignFunctionWithBody(let name):
      return "foreign function '\(name)' cannot have a body"
    case .nonForeignFunctionWithoutBody(let name):
      return "function '\(name)' must have a body"
    case .foreignVarWithRHS(let name):
      return "foreign var '\(name)' cannot have a value"
    case .varArgsInNonForeignDecl:
      return "varargs in non-foreign declarations are not yet supported"
    case .nonPointerNil(let type):
      return "cannot set non-pointer type '\(type)' to nil"
    case .caseMustBeConstant:
      return "case statement expressions must be constants"
    case .dereferenceNonPointer(let type):
      return "cannot dereference a value of non-pointer type '\(type)'"
    case .addressOfRValue:
      return "cannot get address of an r-value"
    case .breakNotAllowed:
      return "'break' not allowed outside loop"
    case .continueNotAllowed:
      return "'continue' not allowed outside loop"
    case .notAllPathsReturn(let type):
      return "missing return in a function expected to return \(type)"
    case .noViableOverload(let name, let args):
      var s = "could not find a viable overload for \(name) with arguments of type ("
      s += args.map {
        var d = ""
        if let label = $0.label {
          d += "\(label): "
        }
        if let t = $0.val.type {
          d += t.description
        } else {
          d += "<<error type>>"
        }
        return d
        }.joined(separator: ", ")
      s += ")"
      return s
    case .candidates(let functions):
      var s = "found candidates with these arguments: "
      s += functions.map { $0.formattedParameterList }.joined(separator: ", ")
      return s
    case .ambiguousReference(let name):
      return "ambiguous reference to '\(name)'"
    case .callNonFunction(let type):
      return "cannot call non-function type '" + (type.map { String(describing: $0) } ?? "<<error type>>") + "'"
    case .fieldOfFunctionType(let type):
      return "cannot find field on function of type \(type)"
    case .duplicateMethod(let name, let type):
      return "invalid redeclaration of method '\(name)' on type '\(type)'"
    case .duplicateField(let name, let type):
      return "invalid redeclaration of field '\(name)' on type '\(type)'"
    case .referenceSelfInProp(let name):
      return "type '\(name)' cannot have a property that references itself"
    case .poundFunctionOutsideFunction:
      return "'#function' is only valid inside function scope"
    case .deinitOnStruct(let name):
      return "cannot have a deinitializer in non-indirect type '\(name)'"
    case .assignToConstant(let name):
      let val: String
      if let n = name {
        val = "'\(n)'"
      } else {
        val = "expression"
      }
      return "cannot mutate \(val); expression is a 'let' constant"
    case .indexIntoNonTuple:
      return "cannot index into non-tuple expression"
    case .outOfBoundsTupleField(let field, let max):
      return "cannot access field \(field) in tuple with \(max) fields"
    case .incompleteTypeAccess(let type, let operation):
      return "cannot \(operation) incomplete type '\(type)'"
    case .nonMatchingArrayType(let arrayType, let elementType):
      return "element type '\(elementType)' does not match array type '\(arrayType)'"
    case .ambiguousType:
      return "type is ambiguous without more context"
    case .operatorsMustHaveTwoArgs(let op):
      return "definition for operator '\(op)' must have two arguments"
    case .cannotOverloadOperator(let op, let type):
      return "cannot overload \(type) operator '\(op)'"
    case .isCheckAlways(let fails):
      return "`is` check always \(fails ? "fails" : "succeeds")"
    case .pointerFieldAccess(let lhs, let field):
      return "cannot access field \(field) of pointer type \(lhs)"
    }
  }
}

enum FieldKind {
  case method, staticMethod, property
}

class Sema: ASTTransformer, Pass {
  var varBindings = [String: VarAssignDecl]()
  
  var title: String {
    return "Semantic Analysis"
  }
  
  override func run(in context: ASTContext) {
    registerTopLevelDecls(in: context)
    super.run(in: context)
  }
  
  func registerTopLevelDecls(in context: ASTContext) {
    for expr in context.extensions {
      guard let typeDecl = context.decl(for: expr.type) else {
        error(SemaError.unknownType(type: expr.type),
              loc: expr.startLoc,
              highlights: [ expr.sourceRange ])
        continue
      }
      for method in expr.methods {
        typeDecl.addMethod(method, named: method.name.name)
      }
      for subscriptDecl in expr.subscripts {
        typeDecl.addSubscript(subscriptDecl)
      }
    }
    for expr in context.types {
      let oldBindings = varBindings
      defer { varBindings = oldBindings }
      var fieldNames = Set<String>()
      for field in expr.fields {
        field.kind = .property(expr)
        if fieldNames.contains(field.name.name) {
          error(SemaError.duplicateField(name: field.name,
                                         type: expr.type),
                loc: field.startLoc,
                highlights: [ expr.name.range ])
          continue
        }
        fieldNames.insert(field.name.name)
      }
      var methodNames = Set<String>()
      for method in expr.methods + expr.staticMethods {
        let mangled = Mangler.mangle(method)
        if methodNames.contains(mangled) {
          error(SemaError.duplicateMethod(name: method.name,
                                          type: expr.type),
                loc: method.startLoc,
                highlights: [ expr.name.range ])
          continue
        }
        methodNames.insert(mangled)
      }
      if context.isCircularType(expr) {
        error(SemaError.referenceSelfInProp(name: expr.name),
              loc: expr.startLoc,
              highlights: [
                expr.name.range
          ])
      }
    }
  }
  
  override func visitFuncDecl(_ expr: FuncDecl) {
    super.visitFuncDecl(expr)
    if expr.has(attribute: .foreign) {
      if !(expr is InitializerDecl) && expr.body != nil {
        error(SemaError.foreignFunctionWithBody(name: expr.name),
              loc: expr.name.range?.start,
              highlights: [
                expr.name.range
          ])
        return
      }
    } else {
      if !expr.has(attribute: .implicit) && expr.body == nil {
        error(SemaError.nonForeignFunctionWithoutBody(name: expr.name),
              loc: expr.name.range?.start,
              highlights: [
                expr.name.range
          ])
        return
      }
      if expr.hasVarArgs {
        error(SemaError.varArgsInNonForeignDecl,
              loc: expr.startLoc)
        return
      }
    }
    let returnType = expr.returnType.type!
    if !context.isValidType(returnType) {
      error(SemaError.unknownType(type: returnType),
            loc: expr.returnType.startLoc,
            highlights: [
              expr.returnType.sourceRange
        ])
      return
    }
    if let body = expr.body,
        !body.hasReturn,
        returnType != .void,
        !expr.has(attribute: .implicit),
        !(expr is InitializerDecl) {
      error(SemaError.notAllPathsReturn(type: expr.returnType.type!),
            loc: expr.sourceRange?.start,
            highlights: [
              expr.name.range,
              expr.returnType.sourceRange
        ])
      return
    }
    if let destr = expr as? DeinitializerDecl,
       let decl = context.decl(for: destr.parentType, canonicalized: true),
       !decl.isIndirect {
     error(SemaError.deinitOnStruct(name: decl.name))
    }
  }
  
  override func withScope(_ e: CompoundStmt, _ f: () -> Void) {
    let oldVarBindings = varBindings
    super.withScope(e, f)
    varBindings = oldVarBindings
  }
  
  override func visitVarAssignDecl(_ decl: VarAssignDecl) -> Result {
    super.visitVarAssignDecl(decl)
    if let rhs = decl.rhs, decl.has(attribute: .foreign) {
      error(SemaError.foreignVarWithRHS(name: decl.name),
            loc: decl.startLoc,
            highlights: [ rhs.sourceRange ])
      return
    }
    guard !decl.has(attribute: .foreign) else { return }
    if let type = decl.typeRef?.type {
      if !context.isValidType(type) {
        error(SemaError.unknownType(type: type),
              loc: decl.typeRef!.startLoc,
              highlights: [
                decl.typeRef!.sourceRange
          ])
        return
      }
    }
    if let fn = currentFunction {
      decl.kind = .local(fn)
    } else if let type = currentType {
      decl.kind = .property(type)
    } else {
      decl.kind = .global
    }
    
    switch decl.kind {
    case .local, .global:
      varBindings[decl.name.name] = decl
    default: break
    }
    
    if let rhs = decl.rhs, decl.typeRef == nil {
      guard let type = rhs.type else { return }
      let canRhs = context.canonicalType(type)
      if case .void = canRhs {
        error(SemaError.incompleteTypeAccess(type: type, operation: "assign value from"),
              loc: rhs.startLoc,
              highlights: [
                rhs.sourceRange
          ])
        return
      }
      
      decl.type = type
      decl.typeRef = type.ref()
      
    }
  }
  
  override func visitParenExpr(_ expr: ParenExpr) {
    super.visitParenExpr(expr)
    expr.type = expr.value.type
  }
  
  override func visitSizeofExpr(_ expr: SizeofExpr) -> Result {
    let handleVar = { (varExpr: VarExpr) in
      let possibleType = DataType(name: varExpr.name.name)
      if self.context.isValidType(possibleType) {
        expr.valueType = possibleType
      } else {
        super.visitSizeofExpr(expr)
        expr.valueType = varExpr.type
      }
    }
    if let varExpr = expr.value as? VarExpr {
      handleVar(varExpr)
    } else if let varExpr = (expr.value as? ParenExpr)?.rootExpr as? VarExpr {
      handleVar(varExpr)
    } else {
      super.visitSizeofExpr(expr)
      expr.valueType = expr.value!.type
    }
  }
  
  override func visitParamDecl(_ decl: ParamDecl) -> Result {
    super.visitParamDecl(decl)
    guard context.isValidType(decl.type) else {
      error(SemaError.unknownType(type: decl.type),
            loc: decl.typeRef?.startLoc,
            highlights: [
              decl.typeRef?.sourceRange
        ])
      return
    }
    decl.kind = .local(currentFunction!)
    let canTy = context.canonicalType(decl.type)
    if case .custom = canTy,
      context.decl(for: canTy)!.isIndirect {
      decl.mutable = true
    }
    varBindings[decl.name.name] = decl
  }
  
  override func visitFieldLookupExpr(_ expr: FieldLookupExpr) {
    _ = visitFieldLookupExpr(expr, callArgs: nil)
  }
  
  /// - returns: true if the resulting decl is a field of function type,
  ///            instead of a method
  func visitFieldLookupExpr(_ expr: FieldLookupExpr, callArgs: [Argument]?) -> FieldKind {
    super.visitFieldLookupExpr(expr)
    guard let type = expr.lhs.type else {
      // An error will already have been thrown from here
      return .property
    }
    if let type = expr.lhs.type, case .pointer(_) = context.canonicalType(type) {
      error(SemaError.pointerFieldAccess(lhs: type, field: expr.name),
            loc: expr.dotLoc,
            highlights: [
              expr.name.range
        ])
      return .property
    }
    if case .function = type {
      error(SemaError.fieldOfFunctionType(type: type),
            loc: expr.startLoc,
            highlights: [
              expr.sourceRange
        ])
      return .property
    }
    guard let typeDecl = context.decl(for: type) else {
      error(SemaError.unknownType(type: type.rootType),
            loc: expr.startLoc,
            highlights: [
              expr.sourceRange
        ])
      return .property
    }
    expr.typeDecl = typeDecl
    if let varExpr = expr.lhs as? VarExpr, varExpr.isTypeVar {
      expr.decl = varExpr.decl
      expr.type = varExpr.decl?.type
      return .staticMethod
    }
    let candidateMethods = typeDecl.methods(named: expr.name.name)
    if let callArgs = callArgs,
       let index = typeDecl.indexOf(fieldName: expr.name) {
      let field = typeDecl.fields[index]
      if case .function(let args, _) = field.type {
        let types = callArgs.flatMap { $0.val.type }
        if types.count == callArgs.count && args == types {
          expr.decl = field
          expr.type = field.type
          return .property
        }
      }
    }
    if let decl = typeDecl.field(named: expr.name.name) {
      expr.decl = decl
      expr.type = decl.type
      return .property
    } else if !candidateMethods.isEmpty {
      if let args = callArgs,
         let funcDecl = context.candidate(forArgs: args, candidates: candidateMethods) {
        expr.decl = funcDecl
        let types = funcDecl.args.map { $0.type }
        expr.type = .function(args: types, returnType: funcDecl.returnType.type!)
        return .method
      } else {
        error(SemaError.ambiguousReference(name: expr.name),
              loc: expr.startLoc,
              highlights: [
                expr.sourceRange
          ])
        return .property
      }
    } else {
      error(SemaError.unknownField(typeDecl: typeDecl, expr: expr),
            loc: expr.startLoc,
            highlights: [ expr.name.range ])
      return .property
    }
  }
  
  override func visitArrayExpr(_ expr: ArrayExpr) {
    super.visitArrayExpr(expr)
    guard let first = expr.values.first?.type else {
      error(SemaError.ambiguousType,
            loc: expr.startLoc,
            highlights: [
              expr.sourceRange
            ])
      return
    }
    for value in expr.values {
      guard let type = value.type else { return }
      guard matches(type, first) else {
        error(SemaError.nonMatchingArrayType(first, type),
              loc: value.startLoc,
              highlights: [
                value.sourceRange
              ])
        return
      }
    }
    expr.type = .array(field: first, length: expr.values.count)
  }
  
  override func visitTupleExpr(_ expr: TupleExpr) {
    super.visitTupleExpr(expr)
    var types = [DataType]()
    for expr in expr.values {
      guard let t = expr.type else { return }
      types.append(t)
    }
    expr.type = .tuple(fields: types)
  }
  
  override func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) -> Result {
    super.visitTupleFieldLookupExpr(expr)
    guard let lhsTy = expr.lhs.type else { return }
    let lhsCanTy = context.canonicalType(lhsTy)
    guard case .tuple(let fields) = lhsCanTy else {
      error(SemaError.indexIntoNonTuple,
            loc: expr.startLoc,
            highlights: [
              expr.sourceRange
            ])
      return
    }
    if expr.field >= fields.count {
      error(SemaError.outOfBoundsTupleField(field: expr.field, max: fields.count),
            loc: expr.fieldRange.start,
            highlights: [
              expr.fieldRange
            ])
      return
    }
    expr.type = fields[expr.field]
  }
  
  override func visitSubscriptExpr(_ expr: SubscriptExpr) -> Result {
    super.visitSubscriptExpr(expr)
    guard let type = expr.lhs.type else { return }
    let diagnose: () -> Void = {
      self.error(SemaError.cannotSubscript(type: type),
                 loc: expr.startLoc,
                 highlights: [ expr.lhs.sourceRange ])
    }
    let elementType: DataType
    switch type {
    case .pointer(let subtype):
      elementType = subtype
    case .array(let element, _):
      elementType = element
    default:
      guard let decl = context.decl(for: type), !decl.subscripts.isEmpty else {
        diagnose()
        return
      }
      guard let candidate = context.candidate(forArgs: expr.args, candidates: decl.subscripts) as? SubscriptDecl else {
        diagnose()
        return
      }
      elementType = candidate.returnType.type!
      expr.decl = candidate
    }
    guard elementType != .void else {
      error(SemaError.incompleteTypeAccess(type: elementType, operation: "subscript"),
            loc: expr.lhs.startLoc,
            highlights: [
              expr.lhs.sourceRange
            ])
      return
    }
    expr.type = elementType
  }
  
  override func visitExtensionDecl(_ expr: ExtensionDecl) -> Result {
    guard let decl = context.decl(for: expr.type) else {
      error(SemaError.unknownType(type: expr.type),
            loc: expr.startLoc,
            highlights: [ expr.typeRef.name.range ])
      return
    }
    withTypeDecl(decl) {
      super.visitExtensionDecl(expr)
    }
    expr.typeDecl = decl
  }
  
  override func visitVarExpr(_ expr: VarExpr) -> Result {
    super.visitVarExpr(expr)
    if
      let fn = currentFunction,
      fn is InitializerDecl,
      expr.name == "self" {
      expr.decl = VarAssignDecl(name: "self", typeRef: fn.returnType, kind: .implicitSelf(fn, currentType!))
      expr.isSelf = true
      expr.type = fn.returnType.type!
      return
    }
    let candidates = context.functions(named: expr.name)
    if let decl = varBindings[expr.name.name] ?? context.global(named: expr.name) {
      expr.decl = decl
      expr.type = decl.type
      if let d = decl as? ParamDecl, d.isImplicitSelf {
        expr.isSelf = true
      }
    } else if !candidates.isEmpty {
      if let funcDecl = candidates.first, candidates.count == 1 {
        expr.decl = funcDecl
        expr.type = funcDecl.type
      } else {
        error(SemaError.ambiguousReference(name: expr.name),
              loc: expr.startLoc,
              highlights: [
                expr.sourceRange
          ])
        return
      }
    } else if let decl = context.decl(for: DataType(name: expr.name.name)) {
      expr.isTypeVar = true
      expr.decl = decl
      expr.type = DataType(name: expr.name.name)
    }
    guard let decl = expr.decl else {
      error(SemaError.unknownVariableName(name: expr.name),
            loc: expr.startLoc,
            highlights: [ expr.sourceRange ])
      return
    }
    if let closure = currentClosure {
      closure.add(capture: decl)
    }
  }
  
  override func visitContinueStmt(_ stmt: ContinueStmt) -> Result {
    if currentBreakTarget == nil {
      error(SemaError.continueNotAllowed,
            loc: stmt.startLoc,
            highlights: [ stmt.sourceRange ])
    }
  }
  
  override func visitBreakStmt(_ stmt: BreakStmt) -> Result {
    if currentBreakTarget == nil {
      error(SemaError.breakNotAllowed,
            loc: stmt.startLoc,
            highlights: [ stmt.sourceRange ])
    }
  }
  
  override func visitTypeAliasDecl(_ decl: TypeAliasDecl) -> Result {
    guard let bound = decl.bound.type else { return }
    guard context.isValidType(bound) else {
      error(SemaError.unknownType(type: bound),
            loc: decl.bound.startLoc,
            highlights: [
              decl.bound.sourceRange
        ])
      return
    }
  }
  
  override func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result {
    expr.args.forEach {
      visit($0.val)
    }
    
    for arg in expr.args {
      guard arg.val.type != nil else { return }
    }
    var candidates = [FuncDecl]()
    var name: Identifier? = nil
    
    var setLHSDecl: (Decl) -> Void = {_ in }
    
    switch expr.lhs {
    case let lhs as FieldLookupExpr:
      name = lhs.name
      let fieldKind = visitFieldLookupExpr(lhs, callArgs: expr.args)
      guard let typeDecl = lhs.typeDecl else {
        return
      }
      switch fieldKind {
      case .property:
        if case .function(var args, let ret)? = lhs.type {
          candidates.append(context.implicitDecl(args: args, ret: ret))
          args.insert(typeDecl.type, at: 0)
          lhs.type = .function(args: args, returnType: ret)
        }
      case .staticMethod:
        candidates += typeDecl.staticMethods(named: lhs.name.name) as [FuncDecl]
      case .method:
        candidates += typeDecl.methods(named: lhs.name.name) as [FuncDecl]
      }
      setLHSDecl = { lhs.decl = $0 }
    case let lhs as VarExpr:
      setLHSDecl = { lhs.decl = $0 }
      name = lhs.name
      if let typeDecl = context.decl(for: DataType(name: lhs.name.name)) {
        candidates += typeDecl.initializers as [FuncDecl]
      } else if let varDecl = varBindings[lhs.name.name] {
        setLHSDecl = { _ in } // override the decl if this is a function variable
        lhs.decl = varDecl
        let type = context.canonicalType(varDecl.type)
        if case .function(let args, let ret) = type {
          candidates.append(context.implicitDecl(args: args, ret: ret))
        } else {
          error(SemaError.callNonFunction(type: type),
                loc: lhs.startLoc,
                highlights: [
                  expr.sourceRange
            ])
          return
        }
      } else {
        candidates += context.functions(named: lhs.name)
      }
    default:
      visit(expr.lhs)
      if case .function(let args, let ret)? = expr.lhs.type {
        candidates += [context.implicitDecl(args: args, ret: ret)]
      } else {
        error(SemaError.callNonFunction(type: expr.lhs.type ?? .void),
              loc: expr.lhs.startLoc,
              highlights: [
                expr.lhs.sourceRange
          ])
        return
      }
    }
    
    guard !candidates.isEmpty else {
      error(SemaError.unknownFunction(name: name!),
            loc: name?.range?.start,
            highlights: [ name?.range ])
      return
    }
    guard let decl = context.candidate(forArgs: expr.args, candidates: candidates) else {
      error(SemaError.noViableOverload(name: name!,
                                       args: expr.args),
            loc: name?.range?.start,
            highlights: [
              name?.range
        ])
      note(SemaError.candidates(candidates))
      return
    }
    setLHSDecl(decl)
    expr.decl = decl
    expr.type = decl.returnType.type
    
    if let lhs = expr.lhs as? FieldLookupExpr {
      if case .immutable(let culprit) = context.mutability(of: lhs),
        decl.has(attribute: .mutating), decl is MethodDecl {
        error(SemaError.assignToConstant(name: culprit),
              loc: name?.range?.start,
              highlights: [
                name?.range
          ])
        return
      }
    }
  }
  
  override func visitCompoundStmt(_ stmt: CompoundStmt) {
    for (idx, e) in stmt.stmts.enumerated() {
      visit(e)
      let isLast = idx == (stmt.stmts.endIndex - 1)
      let isReturn = e is ReturnStmt
      let isBreak = e is BreakStmt
      let isContinue = e is ContinueStmt
      let isNoReturnFuncCall: Bool = {
        if let exprStmt = e as? ExprStmt, let c = exprStmt.expr as? FuncCallExpr {
          return c.decl?.has(attribute: .noreturn) == true
        }
        return false
      }()
      
      if !stmt.hasReturn {
        if isReturn || isNoReturnFuncCall {
          stmt.hasReturn = true
        } else if let ifExpr = e as? IfStmt,
                  let elseBody = ifExpr.elseBody {
          var hasReturn = true
          for block in ifExpr.blocks where !block.1.hasReturn {
            hasReturn = false
          }
          if hasReturn {
            hasReturn = elseBody.hasReturn
          }
          stmt.hasReturn = hasReturn
        }
      }
      
      if (isReturn || isBreak || isContinue || isNoReturnFuncCall) && !isLast {
        let type =
          isReturn ? "return" :
          isContinue ? "continue" :
          isNoReturnFuncCall ? "call to noreturn function" : "break"
        warning("Code after \(type) will not be executed.",
                loc: e.startLoc,
                highlights: [ stmt.sourceRange ])
      }
    }
  }
  
  override func visitClosureExpr(_ expr: ClosureExpr) {
    super.visitClosureExpr(expr)
    var argTys = [DataType]()
    for arg in expr.args {
      argTys.append(arg.type)
    }
    expr.type = .function(args: argTys, returnType: expr.returnType.type!)
  }
  
  override func visitSwitchStmt(_ stmt: SwitchStmt) {
    super.visitSwitchStmt(stmt)
    guard let valueType = stmt.value.type else { return }
    for c in stmt.cases {
      guard context.isGlobalConstant(c.constant) else {
        error(SemaError.caseMustBeConstant,
              loc: c.constant.startLoc,
              highlights: [c.constant.sourceRange])
        return
      }
      guard let decl = context.infixOperatorCandidate(.equalTo,
                                                      lhs: stmt.value,
                                                      rhs: c.constant),
               !decl.returnType.type!.isPointer else {
        error(SemaError.cannotSwitch(type: valueType),
              loc: stmt.value.startLoc,
              highlights: [ stmt.value.sourceRange ])
        continue
      }
    }
  }
  
  override func visitOperatorDecl(_ decl: OperatorDecl) {
    guard decl.args.count == 2 else {
      error(SemaError.operatorsMustHaveTwoArgs(op: decl.op),
            loc: decl.opRange?.start,
            highlights: [
              decl.opRange
            ])
      return
    }
    guard !decl.op.isAssign else {
      let type = decl.op.isCompoundAssign ? "compound-assignment" : "assignment"
      error(SemaError.cannotOverloadOperator(op: decl.op, type: type),
            loc: decl.opRange?.start,
            highlights: [
              decl.opRange
            ])
      return
    }
    super.visitOperatorDecl(decl)
  }
  
  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
    super.visitInfixOperatorExpr(expr)
    guard var lhsType = expr.lhs.type else { return }
    guard var rhsType = expr.rhs.type else { return }
    
    let canLhs = context.canonicalType(lhsType)
    let canRhs = context.canonicalType(rhsType)
    
    if context.propagateContextualType(rhsType, to: expr.lhs) {
      lhsType = rhsType
    } else if context.propagateContextualType(lhsType, to: expr.rhs) {
      rhsType = lhsType
    }
    
    if expr.op.isAssign {
      expr.type = .void
      if case .void = canRhs {
        error(SemaError.incompleteTypeAccess(type: canRhs, operation: "assign value from"),
              loc: expr.rhs.startLoc,
              highlights: [
                expr.rhs.sourceRange
              ])
        return
      }
      if case .immutable(let name) = context.mutability(of: expr.lhs) {
        if currentFunction == nil || !(currentFunction! is InitializerDecl) {
          error(SemaError.assignToConstant(name: name),
                loc: name?.range?.start,
                highlights: [
                  name?.range
            ])
          return
        }
      }
      if expr.rhs is NilExpr, let lhsType = expr.lhs.type {
        guard context.canBeNil(lhsType) else {
          error(SemaError.nonPointerNil(type: lhsType),
                loc: expr.lhs.startLoc,
                highlights: [
                  expr.lhs.sourceRange,
                  expr.rhs.sourceRange
            ])
          return
        }
      }
      if case .assign = expr.op {
        return
      }
    }
    if case .as = expr.op {
      guard context.isValidType(expr.rhs.type!) else {
        error(SemaError.unknownType(type: expr.rhs.type!),
              loc: expr.rhs.startLoc,
              highlights: [expr.rhs.sourceRange])
        return
      }
      if !context.canCoerce(canLhs, to: canRhs) {
        error(SemaError.cannotCoerce(type: lhsType, toType: rhsType),
              loc: expr.opRange?.start,
              highlights: [
                expr.lhs.sourceRange,
                expr.opRange,
                expr.rhs.sourceRange
          ])
        return
      }
      expr.type = rhsType
      return
    }
    if case .is = expr.op {
      guard context.isValidType(expr.rhs.type!) else {
        error(SemaError.unknownType(type: expr.rhs.type!),
              loc: expr.rhs.startLoc,
              highlights: [expr.rhs.sourceRange])
        return
      }
      guard case .any? = expr.lhs.type else {
        let matched = !matches(expr.lhs.type, expr.rhs.type)
        error(SemaError.isCheckAlways(fails: matched),
              loc: expr.opRange?.start,
              highlights: [
                expr.lhs.sourceRange,
                expr.rhs.sourceRange
          ])
        return
      }
      expr.type = .bool
      return
    }
    let lookupOp = expr.op.associatedOp ?? expr.op
    if let decl = context.infixOperatorCandidate(lookupOp,
                                                 lhs: expr.lhs,
                                                 rhs: expr.rhs) {
      expr.decl = decl
      if expr.op.isAssign {
        expr.type = .void
      } else {
        expr.type = decl.returnType.type
      }
      return
    }
    error(SemaError.noViableOverload(name: Identifier(name: "\(expr.op)"), args: [
        Argument(val: expr.lhs),
        Argument(val: expr.rhs)
      ]), loc: expr.opRange?.start)
  }
  
  override func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    super.visitTernaryExpr(expr)
    expr.type = expr.trueCase.type
  }
  
  override func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) -> Result {
    super.visitPoundFunctionExpr(expr)
    guard let funcDecl = currentFunction else {
      error(SemaError.poundFunctionOutsideFunction,
            loc: expr.startLoc,
            highlights: [
              expr.sourceRange
        ])
      return
    }
    expr.value = funcDecl.formattedName
  }
  
  override func visitPoundDiagnosticStmt(_ stmt: PoundDiagnosticStmt) {
    if stmt.isError {
      context.diag.error(stmt.text, loc: stmt.content.startLoc, highlights: [])
    } else {
      context.diag.warning(stmt.text, loc: stmt.content.startLoc, highlights: [])
    }
  }
  
  override func visitReturnStmt(_ stmt: ReturnStmt) {
    guard let returnType = currentClosure?.returnType.type ?? currentFunction?.returnType.type else { return }
    context.propagateContextualType(returnType, to: stmt.value)
    super.visitReturnStmt(stmt)
  }
  
  override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) {
    super.visitPrefixOperatorExpr(expr)
    guard let rhsType = expr.rhs.type else { return }
    guard let exprType = expr.type(forArgType: context.canonicalType(rhsType)) else {
      error(SemaError.invalidOperands(op: expr.op, invalid: rhsType),
            loc: expr.opRange?.start,
            highlights: [
              expr.opRange,
              expr.rhs.sourceRange
            ])
      return
    }
    expr.type = exprType
    if expr.op == .star {
      guard case .pointer(let subtype) = rhsType else {
        error(SemaError.dereferenceNonPointer(type: rhsType),
              loc: expr.opRange?.start,
              highlights: [
                expr.opRange,
                expr.rhs.sourceRange
          ])
        return
      }
      guard subtype != .void else {
        error(SemaError.incompleteTypeAccess(type: subtype, operation: "dereference"),
              loc: expr.startLoc,
              highlights: [
                expr.sourceRange
              ])
        return
      }
    }
    if expr.op == .ampersand {
      guard expr.rhs is LValue else {
        error(SemaError.addressOfRValue,
              loc: expr.opRange?.start,
              highlights: [
                expr.opRange,
                expr.rhs.sourceRange
          ])
        return
      }
    }
  }
}
