///
/// run-examples.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    write(string.data(using: .utf8)!)
  }
}

func error(_ message: String) -> Never {
  var stderr = FileHandle.standardError
  print("error: \(message)", to: &stderr)
  exit(-1)
}

func usage() -> Never {
  error("usage: run-examples [trill-executable] [examples-dir]")
}

func getExecutable() -> (executable: String, examplesDir: String) {
  guard CommandLine.arguments.count == 3 else {
    usage()
  }
  return (executable: CommandLine.arguments[1],
          examplesDir: CommandLine.arguments[2])
}

func main() throws -> Int {
  let fileManager = FileManager.default
  let (trillExecutable, examplesDir) = getExecutable()

  var allSuccessful = true
  let examples = try! fileManager.contentsOfDirectory(atPath: examplesDir)
  for example in examples {
    let files: [String]
    if example.hasSuffix(".tr") { files = [example] }
    else if example == "multi-file" {
      files = try! fileManager.contentsOfDirectory(atPath: "\(examplesDir)/\(example)").map { "\(example)/\($0)" }
    }
    else { continue }

    var command = ["-run"]
    var argv = [
      "bf.tr": ["\(examplesDir)/bf.bf"],
      "cat.tr": ["\(examplesDir)/cat.tr", "\(examplesDir)/bf.bf"],
      "fib.tr": ["11"],
      "same.tr": ["\(examplesDir)/same.tr"],
    ]

    let requiresStdin = ["area.tr", "string.tr"]
    if requiresStdin.contains(example) { command = ["-emit", "ast"] }
    print("running \(example)...")
    let exampleArgs = argv[example].map { ["--args"] + $0 } ?? []
    let args = command + files.map { "\(examplesDir)/\($0)" } + exampleArgs
    let process = Process()
    process.launchPath = trillExecutable
    process.arguments = args
    process.standardOutput = nil
    process.launch()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
      allSuccessful = false
      print("\n\nrunning \(example) failed\n\n")
    }
  }
  return allSuccessful ? 0 : 1
}


do {
  exit(Int32(try main()))
} catch let err {
  error("\(err)")
}
