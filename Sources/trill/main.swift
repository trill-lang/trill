///
/// main.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import ClangImporter
import Diagnostics
import Driver
import Foundation
import IRGen
import Options

// FIXME: Don't rely on LLVM's argument parser
import LLVMWrappers

import Parse
import Runtime
import Sema
import Source

var stderr = FileHandle.standardError
var stdout = FileHandle.standardOutput

func populate(driver: Driver, options: Options,
              sourceFiles: [SourceFile],
              isATTY: Bool,
              context: ASTContext) throws {
  let runtimeLocation = try RuntimeLocator.findRuntime(forAddress: #dsohandle)
  var stderrStream = ColoredANSIStream(&stderr, colored: isATTY)
  let fatalErrorConsumer = StreamConsumer(stream: &stderrStream)
  let gen = try IRGenerator(context: context, options: options,
                            runtimeLocation: runtimeLocation,
                            fatalErrorConsumer: fatalErrorConsumer)
  driver.add("Lexing and Parsing") { context in
    lexAndParse(sourceFiles: sourceFiles, into: context)
  }

  if options.importC {
    driver.add("Clang Importer") { context in
      return ClangImporter(context: context,
                           target: gen.targetMachine.triple,
                           runtimeLocation: runtimeLocation).run(in: context)
    }
  }

  if options.includeStdlib {
    driver.add("Parsing Standard Library") { context in
      let stdlibContext = StdLibASTContext(diagnosticEngine: context.diag)
      let stdlibPath = runtimeLocation.stdlib.path
      let allStdlibFiles = FileManager.default.recursiveChildren(of: stdlibPath)!
      let stdlibFiles = allStdlibFiles.filter {  $0.hasSuffix(".tr") }
      let stdlibSourceFiles = try _sourceFiles(from: stdlibFiles, context: context)
      lexAndParse(sourceFiles: stdlibSourceFiles, into: stdlibContext)
      context.stdlib = stdlibContext
      context.merge(stdlibContext)
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

  driver.add("LLVM IR Generation", pass: gen.run)

  switch options.mode {
  case .emit(let outputType):
    driver.add("Serializing \(outputType)") { context in
      try gen.emit(outputType, output: options.outputFilename)
    }
    break
  case .jit:
    driver.add("Executing the JIT") { context in
      var args = options.jitArgs
      args.insert("\(options.filenames.first ?? "<>")", at: 0)
      let ret = try gen.execute(args)
      if ret != 0 {
        context.diag.error("program exited with non-zero exit code \(ret)")
      }
    }
  default: break
  }
}

func sourceFiles(options: Options, context: ASTContext) throws -> [SourceFile] {
  if options.isStdin {
    let file = try SourceFile(path: .stdin, sourceFileManager: context.sourceFileManager)
    return [file]
  } else {
    return try _sourceFiles(from: options.filenames, context: context)
  }
}

func _sourceFiles(from filenames: [String], context: ASTContext) throws -> [SourceFile] {
  return try filenames.map { path in
    let url = URL(fileURLWithPath: path)
    return try SourceFile(path: .file(url), sourceFileManager: context.sourceFileManager)
  }
}

func lexAndParse(sourceFiles: [SourceFile], into context: ASTContext) {
  if sourceFiles.count == 1 {
    context.add(sourceFiles[0])
    Parser.parse(sourceFiles[0], into: context)
    return
  }

  let mergeQueue = DispatchQueue(label: "source-file-merge")
  var contexts = [ASTContext]()
  func add(_ context: ASTContext) {
    mergeQueue.sync {
      contexts.append(context)
    }
  }
  let group = DispatchGroup()
  for file in sourceFiles {
    DispatchQueue.global().async(group: group) {
      let newCtx = ASTContext(diagnosticEngine: context.diag)
      newCtx.add(file)
      Parser.parse(file, into: context)
      add(newCtx)
    }
  }
  group.wait()
  for newContext in contexts {
    context.merge(newContext)
  }
}

func performCompile(diag: DiagnosticEngine, options: Options) {
  let context = ASTContext(diagnosticEngine: diag)
  let driver = Driver(context: context)

  if options.jsonDiagnostics {
    let consumer = JSONDiagnosticConsumer(stream: &stderr)
    diag.register(consumer)
  } else {
    var stream = ColoredANSIStream(&stderr, colored: ansiEscapeSupportedOnStdErr)
    let consumer = StreamConsumer(stream: &stream)
    diag.register(consumer)
  }

  if options.filenames.isEmpty {
    diag.error("no input files provided")
    return
  }

  var files = [SourceFile]()
  do {
    files = try sourceFiles(options: options, context: context)

    try populate(driver: driver,
                 options: options,
                 sourceFiles: files,
                 isATTY: ansiEscapeSupportedOnStdErr,
                 context: context)
    driver.run(in: context)
  } catch {
    diag.error(error)
  }

  if options.emitTiming {
    var passColumn = Column(title: "Pass Title")
    var timeColumn = Column(title: "Time")
    for (title, time) in driver.timings {
      passColumn.rows.append(title)
      timeColumn.rows.append(format(time: time))
    }
    TableFormatter(columns: [passColumn, timeColumn]).write(to: &stderr)
  }
}

func main() -> Int32 {
  let diag = DiagnosticEngine()

  do {
    let options = try Options.parseCommandLine()
    performCompile(diag: diag, options: options)
  } catch {
    diag.error(error)
  }

  diag.consumeDiagnostics()

  return diag.hasErrors ? -1 : 0
}

exit(main())
