//
//  ASTContext.swift
//  Trill
//

import Foundation

enum ASTError: Error, CustomStringConvertible {
  case duplicateVar(name: Identifier)
  case duplicateType(name: Identifier)
  case duplicateFunction(name: Identifier)
  case duplicateProtocol(name: Identifier)
  case duplicateOperatorOverload(decl: OperatorDecl)
  case circularAlias(name: Identifier)
  case invalidMain(got: DataType)
  case duplicateMain
  var description: String {
    switch self {
    case .duplicateType(let name):
      return "invalid redeclaration of type '\(name)'"
    case .duplicateVar(let name):
      return "invalid redeclaration of variable '\(name)'"
    case .duplicateFunction(let name):
      return "invalid redeclaration of function '\(name)'"
    case .duplicateProtocol(let name):
      return "invalid redeclaration of protocol '\(name)'"
    case .duplicateOperatorOverload(let decl):
      return "invalid redeclaration of overload for '\(decl.op)' with arguments '\(decl.formattedParameterList)'"
    case .circularAlias(let name):
      return "declaration of '\(name)' is circular"
    case .invalidMain(let type):
      return "invalid main (must be (Int, **Int8) -> Void or () -> Void, got \(type))"
    case .duplicateMain:
      return "only one main function is allowed"
    }
  }
}

enum Mutability {
  case immutable(culprit: Identifier?)
  case mutable
}

enum TypeRank: Int {
  case equal = 999
  case any = 1
}

struct CandidateResult<DeclTy: Decl> {
  let candidate: DeclTy
  let rank: Int
}

struct MainFuncFlags: OptionSet {
  var rawValue: Int8
  static let args = MainFuncFlags(rawValue: 1 << 0)
  static let exitCode = MainFuncFlags(rawValue: 1 << 1)
}

public class ASTContext {
  
  let diag: DiagnosticEngine
  
  init(diagnosticEngine: DiagnosticEngine) {
    self.diag = diagnosticEngine
  }
    
  func error(_ err: Error, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    diag.error(err, loc: loc, highlights: highlights)
  }
  
  func warning(_ warn: Error, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    diag.warning("\(warn)", loc: loc, highlights: highlights)
  }
  
  func note(_ note: Error, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    diag.note("\(note)", loc: loc, highlights: highlights)
  }
  
  func warning(_ msg: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    diag.warning(msg, loc: loc, highlights: highlights)
  }
  
  func note(_ msg: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    diag.note(msg, loc: loc, highlights: highlights)
  }
  
  var sourceFiles = [SourceFile]()
  var functions = [FuncDecl]()
  var operators = [OperatorDecl]()
  var types = [TypeDecl]()
  var extensions = [ExtensionDecl]()
  var protocols = [ProtocolDecl]()
  var diagnostics = [PoundDiagnosticStmt]()
  var globals = [VarAssignDecl]()
  var typeAliases = [TypeAliasDecl]()
  
  private var funcDeclMap = [String: [FuncDecl]]()
  private var protocolDeclMap = [String: ProtocolDecl]()
  private var typeDeclMap: [DataType: TypeDecl] = [
    .int8: TypeDecl(name: "Int8",  properties: []),
    .int16: TypeDecl(name: "Int16",  properties: []),
    .int32: TypeDecl(name: "Int32",  properties: []),
    .int64: TypeDecl(name: "Int",  properties: []),
    .uint8: TypeDecl(name: "UInt8",  properties: []),
    .uint16: TypeDecl(name: "UInt16",  properties: []),
    .uint32: TypeDecl(name: "UInt32",  properties: []),
    .uint64: TypeDecl(name: "UInt",  properties: []),
    .double: TypeDecl(name: "Double",  properties: []),
    .float: TypeDecl(name: "Float",  properties: []),
    .float80: TypeDecl(name: "Float80",  properties: []),
    .bool: TypeDecl(name: "Bool", properties: []),
    .void: TypeDecl(name: "Void", properties: [])
  ]
  
