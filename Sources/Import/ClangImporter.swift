//
//  ClangImporter.swift
//  Trill
//

import Foundation
import Clang
import cclang

enum ImportError: Error {
  case pastIntMax
}

extension Collection where Iterator.Element == String, IndexDistance == Int {
  func withCArrayOfCStrings<Result>(_ f: (UnsafeMutablePointer<UnsafePointer<Int8>?>) throws -> Result) rethrows -> Result {
    let ptr = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>.allocate(capacity: self.count)
    defer  { freelist(ptr, count: self.count) }
    for (idx, str) in enumerated() {
      str.withCString { cStr in
        ptr[idx] = strdup(cStr)
      }
    }
    return try ptr.withMemoryRebound(to: Optional<UnsafePointer<Int8>>.self,
                                     capacity: self.count, f)
  }
}

func freelist<T>(_ ptr: UnsafeMutablePointer<UnsafeMutablePointer<T>?>, count: Int) {
  for i in 0..<count {
    free(ptr[i])
  }
  free(ptr)
}

extension String {
  var lastWord: String? {
    return components(separatedBy: " ").last
  }
}

extension SourceLocation {
  init(clangLocation: Clang.SourceLocation) {
    self.init(line: clangLocation.line,
              column: clangLocation.column,
              file: clangLocation.file.name,
              charOffset: clangLocation.offset)
  }
}

extension SourceRange {
  init(clangRange: Clang.SourceRange) {
    self.init(start: SourceLocation(clangLocation: clangRange.start),
              end: SourceLocation(clangLocation: clangRange.end))
  }
}

