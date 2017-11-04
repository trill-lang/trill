///
/// BaseIRGen.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import Diagnostics
import Foundation
import Options
import cllvm
import LLVM
import LLVMWrappers
import Runtime

private var _fatalErrorConsumer: StreamConsumer<ColoredANSIStream<FileHandle>>? = nil

/// An error that represents a problem with LLVM IR generation or JITting.
enum LLVMError: Error, CustomStringConvertible {
  case noMainFunction
  case closuresUnsupported
  case couldNotLink(String, String)
  case invalidModule(String)
  case brokenJIT
  case llvmError(String)
  case couldNotDetermineTarget
  var description: String {
    switch self {
    case .noMainFunction:
      return "no main function"
    case .closuresUnsupported:
      return "closures are currently unsupported"
    case .couldNotLink(let path, let msg):
      return "could not link archive '\(path)': \(msg)"
    case .brokenJIT:
      return "the JIT experienced an unknown error"
    case .invalidModule(let msg):
      return "module file is invalid:\n\(msg)"
    case .llvmError(let msg):
      return "LLVM Error: \(msg)"
    case .couldNotDetermineTarget:
      return "could not determine target for host platform"
    }
  }
}

/// Stores the state of the current function that's being generated.
/// Use this to find contextual information that might be necessary, i.e.
/// repositioning the builder temporarily.
struct FunctionState {
  /// The AST node of the current function being codegenned.
  let function: FuncDecl?
  
  /// The IRValue of the current function being codegenned.
  let functionRef: Function?
  
  /// The beginning of the return section of a function.
  let returnBlock: BasicBlock?
  
  /// The return stack variable for the current function.
  let resultAlloca: IRValue?
}

/// Generates and executes LLVM IR for a given AST.
public class IRGenerator: ASTVisitor, Pass {

  public typealias Result = IRValue?

  @discardableResult
  public func visitProtocolDecl(_ decl: ProtocolDecl) -> Result {
    fatalError("protocols unsupported")
  }

  /// The LLVM module currently being generated
  let module: Module

  /// The LLVM builder that will build instructions
  let builder: IRBuilder

  /// The LLVM context the module lives in
  let llvmContext: Context

  /// The location of the trill Runtime.
  let runtimeLocation: RuntimeLocation

  /// The target machine we're codegenning for
  public let targetMachine: TargetMachine

  /// The data layout for the current target
  public let layout: TargetData

  /// The ASTContext currently being generated
  public let context: ASTContext

  /// The command line options
  let options: Options

  /// A map of global varible bindings
  var globalVarIRBindings = [Identifier: VarBinding]()

  /// A map of local variable bindings.
  /// Will be destroyed when scopes are exited.
  var varIRBindings = [Identifier: VarBinding]()

  /// A map of types to their IRTypes
  var typeIRBindings = IRGenerator.builtinTypeBindings

  var typeMetadataMap = [DataType: Global]()

  /// A static set of mappings between all the builtin Trill types to their
  /// LLVM counterparts.
  static let builtinTypeBindings: [DataType: IRType] = [
    .int8: IntType.int8,
    .int16: IntType.int16,
    .int32: IntType.int32,
    .int64: IntType.int64,
    .uint8: IntType.int8,
    .uint16: IntType.int16,
    .uint32: IntType.int32,
    .uint64: IntType.int64,

    .float: FloatType.float,
    .double: FloatType.double,
    .float80: FloatType.x86FP80,

    .bool: IntType.int1,
    .void: VoidType()
  ]

  /// A table that holds global string values, as strings are interned.
  /// String literals are held at global scope.
  var globalStringMap = [String: (IRValue, Int)]()

  /// The function currently being generated.
  var currentFunction: FunctionState?

  /// The target basic block that a `break` will break to.
  var currentBreakTarget: BasicBlock? = nil

  /// The target basic block that a `continue` will break to.
  var currentContinueTarget: BasicBlock? = nil

  /// The LLVM value for the `main` function.
  var mainFunction: IRValue? = nil

  /// The function pass manager that performs optimizations.
  let passManager: FunctionPassManager

  required public convenience init(context: ASTContext) {
    fatalError("call init(context:options:)")
  }

