//
//  ASTContext.swift
//  Trill
//

import Foundation

enum ASTError: Error, CustomStringConvertible {
  case duplicateVar(name: Identifier)
  case duplicateType(name: Identifier)
  case duplicateFunction(name: Identifier)
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
  
  var functions = [FuncDecl]()
  var operators = [OperatorDecl]()
  var types = [TypeDecl]()
  var extensions = [ExtensionDecl]()
  var diagnostics = [PoundDiagnosticStmt]()
  var globals = [VarAssignDecl]()
  var typeAliases = [TypeAliasDecl]()
  
  private var funcDeclMap = [String: [FuncDecl]]()
  private var typeDeclMap: [DataType: TypeDecl] = [
    .int8: TypeDecl(name: "Int8",  fields: []),
    .int16: TypeDecl(name: "Int16",  fields: []),
    .int32: TypeDecl(name: "Int32",  fields: []),
    .int64: TypeDecl(name: "Int",  fields: []),
    .uint8: TypeDecl(name: "UInt8",  fields: []),
    .uint16: TypeDecl(name: "UInt16",  fields: []),
    .uint32: TypeDecl(name: "UInt32",  fields: []),
    .uint64: TypeDecl(name: "UInt",  fields: []),
    .double: TypeDecl(name: "Double",  fields: []),
    .float: TypeDecl(name: "Float",  fields: []),
    .float80: TypeDecl(name: "Float80",  fields: []),
    .bool: TypeDecl(name: "Bool", fields: []),
    .void: TypeDecl(name: "Void", fields: [])
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
  
  func infixOperatorCandidate(_ op: BuiltinOperator, lhs: Expr, rhs: Expr) -> OperatorDecl? {
    let canLhs = canonicalType(lhs.type!)
    if rhs is NilExpr && canBeNil(canLhs) && [.equalTo, .notEqualTo].contains(op) {
      return OperatorDecl(op: op,
                          args: [
                            FuncArgumentAssignDecl(name: "", type: lhs.type!.ref()),
                            FuncArgumentAssignDecl(name: "", type: lhs.type!.ref())
                          ],
                          returnType: DataType.bool.ref(),
                          body: nil,
                          modifiers: [.implicit])
    }
    
    let canRhs = canonicalType(rhs.type!)
    let decls = operators(for: op)
    for decl in decls {
      if matches(decl.args[0].type, canLhs) && matches(decl.args[1].type, canRhs) {
        return decl
      }
    }
    return nil
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
    if !base && matches(typeDecl.type, type) { return true }
    for field in typeDecl.fields {
      if case .pointer = field.type { continue }
      if let decl = decl(for: field.type),
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
  
  func matches(_ type1: DataType?, _ type2: DataType?) -> Bool {
    switch (type1, type2) {
    case (nil, nil): return true
    case (_, nil): return false
    case (nil, _): return false
    case (.tuple(let fields1)?, .tuple(let fields2)?):
        if fields1.count != fields2.count { return false }
        for (type1, type2) in zip(fields1, fields2) {
            if !matches(type1, type2) { return false }
        }
        return true
    case (let t1?, let t2?):
      let t1Can = canonicalType(t1)
      let t2Can = canonicalType(t2)
      
      if case .any = t1Can {
        return true
      }
      if case .any = t2Can {
        return true
      }
      
      return t1Can == t2Can
    default:
      return false
    }
  }
  
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
  
  func operators(for op: BuiltinOperator) -> [OperatorDecl] {
    return operatorMap[op] ?? []
  }
  
  func global(named name: Identifier) -> VarAssignDecl? {
    return globalDeclMap[name.name]
  }
  
  func global(named name: String) -> VarAssignDecl? {
    return globalDeclMap[name]
  }
  
  func mutability(of node: ASTNode) -> Mutability {
    switch node {
    case let node as VarExpr:
      return mutability(of: node)
    case let node as FieldLookupExpr:
      return mutability(of: node)
    case let node as SubscriptExpr:
      return mutability(of: node.lhs)
    case let node as ParenExpr:
      return mutability(of: node.value)
    case let node as PrefixOperatorExpr:
      return mutability(of: node.rhs)
    case let node as TupleFieldLookupExpr:
      return mutability(of: node.lhs)
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
  
  func mutability(of expr: FieldLookupExpr) -> Mutability {
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
                     _ returnType: DataType) {
        self.init(op: op, args: [
            FuncArgumentAssignDecl(name: "lhs", type: lhsType.ref()),
            FuncArgumentAssignDecl(name: "rhs", type: rhsType.ref()),
            ], returnType: returnType.ref(),
               body: CompoundStmt(exprs: []),
               modifiers: [.implicit])
    }
}
  