  private static let numericTypes: [DataType] = [.int8, .int16, .int32, .int64,
                                                 .uint8, .uint16, .uint32, .uint64,
                                                 .float, .double, .float80]
  private var operatorMap: [BuiltinOperator: [OperatorDecl]] = [
    .plus: makeHomogenousOps(.plus, ASTContext.numericTypes),
    .minus: makeHomogenousOps(.minus, ASTContext.numericTypes),
    .star: makeHomogenousOps(.star, ASTContext.numericTypes),
    .divide: makeHomogenousOps(.divide, ASTContext.numericTypes),
    .mod: makeHomogenousOps(.mod, ASTContext.numericTypes),
    .ampersand: makeHomogenousOps(.ampersand, ASTContext.numericTypes),
    .bitwiseOr: makeHomogenousOps(.bitwiseOr, ASTContext.numericTypes),
    .bitwiseNot: makeHomogenousOps(.bitwiseNot, ASTContext.numericTypes),
    .leftShift: makeHomogenousOps(.leftShift, ASTContext.numericTypes),
    .rightShift: makeHomogenousOps(.rightShift, ASTContext.numericTypes),
    .xor: makeHomogenousOps(.xor, ASTContext.numericTypes + [.bool]),
    .equalTo: makeBoolOps(.equalTo, ASTContext.numericTypes + [.bool]),
    .notEqualTo: makeBoolOps(.notEqualTo, ASTContext.numericTypes + [.bool]),
    .lessThan: makeBoolOps(.lessThan, ASTContext.numericTypes),
    .lessThanOrEqual: makeBoolOps(.lessThanOrEqual, ASTContext.numericTypes),
    .greaterThan: makeBoolOps(.greaterThan, ASTContext.numericTypes),
    .greaterThanOrEqual: makeBoolOps(.greaterThanOrEqual, ASTContext.numericTypes),
    .and: makeBoolOps(.and, [.bool]),
    .or: makeBoolOps(.or, [.bool]),
    .not: makeBoolOps(.not, [.bool]),
  ]
  private var globalDeclMap = [String: VarAssignDecl]()
  private var typeAliasMap = [String: TypeAliasDecl]()
  private var sourceFileMap = [String: SourceFile]()
  
  private(set) var mainFunction: FuncDecl? = nil
  private(set) var mainFlags: MainFuncFlags? = nil
  
  func setMain(_ main: FuncDecl) {
    guard mainFunction == nil else {
      error(ASTError.duplicateMain,
            loc: main.startLoc,
            highlights: [
              main.name.range
        ])
      return
    }
    guard case .function(let args, let ret) = main.type else { fatalError() }
    var flags = MainFuncFlags()
    if ret == .int64 {
      _ = flags.insert(.exitCode)
    }
    if args.count == 2 {
      if case (.int, .pointer(type: .pointer(type: .int(width: 8, signed: true)))) = (args[0], args[1]) {
        _ = flags.insert(.args)
      }
    }
    mainFlags = flags
    let hasInvalidArgs = !args.isEmpty && !flags.contains(.args)
    let hasInvalidRet = ret != .void && !flags.contains(.exitCode)
    if hasInvalidRet || hasInvalidArgs {
      error(ASTError.invalidMain(got: main.type),
            loc: main.startLoc,
            highlights: [
              main.name.range
        ])
      return
    }
    mainFunction = main
  }
  
  func add(_ operatorDecl: OperatorDecl) {
    operators.append(operatorDecl)
    
    let decls = operators(for: operatorDecl.op)
    let declNames = decls.map { Mangler.mangle($0) }
    if declNames.contains(Mangler.mangle(operatorDecl)) {
      error(ASTError.duplicateOperatorOverload(decl: operatorDecl),
            loc: operatorDecl.name.range?.start,
            highlights: [ operatorDecl.name.range ])
      return
    }
    
    var existing = operatorMap[operatorDecl.op] ?? []
    existing.append(operatorDecl)
    operatorMap[operatorDecl.op] = existing
  }

  func add(_ sourceFile: SourceFile) {
    var sourceFile = sourceFile
    sourceFile.context = self
    sourceFiles.append(sourceFile)
    sourceFileMap[sourceFile.path.filename] = sourceFile
  }
  
