///
/// Sema.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import Foundation

enum FieldKind {
  case method, staticMethod, property
}

public class Sema: ASTTransformer, Pass {
  var varBindings = [String: VarAssignDecl]()
  var varBindings = [Identifier: VarAssignDecl]()
  let csGen: ConstraintGenerator
  var env: ConstraintEnvironment

  required init(context: ASTContext) {
    self.env = ConstraintEnvironment()
    self.csGen = ConstraintGenerator(context: context)
    super.init(context: context)
  }
  
  public var title: String {
    return "Semantic Analysis"
  }
  
  public override func run(in context: ASTContext) {
    registerTopLevelDecls(in: context)
    super.run(in: context)
  }

  func bind(_ name: Identifier, to decl: VarAssignDecl) {
    varBindings[name] = decl
    env[name] = decl.type
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
    for decl in context.types {
      if decl.isIndirect {
        for op in [BuiltinOperator.equalTo, .notEqualTo] {
          context.add(OperatorDecl(op, decl.type, decl.type,
                                   .bool, modifiers: [.implicit]))
        }
      }
      withScope(CompoundStmt(stmts: [])) {
        var propertyNames = Set<String>()
        for property in decl.properties {
          property.kind = .property(decl)
          if propertyNames.contains(property.name.name) {
            error(SemaError.duplicateField(name: property.name,
                                           type: decl.type),
                  loc: property.startLoc,
                  highlights: [ decl.name.range ])
            continue
          }
          propertyNames.insert(property.name.name)
        }
        var methodNames = Set<String>()
        for method in decl.methods + decl.staticMethods {
          let mangled = Mangler.mangle(method)
          if methodNames.contains(mangled) {
            error(SemaError.duplicateMethod(name: method.name,
                                            type: decl.type),
                  loc: method.startLoc,
                  highlights: [ decl.name.range ])
            continue
          }
          methodNames.insert(mangled)
        }
        if context.isCircularType(decl) {
          error(SemaError.referenceSelfInProp(name: decl.name),
                loc: decl.startLoc,
                highlights: [
                  decl.name.range
                ])
        }
      }
    }
  }

