//
//  IRGenerator.swift
//  Trill
//

import Foundation

#if !XCODE
  import LLVM
#endif

private var fatalErrorConsumer: StreamConsumer<StandardErrorTextOutputStream>? = nil

/// An error that represents a problem with LLVM IR generation or JITting.
enum LLVMError: Error, CustomStringConvertible {
  case noMainFunction
  case closuresUnsupported
  case couldNotLink(String, String)
  case invalidModule(String)
  case brokenJIT
  case llvmError(String)
  case invalidTarget(String)
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
    case .invalidTarget(let target):
      return "invalid target '\(target)'"
    case .couldNotDetermineTarget:
      return "could not determine target for host platform"
    }
  }
}

extension OutputFormat {
  
  func addExtension(to basename: String) -> String {
    var url = URL(fileURLWithPath: basename)
    url.deletePathExtension()
    return url.appendingPathExtension(fileExtension).lastPathComponent
  }
  
  var fileExtension: String {
    switch self {
    case .llvm: return "ll"
    case .asm: return "s"
    case .obj, .binary: return "o"
    case .bitCode: return "bc"
    case .javaScript: return "js"
    default: fatalError("should not be serializing \(self)")
    }
  }
  
  var description: String {
    switch self {
    case .llvm: return "LLVM IR"
    case .binary: return "Executable"
    case .asm: return "Assembly"
    case .obj: return "Object File"
    case .javaScript: return "JavaScript File"
    case .ast: return "AST"
    case .bitCode: return "LLVM Bitcode File"
    }
  }
  
  /// The LLVMCodeGenFileType for this output format
  var llvmType: LLVMCodeGenFileType? {
    switch self {
    case .asm: return LLVMAssemblyFile
    case .binary, .obj: return LLVMObjectFile
    case .bitCode: return nil
    default: fatalError("should not be handled here")
    }
  }
}

/// Stores the state of the current function that's being generated.
/// Use this to find contextual information that might be necessary, i.e.
/// repositioning the builder temporarily.
struct FunctionState {
  
  /// The AST node of the current function being codegenned.
  let function: FuncDecl?
  
  /// The LLVMValueRef of the current function being codegenned.
  let functionRef: LLVMValueRef?
  
  /// The beginning of the return section of a function.
  let returnBlock: LLVMBasicBlockRef?
  
  /// The return stack variable for the current function.
  let resultAlloca: LLVMValueRef?
}

/// Possible ways a binding should be accessed. Determines if a binding
/// is a value or reference type, and
enum Storage {
  /// The binding will always be passed by value into functions.
  case value
  
  /// The binding will always be passed by reference into functions
  case reference
}

/// Represents a variable binding and its corresponding binding type.
struct VarBinding {
  let ref: LLVMValueRef
  let storage: Storage
}

/// Generates and executes LLVM IR for a given AST.
class IRGenerator: ASTVisitor, Pass {
  
  typealias Result = LLVMValueRef?
  
  /// The LLVM module currently being generated
  let module: LLVMModuleRef
  
  /// The LLVM builder that will build instructions
  let builder: LLVMBuilderRef
  
  /// The LLVM context the module lives in
  let llvmContext: LLVMContextRef
  
  /// The target machine we're codegenning for
  let targetMachine: LLVMTargetMachineRef
  
  /// The target triple we're codegenning for
  let targetTriple: String
  
  /// The data layout for the current target
  let layout: LLVMTargetDataRef
  
  /// The ASTContext currently being generated
  let context: ASTContext
  
  /// The command line options
  let options: Options
  
  /// A map of global varible bindings
  var globalVarIRBindings = [Identifier: VarBinding]()
  
  /// A map of local variable bindings.
  /// Will be destroyed when scopes are exited.
  var varIRBindings = [Identifier: VarBinding]()
  
  /// A map of types to their LLVMTypeRefs
  var typeIRBindings = IRGenerator.builtinTypeBindings
  
  var typeMetadataMap = [DataType: LLVMValueRef]()
  
  /// A static set of mappings between all the builtin Trill types to their
  /// LLVM counterparts.
  static let builtinTypeBindings: [DataType: LLVMTypeRef] = [
    .int8: LLVMInt8Type(),
    .int16: LLVMInt16Type(),
    .int32: LLVMInt32Type(),
    .int64: LLVMInt64Type(),
    .uint8: LLVMInt8Type(),
    .uint16: LLVMInt16Type(),
    .uint32: LLVMInt32Type(),
    .uint64: LLVMInt64Type(),
    
    .float: LLVMFloatType(),
    .double: LLVMDoubleType(),
    .float80: LLVMX86FP80Type(),
    
    .bool: LLVMInt1Type(),
    .void: LLVMVoidType()
  ]
  