class ClangImporter: Pass {
  static let headerFiles = [
    "stdlib.h",
    "stdio.h",
    "fcntl.h",
    "stdint.h",
    "stddef.h",
    "math.h",
    "string.h",
    "_types.h",
    "pthread.h",
    "sys/time.h",
    "sys/resource.h",
    "sched.h",
  ]
  #if os(macOS)
  static func loadSDKPath() -> String? {
    let pipe = Pipe()
    let xcrun = Process()
    xcrun.launchPath = "/usr/bin/xcrun"
    xcrun.arguments = ["--show-sdk-path", "--sdk", "macosx"]
    xcrun.standardOutput = pipe
    xcrun.launch()
    xcrun.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static let sdkPath: String? = loadSDKPath()
  static let includeDir = sdkPath.map { $0 + "/usr/include" }
  #else
  static let includeDir: String? = "/usr/local/include"
  #endif
  
  let context: ASTContext
  let targetTriple: String
  
  var importedTypes = [Identifier: TypeDecl]()
  var importedFunctions = [Identifier: FuncDecl]()
  
  required init(context: ASTContext) {
    fatalError("use init(context:target:)")
  }
  
  init(context: ASTContext, target: String) {
    self.context = context
    self.targetTriple = target
  }
  
  var title: String {
    return "Clang Importer"
  }
  
  func translationUnit(for path: String) throws -> TranslationUnit {
    let index = Index()
    var args = [
      "-I", "/usr/local/include/trill",
      "-std=gnu11", "-fsyntax-only",
      "-target", targetTriple
    ]

    #if os(macOS)
      if let sdkPath = ClangImporter.sdkPath {
        args.append("-isysroot")
        args.append(sdkPath)
      }
    #endif

    return try TranslationUnit(index: index,
                               filename: path,
                               commandLineArgs: args,
                               options: [.skipFunctionBodies,
                                         .detailedPreprocessingRecord])
  }
  
  func synthesize(name: String, args: [DataType],
                  return: DataType,
                  hasVarArgs: Bool,
                  modifiers: [DeclModifier],
                  range: SourceRange?,
                  argRanges: [SourceRange] = []) -> FuncDecl {
    return FuncDecl(name: Identifier(name: name),
                        returnType: `return`.ref(),
                        args: args.enumerated().map { (idx, type) in
                          let range = argRanges[safe: idx]
                          let ref = type.ref(range: range)
                          return ParamDecl(name: "", type: ref, sourceRange: range)
                        },
                        modifiers: modifiers,
                        hasVarArgs: hasVarArgs,
                        sourceRange: range)
  }
  
  @discardableResult
  func importTypeDef(_ cursor: TypedefDecl, in context: ASTContext) -> TypeAliasDecl? {
    let name = cursor.displayName
    guard ClangImporter.builtinTypeReplacements[name] == nil else { return nil }
    let type = cursor.type!
    let decl = cursor.definition
    var trillType: DataType?
    if let structDecl = decl as? StructDecl {
      if let expr = importStruct(structDecl, in: context) {
        trillType = expr.type
      } else {
        return nil
      }
    } else {
      trillType = convertToTrillType(type)
    }
    guard let t = trillType else {
      return nil
    }

    // If we see a struct declared as:
    //
    // typedef struct struct_name {
    // } struct_name;
    //
    // Where the typedef renames the type without the `struct` keyword, then
    // skip creating a TypeAliasDecl for that type, as it would be circular.
    if t.description == name, context.decl(for: t) != nil {
      return nil
    }

    let range = SourceRange(clangRange: cursor.range)
    let alias = TypeAliasDecl(name: Identifier(name: name),
                              bound: t.ref(range: range),
                              sourceRange: range)
    context.add(alias)
    return alias
  }
  
  @discardableResult
  func importStruct(_ cursor: StructDecl, in context: ASTContext) -> TypeDecl? {

    guard let type = cursor.type,
          let typeName = type.description.lastWord else {
        return nil
    }
    let name = Identifier(name: typeName)
    
    if let e = importedTypes[name] { return e }
    
    var values = [PropertyDecl]()

    for (idx, child) in cursor.children().enumerated() {
      var fieldName = child.displayName
      if fieldName.isEmpty {
        fieldName = "__unnamed_\(idx)"
      }
      let fieldId = Identifier(name: fieldName,
                               range: nil)
      guard let trillTy = convertToTrillType(child.type!) else {
        return nil
      }
      let range = SourceRange(clangRange: child.range)
      let expr = PropertyDecl(name: fieldId,
                              type: trillTy.ref(),
                              mutable: true,
                              rhs: nil,
                              modifiers: [.foreign, .implicit],
                              getter: nil,
                              setter: nil,
                              sourceRange: range)
      values.append(expr)
    }
    
    let range = SourceRange(clangRange: cursor.range)
    let expr = TypeDecl(name: name, properties: values, modifiers: [.foreign, .implicit],
                        sourceRange: range)
    importedTypes[name] = expr
    context.add(expr)
    return expr
  }
  
  func importFunction(_ cursor: FunctionDecl, in context: ASTContext)  {
    let name = cursor.displayName
    if importedFunctions[Identifier(name: name)] != nil { return }
    var modifiers = [DeclModifier.foreign, DeclModifier.implicit]

    if clang_isNoReturn(cursor.asClang()) != 0 {
      modifiers.append(.noreturn)
    }

    let hasVarArgs = cursor.isVariadic
    let funcType = cursor.type as! FunctionType
    
    guard let trillRetTy = convertToTrillType(funcType.returnType!) else { return }

    var args = [DataType]()
    var argRanges = [SourceRange]()
    for param in cursor.parameters() {
      guard let trillType = convertToTrillType(param.type!) else { return }
      args.append(trillType)
      argRanges.append(SourceRange(clangRange: param.range))
    }
    
    let range = SourceRange(clangRange: cursor.range)
    let decl = synthesize(name: name,
                          args: args,
                          return: trillRetTy,
                          hasVarArgs: hasVarArgs,
                          modifiers: modifiers,
                          range: range,
                          argRanges: argRanges)
    importedFunctions[decl.name] = decl
    context.add(decl)
  }
  
  func importEnum(_ cursor: EnumDecl, in context: ASTContext) {
    for child in cursor.children() {
      let name = Identifier(name: child.displayName)
      if context.global(named: name) != nil { continue }
      
      let range = SourceRange(clangRange: child.range)
      let varExpr = VarAssignDecl(name: name,
                                  typeRef: DataType.int32.ref(),
                                  modifiers: [.foreign, .implicit],
                                  mutable: false,
                                  sourceRange: range)!
      context.add(varExpr)
    }
  }
  
  func importUnion(_ cursor: UnionDecl, context: ASTContext) {

    guard
      let type = cursor.type,
      let typeName = type.description.lastWord else {
      return
    }
    var maxType: (CType, Int)? = nil
    for child in cursor.children() {
      let fieldType = child.type!
      let fieldSize = try! fieldType.sizeOf()
      guard let max = maxType else {
        maxType = (fieldType, fieldSize)
        continue
      }
      if fieldSize > max.1 {
        maxType = (fieldType, fieldSize)
      }
    }
    guard let max = maxType?.0,
      let trillType = convertToTrillType(max) else {
      return
    }
    let alias = makeAlias(name: typeName, type: trillType)
    context.add(alias)
  }
  
  func importMacro(_ cursor: MacroDefinition, in tu: TranslationUnit, context: ASTContext) {
    if cursor.isFunctionLike { return }
    let tokens = tu.tokens(in: cursor.range)
    let range = cursor.range
    
    guard tokens.count >= 2 else { return }

    _ = tu.annotate(tokens: tokens)
    
    let name = tokens[0].spelling(in: tu)
    guard context.global(named: Identifier(name: name)) == nil else { return }
    let value = tokens[1]
    switch value {
    case is LiteralToken:
      guard let assign = parse(tu: tu, token: value, name: name) else { return }
      context.add(assign)
    case is IdentifierToken:
      let identifierName = value.spelling(in: tu)
      guard let _ = context.global(named: identifierName) else { return }
      let rhs = VarExpr(name: Identifier(name: identifierName,
                                         range: SourceRange(clangRange: value.range(in: tu))))
      let varDecl = VarAssignDecl(name: Identifier(name: name),
                                  typeRef: nil,
                                  kind: .global,
                                  rhs: rhs,
                                  modifiers: [.implicit],
                                  mutable: false,
                                  sourceRange: SourceRange(clangRange: range))
      context.add(varDecl!)
    default:
      return
    }
  }
  
  func importVariableDeclation(_ cursor: VarDecl, in tu: TranslationUnit, context: ASTContext) {
    guard let cType = cursor.type, let type = convertToTrillType(cType) else { return }
    let name = cursor.displayName
    let identifier = Identifier(name: name,
                                range: SourceRange(clangRange: cursor.range))
    if let existing = context.global(named: name),
       existing.sourceRange == identifier.range { return }
    
    context.add(VarAssignDecl(name: identifier,
                              typeRef: type.ref(),
                              kind: .global,
                              rhs: nil,
                              modifiers: [.foreign, .implicit],
                              mutable: false,
                              sourceRange: identifier.range)!)
  }
  
  // FIXME: Actually use Clang's lexer instead of re-implementing parts of
  //        it, poorly.
  func simpleParseIntegerLiteralToken(_ rawToken: String) throws -> NumExpr? {
    var token = rawToken.lowercased()
    // HACK: harcoded UIntMax.max
    if token == "18446744073709551615ul" || token == "18446744073709551615ull" {
      let expr = NumExpr(value: IntMax(bitPattern: UIntMax.max), raw: rawToken)
      expr.type = .uint64
      return expr
    }
    let suffixTypeMap: [(String, DataType)] = [
      ("ull", .uint64), ("ul", .uint64), ("ll", .int64),
      ("u", .uint32), ("l", .int64)
    ]

    var type = DataType.int64

    for (suffix, suffixType) in suffixTypeMap {
      if token.hasSuffix(suffix) {
        type = suffixType
        let suffixStartIndex = token.characters.index(token.endIndex,
                                                      offsetBy: -suffix.characters.count)
        token.removeSubrange(suffixStartIndex..<token.endIndex)
        break
      }
    }

    guard let num = token.asNumber() else { return nil }

    let expr = NumExpr(value: num, raw: rawToken)
    expr.type = type
    return expr
  }
  
    func simpleParseCToken(_ token: String, range: SourceRange) throws -> Expr? {
    var lexer = Lexer(filename: "", input: token)
    let toks = try lexer.lex()
    guard let first = toks.first?.kind else { return nil }
    switch first {
    case .char(let value):
        return CharExpr(value: value, sourceRange: range)
    case .stringLiteral(let value):
        return StringExpr(value: value, sourceRange: range)
    case .number(let value, let raw):
        return NumExpr(value: value, raw: raw, sourceRange: range)
    case .identifier(let name):
        return try simpleParseIntegerLiteralToken(name) ??
          VarExpr(name: Identifier(name: name, range: range),
                  sourceRange: range)
    default:
        return nil
    }
  }

  func parse(tu: TranslationUnit, token: Clang.Token, name: String) -> VarAssignDecl? {
    do {
      let tok = token.spelling(in: tu)
      let range = SourceRange(clangRange: token.range(in: tu))
      guard let expr = try simpleParseCToken(tok, range: range) else { return nil }

      return VarAssignDecl(name: Identifier(name: name),
                           typeRef: expr.type?.ref(),
                           rhs: expr,
                           modifiers: [.implicit],
                           mutable: false,
                           sourceRange: range)
    } catch { return nil }
  }
  
  func makeAlias(name: String, type: DataType, range: SourceRange? = nil) -> TypeAliasDecl {
    return TypeAliasDecl(name: Identifier(name: name),
                         bound: type.ref(),
                         modifiers: [.implicit],
                         sourceRange: range)
  }
  
  func importDeclarations(for path: String, in context: ASTContext) {
    do {
      let file = try SourceFile(path: .file(URL(fileURLWithPath: path)), context: context)
      context.add(file)
    } catch {
      // do nothing
    }
    let tu: TranslationUnit
    do {
      tu = try translationUnit(for: path)
    } catch {
      context.error(error)
      return
    }
    for child in tu.cursor.children() {
      switch child {
      case let child as TypedefDecl:
        importTypeDef(child, in: context)
      case let child as EnumDecl:
        importEnum(child, in: context)
      case let child as StructDecl:
        importStruct(child, in: context)
      case let child as FunctionDecl:
        importFunction(child, in: context)
      case let child as MacroDefinition:
        importMacro(child, in: tu, context: context)
      case let child as UnionDecl:
        importUnion(child, context: context)
      case let child as VarDecl:
        importVariableDeclation(child, in: tu, context: context)
      default:
        break
      }
    }
  }

  static let runtimeHeaderPath: String = {
    let fileManager = FileManager.default
    
    if let headersURL = runtimeFramework?.bundleURL.appendingPathComponent("Headers"),
      fileManager.fileExists(atPath: headersURL.path) {
      return headersURL.path
    }
    
    return "/usr/lib/include/trill"
  }()
  
  func importBuiltinAliases(into context: ASTContext) {
    context.add(makeAlias(name: "__builtin_va_list",
                          type: .pointer(type: .void)))
    context.add(makeAlias(name: "__va_list_tag",
                          type: .pointer(type: .void)))
  }
  
  func importBuiltinFunctions(into context: ASTContext) {
    func add(_ decl: FuncDecl) {
      context.add(decl)
      importedFunctions[decl.name] = decl
    }
    
    add(synthesize(name: "trill_fatalError",
                   args: [.pointer(type: .int8)],
                   return: .void,
                   hasVarArgs: false,
                   modifiers: [.foreign, .noreturn],
                   range: nil))
    
    // calloc and realloc is imported with `int` for their arguments.
    // I need to override them with .int64 for their arguments.
    add(synthesize(name: "malloc",
                   args: [.int64],
                   return: .pointer(type: .void),
                   hasVarArgs: false,
                   modifiers: [.foreign],
                   range: nil))
    add(synthesize(name: "calloc",
                   args: [.int64, .int64],
                   return: .pointer(type: .void),
                   hasVarArgs: false,
                   modifiers: [.foreign],
                   range: nil))
    add(synthesize(name: "realloc",
                   args: [.pointer(type: .void), .int64],
                   return: .pointer(type: .void),
                   hasVarArgs: false,
                   modifiers: [.foreign],
                   range: nil))
  }

  func run(in context: ASTContext) {
    importBuiltinAliases(into: context)
    importBuiltinFunctions(into: context)

    importDeclarations(for: URL(fileURLWithPath: ClangImporter.runtimeHeaderPath).appendingPathComponent("trill.h").path,
                       in: context)
    if let path = ClangImporter.includeDir {
      for header in ClangImporter.headerFiles {
        importDeclarations(for: "\(path)/\(header)", in: context)
      }
    }
  }
  
  static let builtinTypeReplacements: [String: DataType] = [
    "size_t": .int64,
    "ssize_t": .int64,
    "rsize_t": .int64,
    "uint64_t": .uint64,
    "uint32_t": .uint32,
    "uint16_t": .uint16,
    "uint8_t": .uint8,
    "int64_t": .int64,
    "int32_t": .int32,
    "int16_t": .int16,
    "int8_t": .int8,
    "TRILL_ANY": .any,
  ]
  
  func convertToTrillType(_ type: CType) -> DataType? {
    switch type {
    case is VoidType: return .void
    case is IntType: return .int32
    case is BoolType: return .bool
    case is EnumType: return .int32
    case is FloatType: return .float
    case is DoubleType: return .double
    case is LongDoubleType: return .float80
    case is LongType: return .int64
    case is UIntType: return .uint32
    case is LongLongType: return .int64
    case is ULongType: return .uint64
    case is ULongLongType: return .uint64
    case is ShortType: return .int16
    case is UShortType: return .uint16
    case is SCharType: return .int8
    case is Char_SType: return .int8
    case is Char16Type: return .int16
    case is Char32Type: return .int32
    case is UCharType: return .uint8
    case is WCharType: return .int16
    case is ObjCSelType: return .pointer(type: .int8)
    case is ObjCIdType: return .pointer(type: .int8)
    case is NullPtrType: return .pointer(type: .int8)
    case is UnexposedType: return .pointer(type: .int8)
    case let type as ConstantArrayType:
      guard let underlying = type.element else { return nil }
      guard let trillTy = convertToTrillType(underlying) else { return nil }
      return .pointer(type: trillTy)
    case let type as PointerType:
      let pointee = type.pointee!
      // Check to see if the pointee is a function type:
      if let funcTy = pointee as? FunctionProtoType {
        // function pointer type.
        guard let t = convertFunctionType(funcTy) else { return nil }
        return t
      }
      let trillPointee = convertToTrillType(pointee)
      guard let p = trillPointee else {
        return nil
      }
      return .pointer(type: p)
    case let type as FunctionProtoType:
      return convertFunctionType(type)
    case let type as FunctionNoProtoType:
      guard let trillRet = convertToTrillType(type.returnType!) else { return nil }
      return .function(args: [], returnType: trillRet)
    case let type as TypedefType:
      let typeDecl = type.declaration!
      let typeName = typeDecl.displayName
      if let replacement = ClangImporter.builtinTypeReplacements[typeName] {
        return replacement
      }
      return DataType(name: typeName)
    case let type as RecordType:
      guard let name = type.declaration!.displayName.lastWord else {
          return nil
      }
      return DataType(name: name)
    case let type as ConstantArrayType:
      guard let trillElType = convertToTrillType(type.element!) else { return nil }
      return .tuple(fields: [DataType](repeating: trillElType, count: type.count))
    case let type as ElaboratedType:
      return convertToTrillType(type.namedType!)
    case let type as IncompleteArrayType:
      guard let trillEltTy = convertToTrillType(type.element!) else { return nil }
      return .pointer(type: trillEltTy)
    case is InvalidType:
      return nil
    case is BlockPointerType:
      // C/Obj-C Blocks are unexposed, but are always pointers.
      return .pointer(type: .int8)
    default:
      return nil
    }
  }
  
  func convertFunctionType(_ type: FunctionProtoType) -> DataType? {
    let trillRet = convertToTrillType(type.returnType!) ?? .void
    let args = type.argTypes.flatMap(convertToTrillType)
    return .function(args: args, returnType: trillRet)
  }
}
