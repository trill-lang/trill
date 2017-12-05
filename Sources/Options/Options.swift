///
/// Options.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation
import Basic
import Utility

public enum OptimizationLevel: String, ArgumentKind {
  case none = "0"
  case less = "1"
  case `default` = "2"
  case aggressive = "3"

  public init(argument: String) throws {
    guard let level = OptimizationLevel(rawValue: argument) else {
      throw ArgumentParserError.invalidValue(argument: argument,
                                             error: .unknown(value: argument))
    }
    self = level
  }

  public static var completion: ShellCompletion {
    return ShellCompletion.values([
      (value: "O0", description: "Perform no optimizations."),
      (value: "O1", description: "Perform a small set of optimizations."),
      (value: "O2", description: "Perform the default set of optimizations."),
      (value: "O3", description: "Perform aggressive optimizations.")
    ])
  }
}

public struct Options {
  public let filenames: [String]
  public let targetTriple: String?
  public let outputFilename: String?
  public let mode: Mode
  public let importC: Bool
  public let emitTiming: Bool
  public let jsonDiagnostics: Bool
  public let parseOnly: Bool
  public let showImports: Bool
  public let includeStdlib: Bool
  public let optimizationLevel: OptimizationLevel
  public let jitArgs: [String]
  public let linkerFlags: [String]
  public let clangFlags: [String]

  public var isStdin: Bool {
    return filenames.count == 1 && filenames[0] == "-"
  }

  public static func parseCommandLine() throws -> Options {
    let parser = ArgumentParser(commandName: "trill",
                                usage: "[options] <input-files>",
                                overview: "")
    let help =
      parser.add(option: "-help", shortName: "-h", kind: Bool.self,
                 usage: "Prints this help message.")
    let targetTriple =
      parser.add(option: "-target", kind: String.self,
                 usage: "Override the target triple for cross-compilation.")
    let outputFilename =
      parser.add(option: "-output-file", shortName: "-o", kind: String.self,
                 usage: "The file to write the resulting output to.")
    let noImportC =
      parser.add(option: "-no-import", kind: Bool.self,
                 usage: "Disable importing C declarations.")
    let emitTiming =
      parser.add(option: "-debug-print-timing", kind: Bool.self,
                 usage: "Print times for each pass (for debugging).")
    let jsonDiagnostics =
      parser.add(option: "-json-diagnostics",
                 kind: Bool.self,
                 usage: "Emit diagnostics as JSON instead of strings.")
    let parseOnly =
      parser.add(option: "-parse-only", kind: Bool.self,
                 usage: "Only parse the input file(s); do not typecheck.")
    let showImports =
      parser.add(option: "-show-imports", kind: Bool.self,
                 usage: "Whether to show imported declarations in AST dumps.")
    let noStdlib =
      parser.add(option: "-no-stdlib", kind: Bool.self,
                 usage: "Do not compile the standard library.")
    let linkerFlags =
      parser.add(option: "-Xlinker", kind: [String].self, strategy: .oneByOne,
                 usage: "Flags to pass to the linker when linking.")
    let clangFlags =
      parser.add(option: "-Xclang", kind: [String].self,
                 strategy: .oneByOne, usage: "Flags to pass to clang.")
    let optimizationLevel =
      parser.add(option: "-O", kind: OptimizationLevel.self,
                 usage: "The optimization level to apply to the program.")
    let outputFormat =
      parser.add(option: "-emit", kind: OutputFormat.self,
                 usage: "The kind of file to emit. Defaults to binary.")
    let onlyDiagnostics =
      parser.add(option: "-only-diagnostics", kind: Bool.self,
                 usage: "Only print diagnostics, no other output.")
    let files =
      parser.add(positional: "", kind: [String].self)

    let jit = parser.add(option: "-run", kind: Bool.self,
                         usage: "JIT the specified files.")
    let jitArgs = parser.add(option: "-args", kind: [String].self,
                             strategy: .remaining)

    let args: ArgumentParser.Result

    do {
      let commandLineArgs = Array(CommandLine.arguments.dropFirst())
      args = try parser.parse(commandLineArgs)
      if args.get(help) != nil {
        parser.printUsage(on: Basic.stdoutStream)
        exit(0)
      }
    } catch {
      parser.printUsage(on: Basic.stdoutStream)
      exit(-1)
    }

    let mode: Mode
    if let format = args.get(outputFormat) {
      mode = .emit(format)
    } else if args.get(jit) != nil {
      mode = .jit
    } else if args.get(onlyDiagnostics) != nil {
      mode = .onlyDiagnostics
    } else {
      mode = .emit(.binary)
    }

    return Options(filenames: args.get(files) ?? [],
                   targetTriple: args.get(targetTriple),
                   outputFilename: args.get(outputFilename),
                   mode: mode,
                   importC: !(args.get(noImportC) ?? false),
                   emitTiming: args.get(emitTiming) ?? false,
                   jsonDiagnostics: args.get(jsonDiagnostics) ?? false,
                   parseOnly: args.get(parseOnly) ?? false,
                   showImports: args.get(showImports) ?? false,
                   includeStdlib: !(args.get(noStdlib) ?? false),
                   optimizationLevel: args.get(optimizationLevel) ?? .none,
                   jitArgs: args.get(jitArgs) ?? [],
                   linkerFlags: args.get(linkerFlags) ?? [],
                   clangFlags: args.get(clangFlags) ?? [])
  }
}