  /// A table that holds global string values, as strings are interned.
  /// String literals are held at global scope.
  var globalStringMap = [String: LLVMValueRef]()
  
  /// The function currently being generated.
  var currentFunction: FunctionState?
  
  /// The target basic block that a `break` will break to.
  var currentBreakTarget: LLVMBasicBlockRef? = nil
  
  /// The target basic block that a `continue` will break to.
  var currentContinueTarget: LLVMBasicBlockRef? = nil
  
  /// The LLVM value for the `main` function.
  var mainFunction: LLVMValueRef? = nil
  
  /// The function pass manager that performs optimizations.
  let passManager: LLVMPassManagerRef
  
  required convenience init(context: ASTContext) {
    fatalError("call init(context:options:)")
  }
  
  /// Creates an IRGenerator.
  /// - parameters:
  ///   - context: The ASTContext containing the current module.
  ///   - options: The command line arguments.
  init(context: ASTContext, options: Options) throws {
    self.options = options
    
    llvmContext = LLVMGetGlobalContext()
    module = LLVMModuleCreateWithNameInContext("main", llvmContext)
    builder = LLVMCreateBuilderInContext(llvmContext)
    passManager = LLVMCreateFunctionPassManagerForModule(module)
    passManager.addPasses(for: options.optimizationLevel)
    
    fatalErrorConsumer = StreamConsumer(files: [],
                                        stream: &stderr,
                                        colored: true)
    LLVMEnablePrettyStackTrace()
    LLVMInstallFatalErrorHandler {
      fatalErrorConsumer!.consume(Diagnostic.error(LLVMError.llvmError(String(cString: $0!))))
    }
    LLVMInitializeFunctionPassManager(passManager)
    LLVMInitializeNativeAsmPrinter()
    LLVMInitializeNativeTarget()
    
    self.targetTriple = options.targetTriple ?? {
      let triple = LLVMGetDefaultTargetTriple()!
      defer {
        LLVMDisposeMessage(triple)
      }
      return String(cString: triple)
    }()
    let targetTriple = self.targetTriple
    self.targetMachine = try targetTriple.withCString { cString in
      var target: LLVMTargetRef?
      if LLVMGetTargetFromTriple(cString, &target, nil) != 0 {
        throw LLVMError.invalidTarget(targetTriple)
      }
      return LLVMCreateTargetMachine(target!,
                                     cString,
                                     "", // TODO: Figure out what to put here
                                     "", //       because I don't know how to
                                         //       get the CPU and features
                                         options.optimizationLevel.llvmLevel,
                                         LLVMRelocDefault,
                                         LLVMCodeModelDefault)
    }
    
    layout = LLVMGetModuleDataLayout(module)
    
    self.context = context
  }
  
  /// Validates the module using LLVM's module verification.
  /// - throws: LLVMError.invalidModule (if LLVM found errors)
  func validateModule() throws {
    var err: UnsafeMutablePointer<Int8>?
    if LLVMVerifyModule(module, LLVMReturnStatusAction, &err) == 1 {
      defer { LLVMDisposeMessage(err) }
      LLVMDumpModule(module)
      throw LLVMError.invalidModule(String(cString: err!))
    }
  }
  
  var title: String {
    return "LLVM IR Generation"
  }
  
  /// Executes the main function, forwarding the arguments into the JIT.
  /// - parameters:
  ///   - args: The command line arguments that will be sent to the JIT main.
  func execute(_ args: [String]) throws -> Int32 {
    guard let jit = LLVMCreateOrcMCJITReplacement(module, targetMachine) else {
      throw LLVMError.brokenJIT
    }
    try addArchive(at: "/usr/local/lib/libtrillRuntime.a", to: jit)
    let main = try codegenMain(forJIT: true)
    finalizeGlobalInit()
    try validateModule()
    
    print(args)
    return args.withCArrayOfCStrings { argv in
      return LLVMRunFunctionAsMain(jit, main, UInt32(args.count), argv, nil)
    }
  }
  
