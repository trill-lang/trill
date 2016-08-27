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

enum Mode: Int {
  case emitLLVM, emitAST, emitJavaScript, prettyPrint, jit

  init(_ raw: RawMode) {
    switch raw {
    case EmitLLVM: self = .emitLLVM
    case EmitAST: self = .emitAST
    case PrettyPrint: self = .prettyPrint
    case EmitJavaScript: self = .emitJavaScript
    case JIT: self = .jit
    default: fatalError("invalid mode \(raw)")
    }
  }
}

struct Options {
  let filename: String
  let mode: Mode
  let remainder: [String]
  let importC: Bool
  let emitTiming: Bool
  let optimizationLevel: OptimizationLevel
  
  init(_ raw: RawOptions) {
    self.filename = String(cString: raw.filename)
    self.mode = Mode(raw.mode)
    var strs = [String]()
    for i in 0..<raw.argCount {
      strs.append(String(cString: raw.remainingArgs[i]!))
    }
    self.remainder = strs
    self.importC = raw.importC
    self.emitTiming = raw.emitTiming
    self.optimizationLevel = raw.optimizationLevel
    DestroyRawOptions(raw)
  }
}

var stdout = StandardTextOutputStream()

func populate(driver: Driver, options: Options,
              context: ASTContext,
              str: String) {
  driver.add("Lexing and Parsing") { context in
    let lexer = Lexer(input: str)
    let tokens = try lexer.lex()
    let parser = Parser(tokens: tokens,
                        filename: options.filename,
                        context: context)
    try parser.parseTopLevel(into: context)
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
  
  if case .emitJavaScript = options.mode {
    driver.add("Generating JavaScript") { context in
      return JavaScriptGen(stream: &stdout, context: context).run(in: context)
    }
    return
  }
  
  let gen = IRGenerator(context: context,
                        optimizationLevel: options.optimizationLevel)
  driver.add("LLVM IR Generation", pass: gen.run)
  
  switch options.mode {
  case .emitLLVM:
    driver.add("Serializing LLVM IR") { context in
      let str = try gen.serialize()
      print(str)
    }
  case .jit:
    driver.add("Executing the JIT") { context in
      var args = options.remainder
      args.insert("\(options.filename)", at: 0)
      let ret = try gen.execute(args)
      if ret != 0 {
        context.diag.error("\(options.filename) exited with non-zero exit code \(ret)")
      }
    }
  default: break
  }
}

func main() -> Int32 {
  let options = Options(ParseArguments(CommandLine.argc, CommandLine.unsafeArgv))
  
  var str = ""
  if options.filename == "<stdin>" {
    while let line = readLine() {
      str += line + "\n"
    }
  } else if let s = try? String(contentsOfFile: options.filename) {
    str = s
  } else {
    print("error: unknown file \(options.filename)")
    return 1
  }
  
  let diag = DiagnosticEngine()
  
  let context = ASTContext(filename: options.filename,
                           diagnosticEngine: diag)
  let driver = Driver(context: context)
  populate(driver: driver, options: options, context: context, str: str)
  driver.run(in: context)
  
  
  let isATTY = isatty(STDERR_FILENO) != 0
  let consumer = StreamConsumer(filename: options.filename,
                                lines: str.components(separatedBy: "\n"),
                                stream: &stderr, colored: isATTY)
  diag.register(consumer)
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
  return diag.hasErrors ? 1 : 0
}

exit(main())