  /// Creates an IRGenerator.
  /// - parameters:
  ///   - context: The ASTContext containing the current module.
  ///   - options: The command line arguments.
  public init(context: ASTContext,
              options: Options,
              runtimeLocation: RuntimeLocation,
              fatalErrorConsumer: StreamConsumer<ColoredANSIStream<FileHandle>>? = nil) throws {
    self.options = options

    llvmContext = Context.global
    module = Module(name: "main", context: llvmContext)
    builder = IRBuilder(module: module)
    passManager = FunctionPassManager(module: module)
    passManager.addPasses(for: options.optimizationLevel)

    LLVMEnablePrettyStackTrace()
    if let consumer = fatalErrorConsumer {
        _fatalErrorConsumer = consumer
        LLVMInstallFatalErrorHandler {
          _fatalErrorConsumer?.consume(.error(LLVMError.llvmError(String(cString: $0!))))
        }
    }
    LLVMInitializeNativeAsmPrinter()
    LLVMInitializeNativeTarget()

    let reg = LLVMGetGlobalPassRegistry()
    LLVMInitializeIPA(reg)
    LLVMInitializeIPO(reg)
    LLVMInitializeCore(reg)
    LLVMInitializeTarget(reg)
    LLVMInitializeCodeGen(reg)
    LLVMInitializeAnalysis(reg)
    LLVMInitializeScalarOpts(reg)
    LLVMInitializeInstCombine(reg)
    LLVMInitializeObjCARCOpts(reg)
    LLVMInitializeVectorization(reg)
    LLVMInitializeTransformUtils(reg)
    LLVMInitializeInstrumentation(reg)

    self.targetMachine = try TargetMachine(triple: options.targetTriple)

    layout = module.dataLayout

    self.context = context
    self.runtimeLocation = runtimeLocation
  }

  public var title: String {
    return "LLVM IR Generation"
  }

  /// Executes the main function, forwarding the arguments into the JIT.
  /// - parameters:
  ///   - args: The command line arguments that will be sent to the JIT main.
  public func execute(_ args: [String]) throws -> Int {
    guard let jit = ORCJIT(module: module, machine: targetMachine) else {
      throw LLVMError.brokenJIT
    }
    try addArchive(at: runtimeLocation.library.path, to: jit.llvm)
    let main = try codegenMain(forJIT: true)
    do {
      try module.verify()
    } catch {
      module.dump()
      throw error // rethrow after dumping
    }
    return jit.runFunctionAsMain(main, argv: args)
  }

  /// Adds a static archive to the JIT while running.
  /// - parameters:
  ///   - path: The file path of the library to link.
  /// - throws: LLVMError.couldNotLink if the archive failed to link.
  func addArchive(at path: String, to jit: LLVMExecutionEngineRef) throws {
    if let err = LLVMAddArchive(UnsafeMutableRawPointer(jit), path) {
      defer { free(err) }
      throw LLVMError.couldNotLink(path, String(cString: err))
    }
  }

  /// Codegens the Trill main entry point, that calls into the user-defined entry
  /// point. Will accomodate a main function of one of the following forms:
  /// ```
  /// func main()
  /// func main() -> Int
  /// func main(argc: Int, argv: **Int8)
  /// func main(argc: Int, argv: **Int8) -> Int
  /// ```
  /// - throws: LLVMError.noMainFunction if there wasn't a user-supplied main.
  @discardableResult
  func codegenMain(forJIT: Bool) throws -> Function {
    guard
      let mainFunction = mainFunction,
      let mainFlags = context.mainFlags else {
        throw LLVMError.noMainFunction
    }
    let hasArgcArgv = mainFlags.contains(.args)
    let ret = resolveLLVMType(.int32)

    let mainType = FunctionType(argTypes: [
      IntType.int32,
      PointerType(pointee: PointerType(pointee: IntType.int8))
      ], returnType: ret)

    // The JIT can't use 'main' because then it'll resolve to the main from Swift.
    let mainName = forJIT ? "trill_main" : "main"
    let function = builder.addFunction(mainName, type: mainType)
    let entry = function.appendBasicBlock(named: "entry", in: llvmContext)
    builder.positionAtEnd(of: entry)

    _ = builder.buildCall(codegenIntrinsic(named: "trill_init"), args: [])

    let val: IRValue
    if hasArgcArgv {
      val = builder.buildCall(mainFunction, args: [
        builder.buildSExt(function.parameter(at: 0)!, type: IntType.int64, name: "argc-ext"),
        function.parameter(at: 1)!
        ])
    } else {
      val = builder.buildCall(mainFunction, args: [])
    }

    if mainFlags.contains(.exitCode) {
      builder.buildRet(builder.buildTrunc(val, type: ret, name: "main-ret-trunc"))
    } else {
      builder.buildRet(ret.null())
    }
    return function
  }