  func infixOperatorCandidate(_ op: BuiltinOperator, lhs: Expr, rhs: Expr) -> OperatorDecl? {
    let canLhs = canonicalType(lhs.type!)
    if rhs is NilExpr && canBeNil(canLhs) && [.equalTo, .notEqualTo].contains(op) {
      return OperatorDecl(op: op,
                          args: [
                            ParamDecl(name: "", type: lhs.type!.ref()),
                            ParamDecl(name: "", type: lhs.type!.ref())
                          ],
                          genericParams: [],
                          returnType: DataType.bool.ref(),
                          body: nil,
                          modifiers: [.implicit])
    }
    
    var bestCandidate: CandidateResult<OperatorDecl>?
    
    let canRhs = canonicalType(rhs.type!)
    let decls = operators(for: op)
    
    for decl in decls {
      let (lhs, rhs) = (decl.args[0], decl.args[1])
      if let lhsRank = matchRank(lhs.type, canLhs),
         let rhsRank = matchRank(rhs.type, canRhs) {
        let totalRank = lhsRank.rawValue + rhsRank.rawValue
        if bestCandidate == nil || bestCandidate!.rank <= totalRank {
          bestCandidate = CandidateResult(candidate: decl, rank: totalRank)
        }
      }
    }
    return bestCandidate?.candidate
  }
  
  
  func candidate(forArgs args: [Argument], candidates: [FuncDecl]) -> FuncDecl? {
    var bestCandidate: CandidateResult<FuncDecl>?
    search: for candidate in candidates {
      var candArgs = candidate.args
      if let first = candArgs.first, first.isImplicitSelf {
        candArgs.remove(at: 0)
      }
      if !candidate.hasVarArgs && candArgs.count != args.count { continue }
      var totalRank = 0
      for (candArg, exprArg) in zip(candArgs, args) {
        if let externalName = candArg.externalName {
          if exprArg.label != externalName {
            continue search
          }
        } else if exprArg.label != nil {
          continue search
        }
        guard let valSugaredType = exprArg.val.type else {
          continue search
        }
        var valType = canonicalType(valSugaredType)
        let candType = canonicalType(candArg.type)
        // automatically coerce number literals.
        if propagateContextualType(candType, to: exprArg.val) {
          valType = candType
        }
        
        // Even though they 'match', we don't want to demote an any to a specific
        // type without being asked.
        if candType != .any && valType == .any {
          continue search
        }
        guard let rank = matchRank(candType, valType) else {
          continue search
        }
        totalRank += rank.rawValue
      }
      let newCand = CandidateResult(candidate: candidate, rank: totalRank)
      
      if bestCandidate == nil || bestCandidate!.rank <= totalRank {
        bestCandidate = newCand
      }
    }
    return bestCandidate?.candidate
  }
  
  /// - Returns: Whether the expression's type was changed
  @discardableResult
  func propagateContextualType(_ contextualType: DataType, to expr: Expr) -> Bool {
    let canTy = canonicalType(contextualType)
    switch expr {
    case let expr as NumExpr:
      if case .int = canTy {
        expr.type = contextualType
        return true
      }
      if case .floating = canTy {
        expr.type = contextualType
        return true
      }
    case let expr as ArrayExpr:
      guard case .array(_, let length)? = expr.type else { return false }
      guard case .array(let ctx, _) = contextualType else {
        return false
      }
      var changed = false
      for value in expr.values {
        if propagateContextualType(ctx, to: value) {
          changed = true
        }
      }
      expr.type = .array(field: ctx, length: length)
      return changed
    case let expr as InfixOperatorExpr:
      if expr.lhs is NumExpr,
        expr.rhs is NumExpr {
        var changed = propagateContextualType(contextualType, to: expr.lhs)
        changed = changed || propagateContextualType(contextualType, to: expr.rhs)
        return changed
      }
    case let expr as NilExpr where canBeNil(canTy):
      expr.type = contextualType
      return true
    case let expr as TupleExpr:
      guard
        case .tuple(let contextualFields) = canTy,
        case .tuple(let fields)? = expr.type,
        contextualFields.count == fields.count else { return false }
      var changed = false
      for (ctxField, value) in zip(contextualFields, expr.values) {
        if propagateContextualType(ctxField, to: value) {
          changed = true
        }
      }
      if changed {
        expr.type = contextualType
      }
      return changed
    case let expr as TernaryExpr:
      if case .any = canTy {
        expr.type = contextualType
        return true
      }
    default:
      break
    }
    return false
  }
  
  func add(_ funcDecl: FuncDecl) {
    functions.append(funcDecl)
    
    if funcDecl.name == "main" {
      setMain(funcDecl)
    }
    
    let decls = functions(named: funcDecl.name)
    let declNames = decls.map { Mangler.mangle($0) }
    if declNames.contains(Mangler.mangle(funcDecl)) {
      error(ASTError.duplicateFunction(name: funcDecl.name),
            loc: funcDecl.name.range?.start,
            highlights: [ funcDecl.name.range ])
      return
    }
    
    var existing = funcDeclMap[funcDecl.name.name] ?? []
    existing.append(funcDecl)
    funcDeclMap[funcDecl.name.name] = existing
  }
  
