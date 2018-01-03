import Source
import Diagnostics
import Foundation
import LiteSupport
import Symbolic
import Basic
import Utility

#if os(Linux)
import Glibc
#endif

enum LiteRunError: Error, CustomStringConvertible {
  case couldNotInferPath

  var description: String {
    switch self {
    case .couldNotInferPath: return "unable to infer silt binary path"
    }
  }
}

func run() -> Int {
  let parser =
    ArgumentParser(commandName: "lite",
                   usage: "[-d|-test-dir] [-trill]",
                   overview: "Runs all tests in the provided test directory")
  let testDir =
    parser.add(option: "-test-dir", shortName: "-d", kind: String.self,
               usage: "The top-level directory containing tests to run. " +
                      "Defaults to the current working directory.")

  let trillExe = parser.add(option: "-trill", kind: String.self,
                            usage: "The path to the `trill` executable. " +
                                   "Defaults to the executable next to `lite`.")

  let args: ArgumentParser.Result
  do {
    let commandLineArgs = Array(CommandLine.arguments.dropFirst())
    args = try parser.parse(commandLineArgs)
  } catch {
    parser.printUsage(on: Basic.stdoutStream)
    return -1
  }

  var stderr = FileHandle.standardError

  var stderrStream = ColoredANSIStream(&stderr, colored: true)

  let engine = DiagnosticEngine()
  engine.register(StreamConsumer(stream: &stderrStream,
                                 sourceFileManager: SourceFileManager()))

  let trillExeURL =
    args.get(trillExe).map(URL.init(fileURLWithPath:)) ?? findTrillExecutable()

  guard let url = trillExeURL else {
    engine.add(.error(LiteRunError.couldNotInferPath))
    return -1
  }

  do {
    let allPassed = try runLite(substitutions: [("trill", url.path)],
                                pathExtensions: ["tr", "trill"],
                                testDirPath: args.get(testDir),
                                testLinePrefix: "//",
                                parallelismLevel: .automatic)
    return allPassed ? 0 : -1
  } catch {
    engine.add(.error(error))
    return -1
  }
}

exit(Int32(run()))
