//
//  main.swift
//  Trill
//

import Foundation

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    write(string.data(using: .utf8)!)
  }
}


var stderr = FileHandle.standardError
var stdout = FileHandle.standardOutput

func populate(driver: Driver, options: Options,
              sourceFiles: [SourceFile],
              isATTY: Bool,
              context: ASTContext) throws {
  var gen: IRGenerator? = nil
  driver.add("Lexing and Parsing") { context in
    lexAndParse(sourceFiles: sourceFiles, into: context)
  }
  
  if options.importC {
    let irgen = try IRGenerator(context: context,
                                options: options)
    driver.add("Clang Importer") { context in
      return ClangImporter(context: context,
                           target: irgen.targetMachine.triple).run(in: context)
    }
    gen = irgen
  }
  
  if options.includeStdlib {
    driver.add("Parsing Standard Library") { context in
      let stdlibContext = StdLibASTContext(diagnosticEngine: context.diag)
      guard let stdlibPath = runtimeFramework?.path(forResource: "stdlib", ofType: nil), FileManager.default.fileExists(atPath: stdlibPath) else {
        context.diag.error("Unable to find the stdlib in the trill runtime")
        return
      }
      guard let stdlibFiles = FileManager.default.recursiveChildren(of: stdlibPath)?.filter({ f in f.hasSuffix(".tr") }) else {
        context.diag.error("Unable to enumerate stdlib at \(stdlibPath)")
        return
      }
      let stdlibSourceFiles = try _sourceFiles(from: stdlibFiles, diag: context.diag)
      lexAndParse(sourceFiles: stdlibSourceFiles, into: stdlibContext)
      context.stdlib = stdlibContext
      context.merge(context: stdlibContext)
    }
  }
  
  let addASTPass: () -> Bool = {
    if case .emit(.ast) = options.mode {
      driver.add("Dumping the AST") { context in
        var stream = ColoredANSIStream(&stdout, colored: isATTY)
        return ASTDumper(stream: &stream,
                         context: context,
                         files: sourceFiles,
                         showImports: options.showImports).run(in: context)
      }
      return true
    }
    return false
  }
  
  if options.parseOnly && addASTPass() {
    return
  }
  
  driver.add(pass: Sema.self)
  driver.add(pass: TypeChecker.self)
  
  if !options.parseOnly && addASTPass() {
    return
  }
  
  if case .onlyDiagnostics = options.mode { return }
  
  if case .emit(.javaScript) = options.mode {
    driver.add("Generating JavaScript") { context in
      return JavaScriptGen(stream: &stdout, context: context).run(in: context)
    }
    return
  }
  
  driver.add("LLVM IR Generation", pass: gen!.run)
  
  switch options.mode {
  case .emit(let outputType):
    driver.add("Serializing \(outputType)") { context in
      try gen!.emit(outputType, output: options.outputFilename)
    }
    break
  case .jit:
    driver.add("Executing the JIT") { context in
      var args = options.jitArgs
      args.insert("\(options.filenames.first ?? "<>")", at: 0)
      let ret = try gen!.execute(args)
      if ret != 0 {
        context.diag.error("program exited with non-zero exit code \(ret)")
      }
    }
  default: break
  }
}

func sourceFiles(options: Options, diag: DiagnosticEngine) throws -> [SourceFile] {
  if options.isStdin {
    let context = ASTContext(diagnosticEngine: diag)
    let file = try SourceFile(path: .stdin,
                              context: context)
    context.add(file)
    return [file]
  } else {
    return try _sourceFiles(from: options.filenames, diag: diag)
  }
}

func _sourceFiles(from filenames: [String], diag: DiagnosticEngine) throws -> [SourceFile] {
  return try filenames.map { path in
    let context = ASTContext(diagnosticEngine: diag)
    let url = URL(fileURLWithPath: path)
    let file = try SourceFile(path: .file(url), context: context)
    context.add(file)
    return file
  }
}

func lexAndParse(sourceFiles: [SourceFile], into context: ASTContext) {
  if sourceFiles.count == 1 {
    sourceFiles[0].parse()
    context.merge(context: sourceFiles[0].context)
    return
  }
  let group = DispatchGroup()
  for file in sourceFiles {
    DispatchQueue.global().async(group: group) {
      file.parse()
    }
  }
  group.wait()
  for file in sourceFiles {
    context.merge(context: file.context)
  }
}

func main() -> Int32 {
  let options = Options(ParseArguments(CommandLine.argc, CommandLine.unsafeArgv))
  
  let diag = DiagnosticEngine()
  let context = ASTContext(diagnosticEngine: diag)
  let driver = Driver(context: context)
  var files = [SourceFile]()
  do {
    files = try sourceFiles(options: options, diag: diag)
    
    try populate(driver: driver,
                 options: options,
                 sourceFiles: files,
                 isATTY: ansiEscapeSupportedOnStdErr,
                 context: context)
    driver.run(in: context)
  } catch {
    diag.error(error)
  }
  if options.jsonDiagnostics {
    let consumer = JSONDiagnosticConsumer(stream: &stderr)
    diag.register(consumer)
  } else {
    var stream = ColoredANSIStream(&stderr, colored: ansiEscapeSupportedOnStdErr)
    let consumer = StreamConsumer(context: context, stream: &stream)
    diag.register(consumer)
  }
  diag.consumeDiagnostics()
  
  if options.emitTiming {
    var passColumn = Column(title: "Pass Title")
    var timeColumn = Column(title: "Time")
    for (title, time) in driver.timings {
      passColumn.rows.append(title)
      timeColumn.rows.append(format(time: time))
    }
    TableFormatter(columns: [passColumn, timeColumn]).write(to: &stderr)
  }
  return diag.hasErrors ? -1 : 0
}

exit(main())