  func add(_ protocolDecl: ProtocolDecl) {
    protocols.append(protocolDecl)
    
    guard protocolDeclMap[protocolDecl.name.name] == nil else {
      error(ASTError.duplicateProtocol(name: protocolDecl.name),
            loc: protocolDecl.name.range?.start,
            highlights: [
              protocolDecl.name.range
            ])
      return
    }
    protocolDeclMap[protocolDecl.name.name] = protocolDecl
  }
  
  @discardableResult
  func add(_ typeDecl: TypeDecl) -> Bool {
    guard decl(for: typeDecl.type) == nil else {
      error(ASTError.duplicateType(name: typeDecl.name),
            loc: typeDecl.startLoc,
            highlights: [ typeDecl.name.range ])
      return false
    }
    types.append(typeDecl)
    typeDeclMap[typeDecl.type] = typeDecl
    return true
  }
  
  @discardableResult
  func add(_ global: VarAssignDecl) -> Bool {
    guard globalDeclMap[global.name.name] == nil else {
      error(ASTError.duplicateVar(name: global.name),
            loc: global.startLoc,
            highlights: [
              global.sourceRange
        ])
      return false
    }
    globals.append(global)
    globalDeclMap[global.name.name] = global
    return true
  }
  
  func add(_ extensionExpr: ExtensionDecl) {
    extensions.append(extensionExpr)
  }
  
  func add(_ diagnosticExpr: PoundDiagnosticStmt) {
    diagnostics.append(diagnosticExpr)
  }
  
  @discardableResult
  func add(_ alias: TypeAliasDecl) -> Bool {
    guard typeAliasMap[alias.name.name] == nil else {
      return false
    }
    if isCircularAlias(alias.bound.type!, visited: [alias.name.name]) {
      error(ASTError.circularAlias(name: alias.name),
            loc: alias.name.range?.start,
            highlights: [
              alias.name.range
        ])
      return false
    }
    typeAliasMap[alias.name.name] = alias
    typeAliases.append(alias)
    return true
  }
  
  func merge(context: ASTContext) {
    for function in context.functions {
      add(function)
    }
    for op in context.operators {
      add(op)
    }
    for type in context.types {
      add(type)
    }
    for ext in context.extensions {
      add(ext)
    }
    for diagnostic in context.diagnostics {
      add(diagnostic)
    }
    for global in context.globals {
      add(global)
    }
    for alias in context.typeAliases {
      add(alias)
    }
    for file in context.sourceFiles {
      add(file)
    }
    for proto in context.protocols {
      add(proto)
    }
  }
  
  func protocolDecl(for type: DataType) -> ProtocolDecl? {
    return protocolDeclMap["\(type)"]
  }
    
  func decl(for type: DataType, canonicalized: Bool = true) -> TypeDecl? {
    let root = canonicalized ? canonicalType(type) : type
    return typeDeclMap[root]
  }
  
  func isIntrinsic(type: DataType) -> Bool {
    if isAlias(type: type) { return false }
    if let d =  decl(for: type, canonicalized: false) {
      return isIntrinsic(decl: d)
    }
    return true
  }
  
  func isIntrinsic(decl: Decl) -> Bool {
    return decl.has(attribute: .foreign) || decl.sourceRange == nil
  }
  
  func isAlias(type: DataType) -> Bool {
    if case .custom(let name) = type {
      return typeAliasMap[name] != nil
    }
    return false
  }
  
  func isCircularAlias(_ type: DataType, visited: Set<String>) -> Bool {
    var visited = visited
    if case .custom(let name) = type {
      if visited.contains(name) { return true }
      visited.insert(name)
      guard let bound = typeAliasMap[name]?.bound.type else { return false }
      return isCircularAlias(bound, visited: visited)
    } else if case .function(let args, let ret) = type {
      for arg in args where isCircularAlias(arg, visited: visited) {
        return true
      }
      return isCircularAlias(ret, visited: visited)
    }
    return false
  }
  
  func containsInLayout(type: DataType, typeDecl: TypeDecl, base: Bool = false) -> Bool {
    if !base && matchRank(typeDecl.type, type) != nil { return true }
    for property in typeDecl.properties {
      if case .pointer = property.type { continue }
      if let decl = decl(for: property.type),
        !decl.isIndirect,
        containsInLayout(type: type, typeDecl: decl) {
        return true
      }
    }
    return false
  }
  