  public func emit(_ type: OutputFormat, output: String? = nil) throws {
    if mainFunction != nil {
      try codegenMain(forJIT: false)
    }
    do {
      try module.verify()
    } catch {
      module.dump()
      throw error // rethrow after dumping
    }
    let outputBase = options.isStdin ? "out" :
        output ?? options.filenames.first ?? "out"
    let outputFilename = type.addExtension(to: outputBase)
    if case .llvm = type {
      try module.print(to: outputFilename)
    } else {
      if let irType = type.irType {
        try targetMachine.emitToFile(module: module,
                                     type: irType,
                                     path: outputFilename)
      }
      if case .binary = type {
        let executableName =
          URL(fileURLWithPath: outputFilename).deletingPathExtension().path
        let invocation = try ClangInvocation()
        invocation.invoke([
          outputFilename,
          "-l", "c++",
          "-l", "trillRuntime",
          "-L", runtimeLocation.libraryDir.path,
          "-o", executableName,
        ], linkerFlags: options.linkerFlags)
      }
    }
  }

  public func visitTypeAliasDecl(_ decl: TypeAliasDecl) -> Result {
    return nil
  }

  /// Runs the IR generation in stages:
  /// 1. Forward declare all types, methods, extensions, and functions in that order.
  /// 2. Visit all types, extensions, and functions, and declare their members.
  /// - note: Global variables are declared lazily as they're accessed, so
  ///         they should not be emitted here.
  public func run(in context: ASTContext) {
    for type in context.types {
      codegenTypePrototype(type)
      for method in type.methods {
        codegenFunctionPrototype(method)
      }
      for method in type.staticMethods {
        codegenFunctionPrototype(method)
      }
    }
    for ext in context.extensions {
      codegenExtensionPrototype(ext)
    }
    for function in context.functions where !function.has(attribute: .foreign) {
      codegenFunctionPrototype(function)
    }
    for op in context.operators {
      codegenFunctionPrototype(op)
    }
    for type in context.types {
      visitTypeDecl(type)
    }
    for ext in context.extensions {
      visitExtensionDecl(ext)
    }
    for function in context.functions where !function.has(attribute: .foreign) {
      _ = visitFuncDecl(function)
    }
    for op in context.operators {
      _ = visitFuncDecl(op)
    }
  }

  @discardableResult
  public func visitCompoundStmt(_ stmt: CompoundStmt)  -> Result {
    for (idx, subExpr) in stmt.stmts.enumerated() {
      visit(subExpr)
      let isBreak = subExpr is BreakStmt
      let isReturn = subExpr is ReturnStmt
      let isNoReturnFuncCall: Bool = {
        if let exprStmt = subExpr as? ExprStmt, let c = exprStmt.expr as? FuncCallExpr {
          return c.decl?.has(attribute: .noreturn) == true
        }
        return false
      }()
      if (isBreak || isReturn || isNoReturnFuncCall) &&
        idx != (stmt.stmts.endIndex - 1) {
        break
      }
    }
    return nil
  }

  public func visitTypeRefExpr(_ expr: TypeRefExpr) -> Result { return nil }

  /// Shortcut for resolving the LLVM type of a TypeRefExpr
  /// - parameters:
  ///   - type: A TypeRefExpr from an expression.
  func resolveLLVMType(_ type: TypeRefExpr) -> IRType {
    return resolveLLVMType(type.type)
  }

  /// Resolves the LLVM type for a given Trill type.
  /// If the type is an indirect type, then this will always resolve to a pointer.
  /// Otherwise, this will walk through the type for all subtypes, constructing
  /// an appropriate LLVM type.
  /// - note: This always canonicalizes the type before resolution.
  func resolveLLVMType(_ type: DataType) -> IRType {
    let type = context.canonicalType(type)
    if let binding = typeIRBindings[type] {
      return storage(for: type) == .value ? binding : PointerType(pointee: binding)
    }
    switch type {
    case .any:
      fallthrough
    case .pointer(.void):
      return PointerType(pointee: IntType.int8)
    case .array(let field, let length):
      let fieldTy = resolveLLVMType(field)
      if let length = length {
        return VectorType(elementType: fieldTy, count: length)
      }
      return PointerType(pointee: fieldTy)
    case .pointer(let subtype):
      let irType = resolveLLVMType(subtype)
      return PointerType(pointee: irType)
    case .function(let args, let ret, let hasVarArgs):
      let argTypes = args.map(resolveLLVMType)
      let retTy = resolveLLVMType(ret)
      return PointerType(pointee: FunctionType(argTypes: argTypes,
                                               returnType: retTy,
                                               isVarArg: hasVarArgs))
    case .tuple:
      return codegenTupleType(type)
    case .custom:
      if let decl = context.decl(for: type) {
        let proto = codegenTypePrototype(decl)
        return storage(for: type) == .value ? proto : PointerType(pointee: proto)
      }
    default: break
    }

    fatalError("unknown llvm type \(type)")
  }