  /// Adds a static archive to the JIT while running.
  /// - parameters:
  ///   - path: The file path of the library to link.
  /// - throws: LLVMError.couldNotLink if the archive failed to link.
  func addArchive(at path: String, to jit: LLVMExecutionEngineRef) throws {
    if let err = LLVMAddArchive(jit, path) {
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
  func codegenMain(forJIT: Bool) throws -> Result {
    guard
      let mainFunction = mainFunction,
      let mainFlags = context.mainFlags else {
        throw LLVMError.noMainFunction
    }
    let hasArgcArgv = mainFlags.contains(.args)
    let ret = mainFlags.contains(.exitCode) ? resolveLLVMType(.int64) : LLVMVoidType()
    
    var params = [
      LLVMInt32Type(),
      LLVMPointerType(LLVMPointerType(LLVMInt8Type(), 0), 0)
    ]
    
    let mainType = params.withUnsafeMutableBufferPointer { buf in
      LLVMFunctionType(ret, buf.baseAddress, UInt32(buf.count), 0)
    }
    
    // The JIT can't use 'main' because then it'll resolve to the main from Swift.
    let mainName = forJIT ? "trill_main" : "main"
    let function = LLVMAddFunction(module, mainName, mainType)
    let entry = LLVMAppendBasicBlockInContext(llvmContext, function, "entry")
    LLVMPositionBuilderAtEnd(builder, entry)
    
    LLVMBuildCall(builder, codegenGlobalInit(), nil, 0, "")
    
    let val: LLVMValueRef?
    if hasArgcArgv {
      var args = [
        LLVMBuildSExt(builder, LLVMGetParam(function, 0), LLVMInt64Type(), "argc-ext"),
        LLVMGetParam(function, 1)
      ]
      val = args.withUnsafeMutableBufferPointer { buf in
        LLVMBuildCall(builder, mainFunction, buf.baseAddress, UInt32(buf.count), "")
      }
    } else {
      val = LLVMBuildCall(builder, mainFunction, nil, 0, "")
    }
    
    if mainFlags.contains(.exitCode) {
      LLVMBuildRet(builder, val)
    } else {
      LLVMBuildRetVoid(builder)
    }
    return function!
  }
  
  func emit(_ type: OutputFormat, output: String? = nil) throws {
    if mainFunction != nil {
      try codegenMain(forJIT: false)
    }
    finalizeGlobalInit()
    try validateModule()
    let outputBase = options.isStdin ? "out" : output ?? options.filenames.first ?? "out"
    let outputFilename = type.addExtension(to: outputBase)
    if case .llvm = type {
      var err: UnsafeMutablePointer<Int8>?
      outputFilename.withCString { cString in
        let mutable = strdup(cString)
        LLVMPrintModuleToFile(module, mutable, &err)
        free(mutable)
      }
      if let err = err {
        throw LLVMError.llvmError(String(cString: err))
      }
    } else {
      var err: UnsafeMutablePointer<Int8>?
      try outputFilename.withCString { cString in
        let mutable = strdup(cString)
        if let llvmType = type.llvmType {
          LLVMTargetMachineEmitToFile(targetMachine, module, mutable, llvmType, &err)
          if let err = err {
            throw LLVMError.llvmError(String(cString: err))
          }
        } else {
          // Dealing with LLVM Bitcode here
          if LLVMWriteBitcodeToFile(module, mutable) != 0 {
            throw LLVMError.llvmError("LLVMWriteBitcodeToFile failed for an unknown reason")
          }
        }
        free(mutable)
        if case .binary = type {
          targetTriple.withCString { trip in
            _ = clang_linkExecutableFromObject(trip, cString,
                                               options.raw.linkerFlags,
                                               options.raw.linkerFlagCount,
                                               options.raw.ccFlags,
                                               options.raw.ccFlagCount)
          }
        }
      }
    }
  }
  
  func visitTypeAliasDecl(_ decl: TypeAliasDecl) -> Result {
    return nil
  }
  
  /// Runs the IR generation in stages:
  /// 1. Forward declare all types, methods, extensions, and functions in that order.
  /// 2. Visit all types, extensions, and functions, and declare their members.
  /// - note: Global variables are declared lazily as they're accessed, so
  ///         they should not be emitted here.
  @discardableResult
  func run(in context: ASTContext) {
    for type in context.types {
      codegenTypePrototype(type)
      for method in type.methods {
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
  func visitCompoundStmt(_ stmt: CompoundStmt)  -> Result {
    for (idx, subExpr) in stmt.exprs.enumerated() {
      visit(subExpr)
      let isBreak = subExpr is BreakStmt
      let isReturn = subExpr is ReturnStmt
      let isNoReturnFuncCall: Bool = {
        if let c = subExpr as? FuncCallExpr {
          return c.decl?.has(attribute: .noreturn) == true
        }
        return false
      }()
      if (isBreak || isReturn || isNoReturnFuncCall) &&
          idx != (stmt.exprs.endIndex - 1) {
        break
      }
    }
    return nil
  }
  
  func visitTypeRefExpr(_ expr: TypeRefExpr) -> Result { return nil }
  
  /// Shortcut for resolving the LLVM type of a TypeRefExpr
  /// - parameters:
  ///   - type: A TypeRefExpr from an expression.
  func resolveLLVMType(_ type: TypeRefExpr) -> LLVMTypeRef {
    return resolveLLVMType(type.type!)
  }
  
  /// Resolves the LLVM type for a given Trill type.
  /// If the type is an indirect type, then this will always resolve to a pointer.
  /// Otherwise, this will walk through the type for all subtypes, constructing
  /// an appropriate LLVM type.
  /// - note: This always canonicalizes the type before resolution.
  func resolveLLVMType(_ type: DataType) -> LLVMTypeRef {
    let type = context.canonicalType(type)
    if let binding = typeIRBindings[type] {
      return storage(for: type) == .value ? binding : LLVMPointerType(binding, 0)
    }
    switch type {
    case .pointer(.void):
      return LLVMPointerType(LLVMInt8Type(), 0)
    case .array(let field, let length):
      let fieldTy = resolveLLVMType(field)
      if let length = length {
        return LLVMVectorType(fieldTy, UInt32(length))
      }
      return LLVMPointerType(fieldTy, 0)
    case .pointer(let subtype):
      let llvmType = resolveLLVMType(subtype)
      return LLVMPointerType(llvmType, 0)
    case .function(let args, let ret):
      var argTypes: [LLVMTypeRef?] = args.map(resolveLLVMType)
      let retTy = resolveLLVMType(ret)
      return argTypes.withUnsafeMutableBufferPointer { buf in
        LLVMPointerType(LLVMFunctionType(retTy, buf.baseAddress, UInt32(buf.count), 0), 0)
      }
    case .tuple:
      return codegenTupleType(type)
    case .custom:
      if let decl = context.decl(for: type) {
        let proto = codegenTypePrototype(decl)
        return storage(for: type) == .value ? proto : LLVMPointerType(proto, 0)
      }
    default: break
    }
    
    fatalError("unknown llvm type \(type)")
  }
  
  func dumpBindings() {
    print("===")
    for (name, binding) in varIRBindings {
      print("\(name):\n", terminator: "")
      LLVMDumpValue(binding.ref)
      print("storage: \(binding.storage)")
    }
    print("===")
  }
  
  /// Resolves an appropriate VarBinding for a given VarExpr.
  /// Will search first through local and global bindings, then will search
  /// through free functions at global scope.
  /// Will always resolve to a pointer.
  func resolveVarBinding(_ expr: VarExpr) -> (Bool, VarBinding?) {
    if let binding = varIRBindings[expr.name] ?? globalVarIRBindings[expr.name] {
      var shouldLoad = true
      if expr.isSelf && storage(for: expr.type!) == .reference {
        shouldLoad = false
      }
      return (shouldLoad, binding)
    } else if let global = context.global(named: expr.name) {
      return (true, visitGlobal(global))
    } else if let funcDecl = expr.decl as? FuncDecl {
      let mangled = Mangler.mangle(funcDecl)
      if let function = LLVMGetNamedFunction(module, mangled) {
        return (false, VarBinding(ref: function, storage: .value))
      }
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
  
  /// Will emit a diagnostic
  func visitClosureExpr(_ expr: ClosureExpr) -> Result {
    error(LLVMError.closuresUnsupported,
          loc: expr.startLoc)
    return nil
  }
}

extension LLVMBasicBlockRef {
  var endsWithTerminator: Bool {
    guard let lastInst = LLVMGetLastInstruction(self) else { return false }
    return LLVMIsATerminatorInst(lastInst) != nil
  }
}

extension LLVMPassManagerRef {
  func addPasses(for level: OptimizationLevel) {
    if level == O0 { return }
    
    LLVMAddInstructionCombiningPass(self)
    LLVMAddReassociatePass(self)
    
    if level == O1 { return }
    
    LLVMAddGVNPass(self)
    LLVMAddCFGSimplificationPass(self)
    LLVMAddPromoteMemoryToRegisterPass(self)
    
    if level == O2 { return }
    
    LLVMAddFunctionInliningPass(self)
    LLVMAddTailCallEliminationPass(self)
  }
}

extension OptimizationLevel {
  var llvmLevel: LLVMCodeGenOptLevel {
    switch self {
    case O0: return LLVMCodeGenLevelNone
    case O1: return LLVMCodeGenLevelLess
    case O2: return LLVMCodeGenLevelDefault
    case O3: return LLVMCodeGenLevelAggressive
    default: return LLVMCodeGenLevelNone
    }
  }
}
