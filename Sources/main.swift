//
//  main.swift
//  Trill
//

import Foundation

class StandardErrorTextOutputStream: TextOutputStream {
  func write(_ string: String) {
    let stderr = FileHandle.standardError
    stderr.write(string.data(using: .utf8)!)
  }
}

var stderr = StandardErrorTextOutputStream()

class StandardTextOutputStream: TextOutputStream {
  func write(_ string: String) {
    let stdout = FileHandle.standardOutput
    stdout.write(string.data(using: .utf8)!)
  }
}

var stdout = StandardTextOutputStream()

func populate(driver: Driver, options: Options,
              sourceFiles: [SourceFile],
              context: ASTContext) throws {
  driver.add("Lexing and Parsing") { context in
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
  if options.importC {
    driver.add(pass: ClangImporter.self)
  }
  switch options.mode {
  case .emitAST:
    driver.add("Dumping the AST") { context in
      return ASTDumper(stream: &stdout, context: context).run(in: context)
    }
    return
  case .prettyPrint:
    driver.add("Pretty Printing the AST") { context in
      return ASTPrinter(stream: &stdout, context: context).run(in: context)
    }
    return
  default: break
  }
  
  driver.add(pass: Sema.self)
  driver.add(pass: TypeChecker.self)
  
  if case .onlyDiagnostics = options.mode { return }
  
  if case .emitJavaScript = options.mode {
    driver.add("Generating JavaScript") { context in
      return JavaScriptGen(stream: &stdout, context: context).run(in: context)
    }
    return
  }
  
  let gen = try IRGenerator(context: context,
                            options: options)
  driver.add("LLVM IR Generation", pass: gen.run)
  
  switch options.mode {
  case .emitLLVM, .emitASM, .emitObj, .emitBinary:
    let outputType: EmitType
    switch options.mode {
    case .emitLLVM: outputType = .llvm
    case .emitObj: outputType = .obj
    case .emitASM: outputType = .asm
    default: outputType = .bin
    }
    driver.add("Serializing \(outputType)") { context in
      try gen.emit(outputType, output: options.outputFilename)
    }
    break
  case .jit:
    driver.add("Executing the JIT") { context in
      // TODO: Fix sending args to the JIT
//      var args = options.remainder
//      args.insert("\(options.filename)", at: 0)
      let ret = try gen.execute([])
      if ret != 0 {
        context.diag.error("program exited with non-zero exit code \(ret)")
      }
    }
  default: break
  }
}

func sourceFiles(options: Options, diag: DiagnosticEngine) throws -> [SourceFile] {
  if options.isStdin {
    return [try SourceFile(path: .stdin,
                           context: ASTContext(diagnosticEngine: diag))]
  } else {
    return try options.filenames.map { path in
      let context = ASTContext(diagnosticEngine: diag)
      let url = URL(fileURLWithPath: path)
      return try SourceFile(path: .file(url), context: context)
    }
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
                 context: context)
    driver.run(in: context)
  } catch {
    diag.error(error)
  }
  let isATTY = isatty(STDERR_FILENO) != 0
  if options.jsonDiagnostics {
    let consumer = JSONDiagnosticConsumer(stream: &stderr)
    diag.register(consumer)
  } else {
    let consumer = StreamConsumer(files: files, stream: &stderr, colored: isATTY)
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