  func dumpBindings() {
    print("===")
    for (name, binding) in varIRBindings {
      print("\(name):\n", terminator: "")
      binding.ref.dump()
      print("storage: \(binding.storage)")
    }
    print("===")
  }

  /// Resolves an appropriate VarBinding for a given VarExpr.
  /// Will search first through local and global bindings, then will search
  /// through free functions at global scope.
  /// Will always resolve to a pointer.
  func resolveVarBinding(_ expr: VarExpr) -> VarBinding? {
    if let binding = varIRBindings[expr.name] ?? globalVarIRBindings[expr.name] {
      return binding
    } else if let global = context.global(named: expr.name) {
      return visitGlobal(global)
    } else if let funcDecl = expr.decl as? FuncDecl {
      let mangled = Mangler.mangle(funcDecl)
      if let function = module.function(named: mangled) {
        let binding = VarBinding(ref: function, storage: .value,
                                 read: {
                                  return function
        },
                                 write: { value in
                                  fatalError("Cannot reassign function")
        })
        return binding
      }
    } else if let decl = expr.decl, expr.isTypeVar, DataType(name: "Mirror") == expr.type {
      let mirrorInitializer = context.stdlib!.mirrorReflectingTypeMetadataInitializer
      let function = codegenFunctionPrototype(mirrorInitializer)
      return VarBinding(ref: function,
                        storage: .reference,
                        read: {
                          let meta = self.codegenTypeMetadata(decl.type)
                          let arg = self.builder.buildBitCast(meta, type: PointerType(pointee: IntType.int8))
                          return self.builder.buildCall(function, args: [arg])
      },
                        write: { _ in fatalError("Cannot reassign type") })
    }
    fatalError("unknown var \(expr.name.name)")
  }

  /// Sets the current function for the duration of the provided block.
  func withFunction(_ block: () -> ()) {
    let oldFunction = currentFunction
    withScope(block)
    currentFunction = oldFunction
  }

  /// Creates a scope for the duration of the provided block, and resets the
  /// variable bindings once that block has finished.
  func withScope(_ block: ()  -> ()) {
    let oldVarIRBindings = varIRBindings
    let oldBreakTarget = currentBreakTarget
    let oldContinueTarget = currentContinueTarget
    block()
    currentBreakTarget = oldBreakTarget
    currentContinueTarget = oldContinueTarget
    varIRBindings = oldVarIRBindings
  }

  public func visitPropertyDecl(_ decl: PropertyDecl) -> IRValue? {
    if let getter = decl.getter {
      _ = visitFuncDecl(getter)
    }
    if let setter = decl.setter {
      _ = visitFuncDecl(setter)
    }
    return nil
  }

  /// Will emit a diagnostic
  public func visitClosureExpr(_ expr: ClosureExpr) -> Result {
    error(LLVMError.closuresUnsupported,
          loc: expr.startLoc)
    return nil
  }

  func codegenDebugPrintf(format: String, _ values: IRValue...) {
    var args = Array(values)
    args.insert(visitStringExpr(StringExpr(value: format))!, at: 0)
    let printfCall = codegenIntrinsic(named: "printf")
    _ = builder.buildCall(printfCall, args: args)
  }
}

extension BasicBlock {
  var endsWithTerminator: Bool {
    guard let lastInst = lastInstruction else { return false }
    return lastInst.isATerminatorInst
  }
}

extension FunctionPassManager {
  func addPasses(for level: OptimizationLevel) {
    if level == .none { return }

    add(.basicAliasAnalysis, .instructionCombining, .reassociate)

    if level == .less { return }

    add(.gvn, .cfgSimplification, .promoteMemoryToRegister)

    if level == .default { return }

    add(.tailCallElimination, .loopUnroll)
  }
}

extension OptimizationLevel {
  var llvmLevel: LLVMCodeGenOptLevel {
    switch self {
    case .none: return LLVMCodeGenLevelNone
    case .less: return LLVMCodeGenLevelLess
    case .default: return LLVMCodeGenLevelDefault
    case .aggressive: return LLVMCodeGenLevelAggressive
    }
  }
}

extension OutputFormat {
  /// The LLVMCodeGenFileType for this output format
  public var irType: CodegenFileType? {
    switch self {
    case .asm: return .assembly
    case .binary, .obj: return .object
    case .bitCode: return .bitCode
    default: fatalError("should not be handled here")
    }
  }
}

