///
/// ASTContext.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Diagnostics
import Foundation
import Source

public enum ASTError: Error, CustomStringConvertible {
  case duplicateVar(name: Identifier)
  case duplicateType(name: Identifier)
  case duplicateFunction(name: Identifier)
  case duplicateProtocol(name: Identifier)
  case duplicateOperatorOverload(decl: OperatorDecl)
  case circularAlias(name: Identifier)
  case invalidMain(got: DataType)
  case duplicateMain
  public var description: String {
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

public enum Mutability {
  case immutable(culprit: Identifier?)
  case mutable
}

public enum TypeRank: Int {
  case equal = 999
  case any = 1
}

public struct CandidateResult<DeclTy: Decl> {
  public let candidate: DeclTy
  public let rank: Int
}

public struct MainFuncFlags: OptionSet {
  public var rawValue: Int8
  public static let args = MainFuncFlags(rawValue: 1 << 0)
  public static let exitCode = MainFuncFlags(rawValue: 1 << 1)

  public init(rawValue: Int8) {
    self.rawValue = rawValue
  }
}

public class ASTContext {

  public let diag: DiagnosticEngine

  public init(diagnosticEngine: DiagnosticEngine) {
    self.diag = diagnosticEngine
  }

  public func error(_ err: Error, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    diag.error(err, loc: loc, highlights: highlights)
  }

  public func warning(_ warn: Error, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    diag.warning("\(warn)", loc: loc, highlights: highlights)
  }

  public func note(_ note: Error, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    diag.note("\(note)", loc: loc, highlights: highlights)
  }

  public func warning(_ msg: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    diag.warning(msg, loc: loc, highlights: highlights)
  }

  public func note(_ msg: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    diag.note(msg, loc: loc, highlights: highlights)
  }

  public let sourceFileManager = SourceFileManager()

  public var sourceFiles = [SourceFile]()
  public var functions = [FuncDecl]()
  public var operators = [OperatorDecl]()
  public var types = [TypeDecl]()
  public var extensions = [ExtensionDecl]()
  public var protocols = [ProtocolDecl]()
  public var diagnostics = [PoundDiagnosticStmt]()
  public var globals = [VarAssignDecl]()
  public var typeAliases = [TypeAliasDecl]()
  public var stdlib: StdLibASTContext?

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

  private(set) public var mainFunction: FuncDecl? = nil
  private(set) public var mainFlags: MainFuncFlags? = nil

  public func setMain(_ main: FuncDecl) {
    guard mainFunction == nil else {
      error(ASTError.duplicateMain,
            loc: main.startLoc,
            highlights: [
              main.name.range
        ])
      return
    }
    guard case .function(let args, let ret, false) = main.type else { fatalError() }
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

  public func add(_ operatorDecl: OperatorDecl) {
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

  public func add(_ sourceFile: SourceFile) {
    sourceFiles.append(sourceFile)
    sourceFileMap[sourceFile.path.filename] = sourceFile
  }

  public func infixOperatorCandidate(_ op: BuiltinOperator, lhs: Expr, rhs: Expr) -> OperatorDecl? {
    let canLhs = canonicalType(lhs.type)
    if rhs is NilExpr && canBeNil(canLhs) && [.equalTo, .notEqualTo].contains(op) {
      return OperatorDecl(op: op,
                          args: [
                            ParamDecl(name: "", type: lhs.type.ref()),
                            ParamDecl(name: "", type: lhs.type.ref())
                          ],
                          genericParams: [],
                          returnType: DataType.bool.ref(),
                          body: nil,
                          modifiers: [.implicit])
    }

    var bestCandidate: CandidateResult<OperatorDecl>?

    let canRhs = canonicalType(rhs.type)
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


  public func candidate(forArgs args: [Argument], candidates: [FuncDecl]) -> FuncDecl? {
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
        let valSugaredType = exprArg.val.type
        guard valSugaredType != .error else {
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

  public func conformsToProtocol(_ decl: TypeDecl, _ proto: ProtocolDecl) -> Bool {
    return missingMethodsForConformance(decl, to: proto).isEmpty
  }

  public func haveEqualSignatures(_ decl: FuncDecl, _ other: FuncDecl) -> Bool {
    guard decl.args.count == other.args.count else { return false }
    guard decl.hasVarArgs == other.hasVarArgs else { return false }
    for (declArg, otherArg) in zip(decl.args, other.args) {
      if declArg.isImplicitSelf && otherArg.isImplicitSelf { continue }
      guard declArg.externalName == otherArg.externalName else { return false }
      guard matches(declArg.type, otherArg.type) else { return false }
    }
    return true
  }

  public func missingMethodsForConformance(_ decl: TypeDecl, to proto: ProtocolDecl) -> [MethodDecl] {
    guard let methods = requiredMethods(for: proto) else { return [] }
    var missing = [MethodDecl]()
    for method in methods {
      let impl = decl.methods(named: method.name.name).first {
        haveEqualSignatures(method, $0)
      }
      if let impl = impl {
        impl.satisfiedProtocols.insert(proto)
      } else {
        missing.append(method)
      }
    }
    return missing
  }

  /// - Returns: Whether the expression's type was changed
  @discardableResult
  public func propagateContextualType(_ contextualType: DataType, to expr: Expr) -> Bool {
    let canTy = canonicalType(contextualType)
    switch expr.semanticsProvidingExpr {
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
      guard case .array(_, let length) = expr.type else { return false }
      guard case .array(let ctx, _) = canTy else {
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
        var changed = propagateContextualType(canTy, to: expr.lhs)
        changed = changed || propagateContextualType(canTy, to: expr.rhs)
        return changed
      }
    case let expr as NilExpr where canBeNil(canTy):
      expr.type = contextualType
      return true
    case let expr as TupleExpr:
      guard
        case .tuple(let contextualFields) = canTy,
        case .tuple(let fields) = expr.type,
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
      } else if propagateContextualType(contextualType, to: expr.trueCase) && propagateContextualType(contextualType, to: expr.falseCase) {
        expr.type = contextualType
        return true
      }
    case let expr as StringExpr:
      if [.string, .pointer(type: DataType.int8)].contains(canTy) {
        expr.type = contextualType
        return true
      }
    case let expr as ClosureExpr:
      if case let .function(_, retTy, _) = canTy {
        expr.type = contextualType
        expr.returnType = TypeRefExpr(type: retTy, name: Identifier(name: ""))
        return true
      }
    default:
      break
    }
    return false
  }

  public func add(_ funcDecl: FuncDecl) {
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

  public func add(_ protocolDecl: ProtocolDecl) {
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
  public func add(_ typeDecl: TypeDecl) -> Bool {
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
  public func add(_ global: VarAssignDecl) -> Bool {
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

  public func add(_ extensionExpr: ExtensionDecl) {
    extensions.append(extensionExpr)
  }

  public func add(_ diagnosticExpr: PoundDiagnosticStmt) {
    diagnostics.append(diagnosticExpr)
  }

  @discardableResult
  public func add(_ alias: TypeAliasDecl) -> Bool {
    guard typeAliasMap[alias.name.name] == nil else {
      return false
    }
    if isCircularAlias(alias.bound.type, visited: [alias.name.name]) {
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

  public func merge(_ context: ASTContext) {
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

  public func protocolDecl(for type: DataType) -> ProtocolDecl? {
    return protocolDeclMap["\(type)"]
  }

  public func decl(for type: DataType, canonicalized: Bool = true) -> TypeDecl? {
    let root = canonicalized ? canonicalType(type) : type
    return typeDeclMap[root]
  }

  public func isIntrinsic(type: DataType) -> Bool {
    if isAlias(type: type) { return false }
    if let d =  decl(for: type, canonicalized: false) {
      return isIntrinsic(decl: d)
    }
    return true
  }

  public func isIntrinsic(decl: Decl) -> Bool {
    return decl.has(attribute: .foreign) || decl.sourceRange == nil
  }

  public func isAlias(type: DataType) -> Bool {
    if case .custom(let name) = type {
      return typeAliasMap[name] != nil
    }
    return false
  }

  public func isCircularAlias(_ type: DataType, visited: Set<String>) -> Bool {
    var visited = visited
    if case .custom(let name) = type {
      if visited.contains(name) { return true }
      visited.insert(name)
      guard let bound = typeAliasMap[name]?.bound.type else { return false }
      return isCircularAlias(bound, visited: visited)
    } else if case .function(let args, let ret, _) = type {
      for arg in args where isCircularAlias(arg, visited: visited) {
        return true
      }
      return isCircularAlias(ret, visited: visited)
    }
    return false
  }

  public func containsInLayout(type: DataType, typeDecl: TypeDecl, base: Bool = false) -> Bool {
    if !base && matchRank(typeDecl.type, type) != nil { return true }
    for property in typeDecl.properties {
      if case .pointer = property.type { continue }
      if property.isComputed { continue }
      if let decl = decl(for: property.type),
        !decl.isIndirect,
        containsInLayout(type: type, typeDecl: decl) {
        return true
      }
    }
    return false
  }

  public func isCircularType(_ typeDecl: TypeDecl) -> Bool {
    return containsInLayout(type: typeDecl.type, typeDecl: typeDecl, base: true)
  }

  /// Determines the ranking of the match between these two types.
  /// This can either be `.equal` or `.any`, depending on the kind of match.
  /// - parameter type1: The first type you're trying to match
  /// - parameter type2: The second type you're trying to match
  /// - returns: The rank of the match between these two types.
  public func matchRank(_ type1: DataType, _ type2: DataType) -> TypeRank? {
    let t1Can = canonicalType(type1)
    let t2Can = canonicalType(type2)
    switch (t1Can, t2Can) {
    case (.tuple(let fields1), .tuple(let fields2)):
        if fields1.count != fields2.count { return nil }
        for (type1, type2) in zip(fields1, fields2) {
            if matchRank(type1, type2) == nil { return nil }
        }
        return .equal
    case (let t1, let t2):
      if case .any = t1 {
        return .any
      }
      if case .any = t2 {
        return .any
      }

      return t1 == t2 ? .equal : nil
    }
  }

  /// Determines if two types can be considered 'matching'.
  /// - returns: True if the match rank between these two types is not `nil`.
  public func matches(_ t1: DataType, _ t2: DataType) -> Bool {
    return matchRank(t1, t2) != nil
  }

  /// Returns all overloaded functions with the given name at top-level scope.
  ///
  /// - Parameter name: The function's base name.
  /// - Returns: An array of functions with that base name.
  public func functions(named name: Identifier) -> [FuncDecl] {
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
  public func operators(for op: BuiltinOperator) -> [OperatorDecl] {
    return operatorMap[op] ?? []
  }


  /// Finds the global variable with a given name
  ///
  /// - Parameter name: The global's name
  /// - Returns: A VarAssignDecl for that global, if it exists.
  public func global(named name: Identifier) -> VarAssignDecl? {
    return globalDeclMap[name.name]
  }

  public func global(named name: String) -> VarAssignDecl? {
    return globalDeclMap[name]
  }

  public func sourceFile(named name: String) -> SourceFile? {
    return sourceFileMap[name]
  }

  public func type(named name: String) -> TypeDecl? {
    return typeDeclMap[DataType(name: name)]
  }

  public func `protocol`(named name: Identifier) -> ProtocolDecl? {
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
  public func requiredMethods(for protocolDecl: ProtocolDecl, visited: Set<String> = Set()) -> [MethodDecl]? {
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

  public func mutability(of expr: Expr) -> Mutability {
    switch expr.semanticsProvidingExpr {
    case let expr as VarExpr:
      return mutability(of: expr)
    case let expr as PropertyRefExpr:
      return mutability(of: expr)
    case let expr as SubscriptExpr:
      return mutability(of: expr.lhs)
    case let expr as PrefixOperatorExpr:
      return mutability(of: expr.rhs)
    case let expr as TupleFieldLookupExpr:
      return mutability(of: expr.lhs)
    default:
      return .immutable(culprit: nil)
    }
  }

  public func mutablity(of expr: PrefixOperatorExpr) -> Mutability {
    switch expr.op {
    case .star:
      return mutability(of: expr.rhs)
    default:
      return .immutable(culprit: nil)
    }
  }

  public func mutability(of expr: VarExpr) -> Mutability {
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

  public func mutability(of expr: PropertyRefExpr) -> Mutability {
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

  public func isIndirect(_ type: DataType) -> Bool {
    guard let decl = decl(for: type) else { return false }
    return decl.isIndirect
  }

  public func canBeNil(_ type: DataType) -> Bool {
    let can = canonicalType(type)
    if case .pointer = can { return true }
    if isIndirect(can) { return true }
    return false
  }

  public func canonicalType(_ type: DataType) -> DataType {
    if case .custom(let name) = type {
      if let alias = typeAliasMap[name] {
        return canonicalType(alias.bound.type)
      }
    }
    if case .function(let args, let returnType, let hasVarArgs) = type {
      var newArgs = [DataType]()
      for argTy in args {
        newArgs.append(canonicalType(argTy))
      }
      return .function(args: newArgs, returnType: canonicalType(returnType), hasVarArgs: hasVarArgs)
    }
    if case .pointer(let subtype) = type {
      return .pointer(type: canonicalType(subtype))
    }
    return type
  }

  public func isGlobalConstant(_ expr: Expr) -> Bool {
    let expr = expr.semanticsProvidingExpr
    if expr is ConstantExpr { return true }
    if let expr = expr as? VarExpr,
       let assign = expr.decl as? VarAssignDecl,
       case .global = assign.kind {
        return !assign.mutable
    }
    return false
  }

  public func isValidType(_ type: DataType) -> Bool {
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
    case .function(let args, let returnType, _):
      for arg in args where !isValidType(arg) {
        return false
      }
      return isValidType(returnType)
    default:
      return true
    }
  }

  public func canCoerce(_ type: DataType, to other: DataType) -> Bool {
    let type = canonicalType(type)
    let other = canonicalType(other)

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

  public func implicitDecl(args: [DataType], ret: DataType,
                           hasVarArgs: Bool = false) -> FuncDecl {
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
                    isPlaceholder: true,
                    hasVarArgs: hasVarArgs)
  }
}

public class StdLibASTContext: ASTContext {
  public var string: TypeDecl {
    return type(named: "String")!
  }

  public var staticStringInitializer: InitializerDecl {
    return string.initializers.first { initializer in
      // TODO: find a way to do this that doesn't require string comparison
      initializer.formattedParameterList == "(_global cString: *Int8, length: Int)"
    }!
  }

  public var staticStringInterpolationSegmentsInitializer: InitializerDecl {
    return string.initializers.first { initializer in
      // TODO: find a way to do this that doesn't require string comparison
      initializer.formattedParameterList == "(_interpolationSegments segments: AnyArray)"
    }!
  }

  public var mirror: TypeDecl {
    return type(named: "Mirror")!
  }

  public var mirrorReflectingTypeMetadataInitializer: InitializerDecl {
    return mirror.initializers.first { initializer in
      // TODO: find a way to do this that doesn't require string comparison
      initializer.formattedParameterList == "(reflectingType typeMeta: *Void)"
    }!
  }

  public var anyArray: TypeDecl {
    return type(named: "AnyArray")!
  }

  public var anyArrayCapacityInitializer: InitializerDecl {
    return anyArray.initializers.first { initializer in
      // TODO: find a way to do this that doesn't require string comparison
      initializer.formattedParameterList == "(capacity: Int)"
    }!
  }

  public var anyArrayAppendElement: FuncDecl {
    return anyArray.methods(named: "append").first { method in
      // TODO: find a way to do this that doesn't require string comparison
      method.formattedParameterList == "(_ element: Any)"
    }!
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
