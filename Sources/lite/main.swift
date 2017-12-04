import Diagnostics
import Foundation
import LiteSupport
import Symbolic
import CommandLineKit


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
  let testDir =
    StringOption(shortFlag: "d",
                 longFlag: "test-dir",
      helpMessage: "The top-level directory containing tests to run. " +
                   "Defaults to the current working directory.")

  let trillExe = StringOption(longFlag: "trill",
    helpMessage: "The path to the `trill` executable. " +
                 "Defaults to the executable next to `lite`.")

  let cli = CommandLineKit.CommandLine()
  cli.addOptions(testDir, trillExe)

  do {
    try cli.parse()
  } catch {
    cli.printUsage()
    return -1
  }

  var stderr = FileHandle.standardError

  var stderrStream = ColoredANSIStream(&stderr, colored: true)

  let engine = DiagnosticEngine()
  engine.register(StreamConsumer(stream: &stderrStream))

  let trillExeURL =
    trillExe.value.map(URL.init(fileURLWithPath:)) ?? findTrillExecutable()

  guard let url = trillExeURL else {
    engine.add(.error(LiteRunError.couldNotInferPath))
    return -1
  }

  do {
    let allPassed = try runLite(substitutions: [("trill", url.path)],
                                pathExtensions: ["tr", "trill"],
                                testDirPath: testDir.value,
                                testLinePrefix: "//")
    return allPassed ? 0 : -1
  } catch {
    engine.add(.error(error))
    return -1
  }
}

exit(Int32(run()))