  func isCircularType(_ typeDecl: TypeDecl) -> Bool {
    return containsInLayout(type: typeDecl.type, typeDecl: typeDecl, base: true)
  }
  
  func matchRank(_ type1: DataType?, _ type2: DataType?) -> TypeRank? {
    switch (type1, type2) {
    case (nil, nil): return .equal
    case (_, nil): return .equal
    case (nil, _): return .equal
    case (.tuple(let fields1)?, .tuple(let fields2)?):
        if fields1.count != fields2.count { return nil }
        for (type1, type2) in zip(fields1, fields2) {
            if matchRank(type1, type2) == nil { return nil }
        }
        return .equal
    case (let t1?, let t2?):
      let t1Can = canonicalType(t1)
      let t2Can = canonicalType(t2)
      
      if case .any = t1Can {
        return .any
      }
      if case .any = t2Can {
        return .any
      }
      
      return t1Can == t2Can ? .equal : nil
    default:
      return nil
    }
  }


  /// Returns all overloaded functions with the given name at top-level scope.
  ///
  /// - Parameter name: The function's base name.
  /// - Returns: An array of functions with that base name.
  func functions(named name: Identifier) -> [FuncDecl] {
    var results = [FuncDecl]()
    if let decls = funcDeclMap[name.name] {
      results.append(contentsOf: decls)
    }
    for intrinsic in IntrinsicFunctions.allIntrinsics where intrinsic.name == name {
      results.append(intrinsic)
    }
    return results
  }


  /// Finds all overloaded operator declarations for a given operator.
  ///
  /// - Parameter op: The operator you're looking for.
  /// - Returns: All OperatorDecls overloading that operator.
  func operators(for op: BuiltinOperator) -> [OperatorDecl] {
    return operatorMap[op] ?? []
  }


  /// Finds the global variable with a given name
  ///
  /// - Parameter name: The global's name
  /// - Returns: A VarAssignDecl for that global, if it exists.
  func global(named name: Identifier) -> VarAssignDecl? {
    return globalDeclMap[name.name]
  }
  
  func global(named name: String) -> VarAssignDecl? {
    return globalDeclMap[name]
  }

  func sourceFile(named name: String) -> SourceFile? {
    return sourceFileMap[name]
  }
  
  func `protocol`(named name: Identifier) -> ProtocolDecl? {
    return protocolDeclMap[name.name]
  }

  /// Traverses the protocol hierarchy and adds all methods required to satisfy
  /// this protocol and all its parent requirements.
  ///
  /// - Parameters:
  ///   - protocolDecl: The protocol you're inspecting
  ///   - visited: A set of mangled names we've seen so far.
  /// - Returns: An array of MethodDecls that are required for a type to
  ///            conform to a protocol.
  func requiredMethods(for protocolDecl: ProtocolDecl, visited: Set<String> = Set()) -> [MethodDecl]? {
    var currentVisited = visited
    var methods = [MethodDecl]()
    for method in protocolDecl.methods {
      let mangled = Mangler.mangle(method)
      if currentVisited.contains(mangled) { continue }
      currentVisited.insert(mangled)
      methods.append(method)
    }
    for conformance in protocolDecl.conformances {
      guard let proto = self.protocol(named: conformance.name) else {
        // We will already have popped a diagnostic for this.
        return nil
      }
      guard let required = requiredMethods(for: proto, visited: currentVisited) else {
        return nil
      }
      methods.append(contentsOf: required)
    }
    return methods
  }

  func mutability(of expr: Expr) -> Mutability {
    switch expr {
    case let expr as VarExpr:
      return mutability(of: expr)
    case let expr as PropertyRefExpr:
      return mutability(of: expr)
    case let expr as SubscriptExpr:
      return mutability(of: expr.lhs)
    case let expr as ParenExpr:
      return mutability(of: expr.value)
    case let expr as PrefixOperatorExpr:
      return mutability(of: expr.rhs)
    case let expr as TupleFieldLookupExpr:
      return mutability(of: expr.lhs)
    default:
      return .immutable(culprit: nil)
    }
  }
  
  func mutablity(of expr: PrefixOperatorExpr) -> Mutability {
    switch expr.op {
    case .star:
      return mutability(of: expr.rhs)
    default:
      return .immutable(culprit: nil)
    }
  }
  
