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
  
  /// The ASTContext currently being generated
  let context: ASTContext
  
  /// A map of global varible bindings
  var globalVarIRBindings = [Identifier: VarBinding]()
  
  /// A map of local variable bindings.
  /// Will be destroyed when scopes are exited.
  var varIRBindings = [Identifier: VarBinding]()
  
  /// A map of types to their LLVMTypeRefs
  var typeIRBindings = IRGenerator.builtinTypeBindings
  
  /// A static set of mappings between all the builtin Trill types to their
  /// LLVM counterparts.
  static let builtinTypeBindings: [DataType: LLVMTypeRef] = [
    .int8: LLVMInt8Type(),
    .int16: LLVMInt16Type(),
    .int32: LLVMInt32Type(),
    .int64: LLVMInt64Type(),
    
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
  
  /// Creates an IRGenerator with no optimizations.
  /// - parameters:
  ///   - context: The ASTContext containing the current module.
  required convenience init(context: ASTContext) {
    self.init(context: context, optimizationLevel: O0)
  }
  
  /// Creates an IRGenerator.
  /// - parameters:
  ///   - context: The ASTContext containing the current module.
  ///   - optimizationLevel: The optimization level specified in the command
  ///                        line arguments.
  init(context: ASTContext, optimizationLevel: OptimizationLevel) {
    llvmContext = LLVMGetGlobalContext()
    module = LLVMModuleCreateWithNameInContext("main", llvmContext)
    builder = LLVMCreateBuilderInContext(llvmContext)
    
    passManager = LLVMCreateFunctionPassManagerForModule(module)
    passManager.addPasses(for: optimizationLevel)
    
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
    
    LLVMSetDataLayout(module, "e")
    
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
    guard let jit = LLVMCreateOrcMCJITReplacementForModule(module) else {
      throw LLVMError.brokenJIT
    }
    try addArchive(at: "/usr/local/lib/libtrillRuntime.a", to: jit)
    let main = try codegenMain(forJIT: true)
    finalizeGlobalInit()
    try validateModule()
    
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
      let mainFuncDecl = context.mainFunction,
      let mainFlags = context.mainFlags else {
        throw LLVMError.noMainFunction
    }
    let hasArgcArgv = mainFlags.contains(.args)
    let ret = mainFlags.contains(.exitCode) ? resolveLLVMType(.int64) : LLVMVoidType()
    
    let params = UnsafeMutablePointer<LLVMTypeRef?>.allocate(capacity: 2)
    params[0] = LLVMInt32Type()
    params[1] = LLVMPointerType(LLVMPointerType(LLVMInt8Type(), 0), 0)
    defer { free(params) }
    let mainType = LLVMFunctionType(ret, params, 2, 0)
    
    // The JIT can't use 'main' because then it'll resolve to the main from Swift.
    let mainName = forJIT ? "trill_main" : "main"
    let function = LLVMAddFunction(module, mainName, mainType)
    let entry = LLVMAppendBasicBlockInContext(llvmContext, function, "entry")
    LLVMPositionBuilderAtEnd(builder, entry)
    
    LLVMBuildCall(builder, codegenGlobalInit(), nil, 0, "")
    
    let val: LLVMValueRef?
    if hasArgcArgv {
      let argsPtr = UnsafeMutablePointer<LLVMValueRef?>.allocate(capacity: 2)
      defer { free(argsPtr) }
      argsPtr[0] = LLVMBuildSExt(builder, LLVMGetParam(function, 0), LLVMInt64Type(), "argc-ext")
      argsPtr[1] = LLVMGetParam(function, 1)
      val = LLVMBuildCall(builder, mainFunction, argsPtr, 2, "")
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
  
  /// Serializes the LLVM module to textual IR.
  /// Will not generate a main entry point if there was no user-defined main.
  func serialize() throws -> String {
    if let mainFunction = mainFunction {
      try codegenMain(forJIT: false)
    }
    finalizeGlobalInit()
    try validateModule()
    let cString = LLVMPrintModuleToString(module)!
    defer { LLVMDisposeMessage(cString) }
    return String(cString: cString)
  }
  
  func visitTypeAliasExpr(_ expr: TypeAliasExpr) -> Result {
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
    for type in context.types {
      visitTypeDecl(type)
    }
    for ext in context.extensions {
      visitExtensionDecl(ext)
    }
    for function in context.functions where !function.has(attribute: .foreign) {
      _ = visitFuncDecl(function)
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
    case .pointer(let subtype):
      let llvmType = resolveLLVMType(subtype)
      return LLVMPointerType(llvmType, 0)
    case .function(let args, let ret):
      let argTypes = UnsafeMutablePointer<LLVMTypeRef?>.allocate(capacity: args.count)
      defer { argTypes.deallocate(capacity: args.count) }
      for (idx, argType) in args.enumerated() {
        argTypes[idx] = resolveLLVMType(argType)
      }
      let retTy = resolveLLVMType(ret)
      return LLVMPointerType(LLVMFunctionType(retTy, argTypes, UInt32(args.count), 0), 0)
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
          loc: expr.startLoc())
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
