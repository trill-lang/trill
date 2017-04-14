//
//  BaseSema.swift
//  Trill
//

import Foundation

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
      var propertyNames = Set<String>()
      for property in expr.properties {
        property.kind = .property(expr)
        if propertyNames.contains(property.name.name) {
          error(SemaError.duplicateField(name: property.name,
                                         type: expr.type),
                loc: property.startLoc,
                highlights: [ expr.name.range ])
          continue
        }
        propertyNames.insert(property.name.name)
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

  override func visitFuncDecl(_ decl: FuncDecl) {
    super.visitFuncDecl(decl)
    if decl.has(attribute: .foreign) {
      if !(decl is InitializerDecl) && decl.body != nil {
        error(SemaError.foreignFunctionWithBody(name: decl.name),
              loc: decl.name.range?.start,
              highlights: [
                decl.name.range
          ])
        return
      }
    } else {
      if !decl.has(attribute: .implicit) && decl.body == nil {
        if decl is ProtocolMethodDecl {
          /* don't diagnose functions without bodies for protocol methods */
        } else {
          error(SemaError.nonForeignFunctionWithoutBody(name: decl.name),
                loc: decl.name.range?.start,
                highlights: [
                  decl.name.range
                ])
          return
        }
      }
      if decl.hasVarArgs {
        error(SemaError.varArgsInNonForeignDecl,
              loc: decl.startLoc)
        return
      }
    }
    let returnType = decl.returnType.type!
    if !context.isValidType(returnType) {
      error(SemaError.unknownType(type: returnType),
            loc: decl.returnType.startLoc,
            highlights: [
              decl.returnType.sourceRange
        ])
      return
    }
    if let body = decl.body,
        !body.hasReturn,
        returnType != .void,
        !decl.has(attribute: .implicit),
        !(decl is InitializerDecl) {
      error(SemaError.notAllPathsReturn(type: decl.returnType.type!),
            loc: decl.sourceRange?.start,
            highlights: [
              decl.name.range,
              decl.returnType.sourceRange
        ])
      return
    }
    if let destr = decl as? DeinitializerDecl,
       let typeDecl = context.decl(for: destr.parentType, canonicalized: true),
       !typeDecl.isIndirect {
     error(SemaError.deinitOnStruct(name: typeDecl.name))
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
    if let rhs = decl.rhs { context.propagateContextualType(decl.type, to: rhs) }
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
    if let varExpr = expr.value?.semanticsProvidingExpr as? VarExpr {
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
    if
      case .custom = canTy,
      let typeDecl = context.decl(for: canTy),
      typeDecl.isIndirect {
      decl.mutable = true
    }
    varBindings[decl.name.name] = decl
  }
  
  func haveEqualSignatures(_ decl: FuncDecl, _ other: FuncDecl) -> Bool {
    guard decl.args.count == other.args.count else { return false }
    guard decl.hasVarArgs == other.hasVarArgs else { return false }
    for (declArg, otherArg) in zip(decl.args, other.args) {
      if declArg.isImplicitSelf && otherArg.isImplicitSelf { continue }
      guard declArg.externalName == otherArg.externalName else { return false }
      guard matches(declArg.type, otherArg.type) else { return false }
    }
    return true
  }
  
  override func visitPropertyRefExpr(_ expr: PropertyRefExpr) {
    _ = visitPropertyRefExpr(expr, callArgs: nil)
  }
  
  /// - returns: true if the resulting decl is a field of function type,
  ///            instead of a method
  func visitPropertyRefExpr(_ expr: PropertyRefExpr, callArgs: [Argument]?) -> FieldKind {
    super.visitPropertyRefExpr(expr)
    guard let type = expr.lhs.type else {
      // An error will already have been thrown from here
      return .property
    }
    if case .pointer(_) = context.canonicalType(type) {
      error(SemaError.pointerPropertyAccess(lhs: type, property: expr.name),
            loc: expr.dotLoc,
            highlights: [
              expr.name.range
        ])
      return .property
    }
    if case .function = type {
      error(SemaError.fieldOfFunctionType(type: type),
            loc: expr.dotLoc,
            highlights: [
              expr.sourceRange
        ])
      return .property
    }
    if case .tuple = type {
      error(SemaError.tuplePropertyAccess(lhs: type, property: expr.name),
            loc: expr.dotLoc,
            highlights: [
              expr.name.range
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
    if let varExpr = expr.lhs as? VarExpr, varExpr.isTypeVar, let varTypeDecl = varExpr.decl as? TypeDecl {
      expr.typeDecl = varTypeDecl
      expr.type = varTypeDecl.type
      return .staticMethod
    }
    let candidateMethods = typeDecl.methods(named: expr.name.name)
    if let callArgs = callArgs,
       let index = typeDecl.indexOfProperty(named: expr.name) {
      let property = typeDecl.properties[index]
      if case .function(let args, _) = property.type {
        let types = callArgs.flatMap { $0.val.type }
        if types.count == callArgs.count && args == types {
          expr.decl = property
          expr.type = property.type
          return .property
        }
      }
    }
    if let decl = typeDecl.property(named: expr.name.name) {
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
      error(SemaError.unknownProperty(typeDecl: typeDecl, expr: expr),
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
      expr.type = context.stdlib?.mirror.type ?? DataType(name: expr.name.name)
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
  
  func foreignDecl(args: [DataType], ret: DataType) -> FuncDecl {
    let assigns: [ParamDecl] = args.map {
      let name = Identifier(name: "__implicit__")
      return ParamDecl(name: "", type: TypeRefExpr(type: $0, name: name))
    }
    let retName = Identifier(name: "\(ret)")
    let typeRef = TypeRefExpr(type: ret, name: retName)
    return FuncDecl(name: "",
                    returnType: typeRef,
                    args: assigns,
                    body: nil,
                    modifiers: [.foreign, .implicit])
  }
  
  override func visitTypeDecl(_ decl: TypeDecl) {
    super.visitTypeDecl(decl)
    diagnoseConformances(decl)
  }
  
  override func visitProtocolDecl(_ decl: ProtocolDecl) {
    super.visitProtocolDecl(decl)
    for conformance in decl.conformances {
      diagnoseConformanceIfMissing(conformance)
    }
  }
  
  @discardableResult
  func diagnoseConformanceIfMissing(_ conformance: TypeRefExpr) -> ProtocolDecl? {
    guard let proto = context.protocol(named: conformance.name) else {
      error(SemaError.unknownProtocol(name: conformance.name),
            loc: conformance.startLoc,
            highlights: [
              conformance.sourceRange
            ])
      return nil
    }
    return proto
  }
  
  func diagnoseConformances(_ decl: TypeDecl) {
    for conformance in decl.conformances {
      guard let proto = diagnoseConformanceIfMissing(conformance) else { continue }
      guard let methods = context.requiredMethods(for: proto) else { continue }
      var missing = [FuncDecl]()
      for method in methods {
        var impl: MethodDecl?
        for candidate in decl.methods(named: method.name.name) {
          if haveEqualSignatures(method, candidate) {
            impl = candidate
            break
          }
        }
        if let impl = impl {
          impl.satisfiedProtocols.insert(proto)
        } else {
          missing.append(method)
        }
      }
      if !missing.isEmpty {
        error(SemaError.typeDoesNotConform(decl.type, protocol: proto.type),
              loc: decl.startLoc,
              highlights: [
                conformance.name.range
              ])
      }
      for decl in missing {
        note(SemaError.missingImplementation(decl),
             loc: decl.startLoc)
      }
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
    
    switch expr.lhs.semanticsProvidingExpr {
    case let lhs as PropertyRefExpr:
      name = lhs.name
      let propertyKind = visitPropertyRefExpr(lhs, callArgs: expr.args)
      guard let typeDecl = lhs.typeDecl else {
        return
      }
      switch propertyKind {
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
    
    if let lhs = expr.lhs as? PropertyRefExpr {
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

  override func visitCoercionExpr(_ expr: CoercionExpr) {
    super.visitCoercionExpr(expr)

    guard var lhsType = expr.lhs.type else { return }
    guard let rhsType = expr.rhs.type else { return }

    if context.propagateContextualType(rhsType, to: expr.lhs) {
      lhsType = rhsType
    }

    guard context.isValidType(rhsType) else {
      error(SemaError.unknownType(type: rhsType),
            loc: expr.rhs.startLoc,
            highlights: [expr.rhs.sourceRange])
      return
    }
    if !context.canCoerce(lhsType, to: rhsType) {
      error(SemaError.cannotCoerce(type: lhsType,
                                   toType: rhsType),
            loc: expr.asRange?.start,
            highlights: [
              expr.lhs.sourceRange,
              expr.asRange,
              expr.rhs.sourceRange
            ])
      return
    }
    expr.type = rhsType
    return
  }

  override func visitIsExpr(_ expr: IsExpr)  {
    super.visitIsExpr(expr)
    guard let lhsType = expr.lhs.type else { return }
    guard let rhsType = expr.rhs.type else { return }

    guard context.isValidType(rhsType) else {
      error(SemaError.unknownType(type: rhsType),
            loc: expr.rhs.startLoc,
            highlights: [expr.rhs.sourceRange])
      return
    }

    guard case .any? = expr.lhs.type else {
      let matched = !matches(lhsType, rhsType)
      error(SemaError.isCheckAlways(fails: matched),
            loc: expr.isRange?.start,
            highlights: [
              expr.lhs.sourceRange,
              expr.isRange,
              expr.rhs.sourceRange
        ])
      return
    }
    expr.type = .bool
    return
  }

  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
    super.visitInfixOperatorExpr(expr)
    guard var lhsType = expr.lhs.type else { return }
    guard var rhsType = expr.rhs.type else { return }
    
    if context.propagateContextualType(rhsType, to: expr.lhs) {
      lhsType = rhsType
    } else if context.propagateContextualType(lhsType, to: expr.rhs) {
      rhsType = lhsType
    }

    let canRhs = context.canonicalType(rhsType)
    
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
  
  override func visitStringExpr(_ expr: StringExpr) {
    super.visitStringExpr(expr)
    if context.isValidType(.string) {
      expr.type = .string
    } else {
      expr.type = .pointer(type: .int8)
    }
  }
  
  override func visitStringInterpolationExpr(_ expr: StringInterpolationExpr) {
    super.visitStringInterpolationExpr(expr)
    if context.isValidType(.string) {
      expr.type = .string
    } else {
      error(SemaError.stdlibRequired("use string interpolation"),
            loc: expr.startLoc,
            highlights: [expr.sourceRange])
    }
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
    visitStringExpr(expr)
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