  public override func visitFuncDecl(_ decl: FuncDecl) {
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
    let returnType = decl.returnType.type
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
      error(SemaError.notAllPathsReturn(type: decl.returnType.type),
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
  
  public override func withScope(_ e: CompoundStmt, _ f: () -> Void) {
    let oldVarBindings = varBindings
    let oldEnv = env
    super.withScope(e, f)
    env = oldEnv
    varBindings = oldVarBindings
  }
  
  public override func visitVarAssignDecl(_ decl: VarAssignDecl) -> Result {
    super.visitVarAssignDecl(decl)

    if let rhs = decl.rhs, decl.has(attribute: .foreign) {
      error(SemaError.foreignVarWithRHS(name: decl.name),
            loc: decl.startLoc,
            highlights: [ rhs.sourceRange ])
      return
    }
    guard !decl.has(attribute: .foreign) else { return }

    if let type = solve(decl) {
      decl.type = type
      TypePropagator(context: context).visitVarAssignDecl(decl)
    } else {
      decl.type = .error
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
      bind(decl.name, to: decl)
    default: break
    }
    
    if let rhs = decl.rhs {
      let canRhs = context.canonicalType(rhs.type)
      if case .void = canRhs {
        error(SemaError.incompleteTypeAccess(type: canRhs,
                                             operation: "assign value from"),
              loc: rhs.startLoc,
              highlights: [
                rhs.sourceRange
          ])
        return
      }
    }
  }
  
  public override func visitParenExpr(_ expr: ParenExpr) {
    super.visitParenExpr(expr)
    expr.type = expr.value.type
  }
  
  public override func visitSizeofExpr(_ expr: SizeofExpr) -> Result {
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
  
  public override func visitParamDecl(_ decl: ParamDecl) -> Result {
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
    bind(decl.name, to: decl)
  }
  
  public override func visitPropertyRefExpr(_ expr: PropertyRefExpr) {
    _ = visitPropertyRefExpr(expr, call: nil)
  }
  
  /// - returns: true if the resulting decl is a field of function type,
  ///            instead of a method
  func visitPropertyRefExpr(_ expr: PropertyRefExpr, call: FuncCallExpr?) -> FieldKind {
    super.visitPropertyRefExpr(expr)
    let type = expr.lhs.type
    guard type != .error else {
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
      error(SemaError.unknownType(type: type.elementType),
            loc: expr.startLoc,
            highlights: [
              expr.sourceRange
        ])
      return .property
    }
    expr.typeDecl = typeDecl
    if let varExpr = expr.lhs as? VarExpr, varExpr.isTypeVar,
       let varTypeDecl = varExpr.decl as? TypeDecl {
      expr.typeDecl = varTypeDecl
      expr.type = varTypeDecl.type
      return .staticMethod
    }
    let candidateMethods = typeDecl.methods(named: expr.name.name)
    if let call = call,
       let index = typeDecl.indexOfProperty(named: expr.name) {
      let property = typeDecl.properties[index]
      if case .function(let args, _, _) = property.type {
        let types = call.args.flatMap { $0.val.type }
        if types.count == call.args.count && args == types {
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
      if let call = call {
        let resolver = OverloadResolver(context: context,
                                        environment: env)
        let solution = resolver.resolve(call, candidates: candidateMethods)
        guard case .resolved(let funcDecl) = solution else {
          diagnoseOverloadFailure(name: expr.name, args: call.args,
                                  resolution: solution,
                                  loc: expr.startLoc, highlights: [
                                    expr.name.range
          ])
          return .method
        }
        expr.decl = funcDecl
        let types = funcDecl.args.map { $0.type }
        expr.type = .function(args: types,
                              returnType: funcDecl.returnType.type,
                              hasVarArgs: funcDecl.hasVarArgs)
        TypePropagator(context: context).visitFuncCallExpr(call)
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

  func diagnoseOverloadFailure<DeclType: FuncDecl>(
    name: Identifier, args: [Argument],
    resolution: OverloadResolution<DeclType>, loc: SourceLocation? = nil,
    highlights: [SourceRange?] = []) {
    switch resolution {
    case .resolved:
      return
    case .noCandidates:
      error(SemaError.unknownFunction(name: name),
            loc: loc, highlights: highlights)
    case .ambiguity(let decls):
      error(SemaError.ambiguousReference(name: name),
            loc: loc, highlights: highlights)
      addNotesForRejections(decls)
    case .noMatchingCandidates(let decls):
      error(SemaError.noViableOverload(name: name, args: args),
            loc: loc, highlights: highlights)
      addNotesForRejections(decls)
    }
  }

  func addNotesForRejections<DeclType: FuncDecl>(_ rejections: [OverloadRejection<DeclType>]) {
    // FIXME: Be more intelligent when generating errors and
    //        include the reasons passed in.
    note(SemaError.candidates(rejections.map { $0.candidate }))
  }
  
  public override func visitArrayExpr(_ expr: ArrayExpr) {
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
      let type = value.type
      guard type != .error else { return }
      guard matches(type, first) else {
        error(SemaError.nonMatchingArrayType(first, type),
              loc: value.startLoc,
              highlights: [
                value.sourceRange
              ])
        return
      }
    }
    expr.type = .array(first, length: expr.values.count)
  }
  
  public override func visitTupleExpr(_ expr: TupleExpr) {
    super.visitTupleExpr(expr)
    var types = [DataType]()
    for expr in expr.values {
      types.append(expr.type)
    }
    expr.type = .tuple(types)
  }
  
  public override func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) -> Result {
    super.visitTupleFieldLookupExpr(expr)
    let lhsCanTy = context.canonicalType(expr.lhs.type)
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
  
  public override func visitSubscriptExpr(_ expr: SubscriptExpr) -> Result {
    super.visitSubscriptExpr(expr)
    let type = expr.lhs.type
    guard type != .error else {
      return
    }
    let diagnose: () -> Void = {
      self.error(SemaError.cannotSubscript(type: type),
                 loc: expr.startLoc,
                 highlights: [ expr.lhs.sourceRange ])
    }
    let elementType: DataType
    switch type {
    case .pointer(let element), .array(let element, _):
      elementType = element
    default:
      guard let typeDecl = context.decl(for: type),
            !typeDecl.subscripts.isEmpty else {
        diagnose()
        return
      }
      let resolver = OverloadResolver(context: context,
                                      environment: env)
      let resolution = resolver.resolve(expr, candidates: typeDecl.subscripts)
      guard case .resolved(let decl) = resolution else {
        diagnoseOverloadFailure(name: "subscript",
                                args: expr.args,
                                resolution: resolution,
                                loc: expr.startLoc,
                                highlights: [
                                  expr.lhs.sourceRange
                                ])
        return
      }
      elementType = decl.returnType.type
      expr.type = elementType
      expr.decl = decl
      TypePropagator(context: context).visitSubscriptExpr(expr)
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
  
  public override func visitExtensionDecl(_ expr: ExtensionDecl) -> Result {
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
  
  public override func visitVarExpr(_ expr: VarExpr) -> Result {
    super.visitVarExpr(expr)
    if
      let fn = currentFunction,
      fn is InitializerDecl,
      expr.name == "self" {
      expr.decl = VarAssignDecl(name: "self",
                                typeRef: fn.returnType,
                                kind: .implicitSelf(fn, currentType!))
      expr.isSelf = true
      expr.type = currentType!.type
      return
    }
    let candidates = context.functions(named: expr.name)
    if let decl = varBindings[expr.name] ?? context.global(named: expr.name) {
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
  
  public override func visitContinueStmt(_ stmt: ContinueStmt) -> Result {
    if currentBreakTarget == nil {
      error(SemaError.continueNotAllowed,
            loc: stmt.startLoc,
            highlights: [ stmt.sourceRange ])
    }
  }
  
  public override func visitBreakStmt(_ stmt: BreakStmt) -> Result {
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
  
  public override func visitTypeDecl(_ decl: TypeDecl) {
    super.visitTypeDecl(decl)
    diagnoseConformances(decl)
  }
  
  public override func visitProtocolDecl(_ decl: ProtocolDecl) {
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
      let missing = context.missingMethodsForConformance(decl, to: proto)
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
  
  public override func visitTypeAliasDecl(_ decl: TypeAliasDecl) -> Result {
    let bound = decl.bound.type
    guard bound != .error else { return }
    guard context.isValidType(bound) else {
      error(SemaError.unknownType(type: bound),
            loc: decl.bound.startLoc,
            highlights: [
              decl.bound.sourceRange
        ])
      return
    }
  }
  
<<<<<<< HEAD:Sources/Sema/Sema.swift
  public override func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result {
    for arg in expr.args {
      visit(arg.val)
    }
    for arg in expr.args {
      guard arg.val.type != .error else { return }
    }
    var candidates = [FuncDecl]()
    let name: Identifier
    
    var setLHSDecl: (Decl) -> Void = {_ in }
    
    switch expr.lhs.semanticsProvidingExpr {
    case let lhs as PropertyRefExpr:
      name = lhs.name
      let propertyKind = visitPropertyRefExpr(lhs, call: expr)
      guard let typeDecl = lhs.typeDecl else {
        return
      }
      switch propertyKind {
      case .property:
        if case .function(var args, let ret, let hasVarArgs) = lhs.type {
          candidates.append(context.implicitDecl(args: args, ret: ret, hasVarArgs: hasVarArgs))
          args.insert(typeDecl.type, at: 0)
          lhs.type = .function(args: args, returnType: ret, hasVarArgs: hasVarArgs)
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
      } else if let varDecl = varBindings[lhs.name] {
        setLHSDecl = { _ in } // override the decl if this is a function variable
        lhs.decl = varDecl
        let type = context.canonicalType(varDecl.type)
        if case .function(let args, let ret, let hasVarArgs) = type {
          candidates.append(context.implicitDecl(args: args, ret: ret,
                                                 hasVarArgs: hasVarArgs))
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
      if case .function(let args, let ret, let hasVarArgs) = expr.lhs.type {
        candidates += [context.implicitDecl(args: args, ret: ret,
                                            hasVarArgs: hasVarArgs)]
      } else {
        error(SemaError.callNonFunction(type: expr.lhs.type ),
              loc: expr.lhs.startLoc,
              highlights: [
                expr.lhs.sourceRange
          ])
        return
      }
      name = "<<implicit>>"
    }
    
    guard !candidates.isEmpty else {
      error(SemaError.unknownFunction(name: name),
            loc: name.range?.start,
            highlights: [ name.range ])
      return
    }
    let resolver = OverloadResolver(context: context,
                                    environment: env)
    let resolution = resolver.resolve(expr, candidates: candidates)

    guard case .resolved(let decl) = resolution else {
      diagnoseOverloadFailure(name: name,
                              args: expr.args,
                              resolution: resolution,
                              loc: name.range?.start,
                              highlights: [name.range])
      return
    }
    setLHSDecl(decl)
    expr.decl = decl
    expr.type = decl.returnType.type
    TypePropagator(context: context).visitFuncCallExpr(expr)

    if let lhs = expr.lhs as? PropertyRefExpr {
      if case .immutable(let culprit) = context.mutability(of: lhs),
        decl.has(attribute: .mutating), decl is MethodDecl {
        error(SemaError.assignToConstant(name: culprit),
              loc: name.range?.start,
              highlights: [
                name.range
          ])
        return
      }
    }
  }

  public override func visitCompoundStmt(_ stmt: CompoundStmt) {
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
  
  public override func visitClosureExpr(_ expr: ClosureExpr) {
    super.visitClosureExpr(expr)
    var argTys = [DataType]()
    for arg in expr.args {
      argTys.append(arg.type)
    }
    expr.type = .function(args: argTys, returnType: expr.returnType!.type,
                          hasVarArgs: false)
  }
  
  public override func visitSwitchStmt(_ stmt: SwitchStmt) {
    super.visitSwitchStmt(stmt)
    let valueType = stmt.value.type
    guard valueType != .error else { return }
    for c in stmt.cases {
      guard context.isGlobalConstant(c.constant) else {
        error(SemaError.caseMustBeConstant,
              loc: c.constant.startLoc,
              highlights: [c.constant.sourceRange])
        return
      }
      let resolver = OverloadResolver(context: context,
                                      environment: env)
      let fakeInfix = InfixOperatorExpr(op: .equalTo,
                                        lhs: stmt.value,
                                        rhs: c.constant)
      let resolution = resolver.resolve(fakeInfix)
      guard case .resolved(let decl) = resolution,
               !decl.returnType.type.isPointer else {
        error(SemaError.cannotSwitch(type: valueType),
              loc: stmt.value.startLoc,
              highlights: [ stmt.value.sourceRange ])
        continue
      }
    }
  }
  
  public override func visitOperatorDecl(_ decl: OperatorDecl) {
    guard decl.args.count == 2 else {
      error(SemaError.operatorsMustHaveTwoArgs(op: decl.op),
            loc: decl.opRange?.start,
            highlights: [
              decl.opRange
            ])
      return
    }
    super.visitOperatorDecl(decl)
  }

  public override func visitCoercionExpr(_ expr: CoercionExpr) {
    visit(expr.lhs)
    visit(expr.rhs)
    let lhsPreType = expr.lhs.type
    guard lhsPreType != .error else { return }

    guard let solution = solve(expr) else {
      return
    }

    expr.type = solution

    // determine if this is a promotion or explicit conversion
    let constraint = Constraint(kind: .coercion(expr.type, lhsPreType),
                                location: #function,
                                attachedNode: expr,
                                isExplicitTypeVariable: false)

    let soln = try! ConstraintSolver(context: context)
                      .solveSingle(constraint)

    expr.kind = soln.isPunished ? .promotion : .conversion

    TypePropagator(context: context).visitCoercionExpr(expr)
  }

  public override func visitIsExpr(_ expr: IsExpr)  {
    super.visitIsExpr(expr)

    let lhsType = expr.lhs.type
    let rhsType = expr.rhs.type
    guard lhsType != .error, rhsType != .error else { return }

    guard context.isValidType(rhsType) else {
      error(SemaError.unknownType(type: rhsType),
            loc: expr.rhs.startLoc,
            highlights: [expr.rhs.sourceRange])
      return
    }

    let canTy = context.canonicalType(expr.lhs.type)

    guard canTy == .any else {
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

  override func visitAssignStmt(_ stmt: AssignStmt) {
    super.visitAssignStmt(stmt)
    if let associated = stmt.associatedOp {
      let resolver = OverloadResolver(context: context, environment: env)
      let resolution = resolver.resolve(stmt)
      let name = Identifier(name: "\(associated)")
      guard case .resolved(let decl) = resolution else {
        diagnoseOverloadFailure(name: name, args: [
          Argument(val: stmt.lhs),
          Argument(val: stmt.rhs)
        ], resolution: resolution, loc: stmt.opRange?.start, highlights: [
            stmt.opRange, stmt.lhs.sourceRange, stmt.rhs.sourceRange
        ])
        return
      }
      stmt.decl = decl
    } else {
      let canRhs = context.canonicalType(stmt.rhs.type)

      if case .void = canRhs {
        error(SemaError.incompleteTypeAccess(type: canRhs,
                                             operation: "assign value from"),
              loc: stmt.rhs.startLoc,
              highlights: [
                stmt.rhs.sourceRange
          ])
        return
      }
      if case .immutable(let name) = context.mutability(of: stmt.lhs) {
        if currentFunction == nil || !(currentFunction! is InitializerDecl) {
          error(SemaError.assignToConstant(name: name),
                loc: name?.range?.start,
                highlights: [
                  name?.range
            ])
          return
        }
      }
    }

    TypePropagator(context: context).visitAssignStmt(stmt)
  }

  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
    super.visitInfixOperatorExpr(expr)
    let lhsType = expr.lhs.type
    let rhsType = expr.rhs.type
    guard lhsType != .error, rhsType != .error else { return }
    
    let resolver = OverloadResolver(context: context,
                                    environment: env)
    let resolution = resolver.resolve(expr)
    let name = Identifier(name: "\(expr.op)")
    guard case .resolved(let decl) = resolution else {
      diagnoseOverloadFailure(name: name, args: [
        Argument(val: expr.lhs),
        Argument(val: expr.rhs)
      ], resolution: resolution, loc: expr.opRange?.start, highlights: [
        expr.opRange, expr.lhs.sourceRange, expr.rhs.sourceRange
      ])
      return
    }
    expr.decl = decl
    expr.type = decl.returnType.type
    TypePropagator(context: context).visitInfixOperatorExpr(expr)
  }

  public override func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    super.visitTernaryExpr(expr)
    expr.type = expr.trueCase.type
  }
  
  public override func visitStringExpr(_ expr: StringExpr) {
    super.visitStringExpr(expr)
    if context.isValidType(.string) {
      expr.type = .string
    } else {
      expr.type = .pointer(type: .int8)
    }
  }
  
  public override func visitStringInterpolationExpr(_ expr: StringInterpolationExpr) {
    super.visitStringInterpolationExpr(expr)
    if context.isValidType(.string) {
      expr.type = .string
    } else {
      error(SemaError.stdlibRequired("use string interpolation"),
            loc: expr.startLoc,
            highlights: [expr.sourceRange])
    }
  }
  
  public override func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) -> Result {
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
  
  public override func visitPoundDiagnosticStmt(_ stmt: PoundDiagnosticStmt) {
    if stmt.isError {
      context.diag.error(stmt.text, loc: stmt.content.startLoc, highlights: [])
    } else {
      context.diag.warning(stmt.text, loc: stmt.content.startLoc, highlights: [])
    }
  }
  
  public override func visitReturnStmt(_ stmt: ReturnStmt) {
    guard let returnType = currentClosure?.returnType!.type ?? currentFunction?.returnType.type else { return }
    super.visitReturnStmt(stmt)
    stmt.value.type = returnType
    guard let solution = solve(stmt) else {
      return
    }
    stmt.value.type = solution
    TypePropagator(context: context).visit(stmt.value)
  }
  
  public override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) {
    super.visitPrefixOperatorExpr(expr)
    guard let solution = solve(expr) else { return }
    expr.type = solution
    TypePropagator(context: context).visitPrefixOperatorExpr(expr)
    let rhsType = context.canonicalType(expr.rhs.type)
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
      guard expr.rhs.semanticsProvidingExpr is LValue else {
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

  func solve(_ node: ASTNode) -> DataType? {
    csGen.reset(with: env)
    csGen.visit(node)
    do {
      let solution = try ConstraintSolver(context: context)
                            .solveSystem(csGen.system)
      let goal = csGen.goal.substitute(solution.substitutions)
      if case .typeVariable = goal {
        return nil
      }
      if !context.isValidType(goal) {
        error(SemaError.unknownType(type: goal),
              loc: node.startLoc,
              highlights: [
                node.sourceRange
          ])
        return nil
      }
      return goal
    } catch let err as ConstraintError {
      error(err, loc: err.constraint.attachedNode?.startLoc,
            highlights: [
              err.constraint.attachedNode?.sourceRange
        ])
    } catch let err {
      error(err, loc: node.startLoc, highlights: [
        node.sourceRange
        ])
    }
    return nil
  }
}
