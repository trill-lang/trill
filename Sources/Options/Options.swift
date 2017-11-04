///
/// Options.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation
import CommandLineKit

public enum OptimizationLevel: String {
  case none = "0"
  case less = "1"
  case `default` = "2"
  case aggressive = "3"
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
    let cli = CommandLineKit.CommandLine()
    let help = BoolOption(shortFlag: "h", longFlag: "help",
                          helpMessage: "Prints a help message.")
    let targetTriple = StringOption(longFlag: "target",
          helpMessage: "Override the target triple for cross-compilation.")
    let outputFilename = StringOption(shortFlag: "o", longFlag: "output-file",
          helpMessage: "The file to write the resulting output to.")
    let noImportC = BoolOption(longFlag: "no-import",
          helpMessage: "Disable importing C declarations.")
    let emitTiming = BoolOption(longFlag: "debug-print-timing",
          helpMessage: "Print times for each pass (for debugging).")
    let jsonDiagnostics = BoolOption(longFlag: "json-diagnostics",
          helpMessage: "Emit diagnostics as JSON instead of strings.")
    let parseOnly = BoolOption(longFlag: "parse-only",
          helpMessage: "Only parse the input file(s); do not typecheck.")
    let showImports = BoolOption(longFlag: "show-imports",
          helpMessage: "Whether to show imported declarations in AST dumps.")
    let noStdlib = BoolOption(longFlag: "no-stdlib",
          helpMessage: "Do not compile the standard library.")
    let jitArgs = MultiStringOption(longFlag: "args",
          helpMessage: "The arguments to pass to the JIT.")
    let linkerFlags = MultiStringOption(longFlag: "Xlinker",
          helpMessage: "Flags to pass to the linker when linking.")
    let clangFlags = MultiStringOption(longFlag: "Xclang",
          helpMessage: "Flags to pass to clang.")

    let optimizationLevel = EnumOption<OptimizationLevel>(shortFlag: "O",
          helpMessage: "The optimization level to apply to the program.")

    let outputFormat = EnumOption<OutputFormat>(longFlag: "emit",
          helpMessage: "The kind of file to emit. Defaults to binary.")
    let jit = BoolOption(longFlag: "run",
          helpMessage: "JIT the specified files.")
    let onlyDiagnostics = BoolOption(longFlag: "only-diagnostics",
          helpMessage: "Only print diagnostics, no other output.")

    cli.addOptions(help, targetTriple, outputFilename, noImportC, emitTiming,
                   jsonDiagnostics, parseOnly, showImports, noStdlib,
                   optimizationLevel, jitArgs, linkerFlags, clangFlags,
                   outputFormat, jit, onlyDiagnostics)
    do {
      try cli.parse()
      if help.value {
        cli.printUsage()
        exit(0)
      }
    } catch {
      cli.printUsage(error)
      exit(-1)
    }

    let mode: Mode
    if let format = outputFormat.value {
      mode = .emit(format)
    } else if jit.value {
      mode = .jit
    } else if onlyDiagnostics.value {
      mode = .onlyDiagnostics
    } else {
      mode = .emit(.binary)
    }

    return Options(filenames: cli.unparsedArguments,
                   targetTriple: targetTriple.value,
                   outputFilename: outputFilename.value,
                   mode: mode,
                   importC: !noImportC.value,
                   emitTiming: emitTiming.value,
                   jsonDiagnostics: jsonDiagnostics.value,
                   parseOnly: parseOnly.value,
                   showImports: showImports.value,
                   includeStdlib: !noStdlib.value,
                   optimizationLevel: optimizationLevel.value ?? .none,
                   jitArgs: jitArgs.value ?? [],
                   linkerFlags: linkerFlags.value ?? [],
                   clangFlags: clangFlags.value ?? [])
  }
}