  func mutability(of expr: VarExpr) -> Mutability {
    guard let decl = expr.decl else { fatalError("no decl in mutability check") }
    switch decl {
    case let decl as VarAssignDecl:
      return decl.mutable ? .mutable : .immutable(culprit: expr.name)
    case let decl as FuncDecl:
      return decl.has(attribute: .mutating) ? .mutable : .immutable(culprit: expr.name)
    default:
      return .immutable(culprit: nil)
    }
  }
  
  func mutability(of expr: PropertyRefExpr) -> Mutability {
    guard let decl = expr.decl else { fatalError("no decl in mutability check") }
    let lhsMutability = mutability(of: expr.lhs)
    guard case .mutable = lhsMutability else {
      return lhsMutability
    }
    switch decl {
    case let decl as VarAssignDecl:
      return decl.mutable ? .mutable : .immutable(culprit: expr.name)
    case let decl as FuncDecl:
      return decl.has(attribute: .mutating) ? .mutable : .immutable(culprit: expr.name)
    default:
      return .immutable(culprit: nil)
    }
  }
  
  func isIndirect(_ type: DataType) -> Bool {
    guard let decl = decl(for: type) else { return false }
    return decl.isIndirect
  }
  
  func canBeNil(_ type: DataType) -> Bool {
    let can = canonicalType(type)
    if case .pointer = can { return true }
    if isIndirect(can) { return true }
    return false
  }
  
  func canonicalType(_ type: DataType) -> DataType {
    if case .custom(let name) = type {
      if let alias = typeAliasMap[name] {
        return canonicalType(alias.bound.type!)
      }
    }
    if case .function(let args, let returnType) = type {
      var newArgs = [DataType]()
      for argTy in args {
        newArgs.append(canonicalType(argTy))
      }
      return .function(args: newArgs, returnType: canonicalType(returnType))
    }
    if case .pointer(let subtype) = type {
      return .pointer(type: canonicalType(subtype))
    }
    return type
  }
  
  func isGlobalConstant(_ expr: Expr) -> Bool {
    if expr is ConstantExpr { return true }
    if let expr = expr as? VarExpr,
       let assign = expr.decl as? VarAssignDecl,
       case .global = assign.kind {
        return !assign.mutable
    }
    return false
  }
  
  func isValidType(_ type: DataType) -> Bool {
    switch type {
    case .pointer(let subtype):
      return isValidType(subtype)
    case .custom:
      let alias = isAlias(type: type)
      let can = alias ? canonicalType(type) : type
      if decl(for: can) != nil {
        return true
      }
      if protocolDecl(for: can) != nil {
        return true
      }
      return alias ? isValidType(can) : false
    case .function(let args, let returnType):
      for arg in args where !isValidType(arg) {
        return false
      }
      return isValidType(returnType)
    default:
      return true
    }
  }
  
  func canCoerce(_ type: DataType, to other: DataType) -> Bool {
    // You should be able to cast between an indirect type and a pointer.
    if isIndirect(other), case .pointer = type {
      return true
    }
    if isIndirect(type), case .pointer = other {
      return true
    }
    if case .any = other {
        return true
    }
    if case .any = type {
        return true
    }
    return type.canCoerceTo(other)
  }
  
  func implicitDecl(args: [DataType], ret: DataType) -> FuncDecl {
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
                    modifiers: [.implicit],
                    isPlaceholder: true)
  }
}

fileprivate func makeHomogenousOps(_ op: BuiltinOperator, _ types: [DataType]) -> [OperatorDecl] {
  return types.map { type in OperatorDecl(op, type, type, type) }
}
fileprivate func makeBoolOps(_ op: BuiltinOperator, _ types: [DataType]) -> [OperatorDecl] {
  return types.map { type in OperatorDecl(op, type, type, .bool) }
}

extension OperatorDecl {
    convenience init(_ op: BuiltinOperator,
                     _ lhsType: DataType,
                     _ rhsType: DataType,
                     _ returnType: DataType,
                     modifiers: [DeclModifier] = [.implicit]) {
        self.init(op: op,
                  args: [
                    ParamDecl(name: "lhs", type: lhsType.ref()),
                    ParamDecl(name: "rhs", type: rhsType.ref()),
                  ],
                  genericParams: [],
                  returnType: returnType.ref(),
                  body: nil,
                  modifiers: modifiers)
    }
}
  
