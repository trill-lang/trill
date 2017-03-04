#!/usr/bin/env swift

import Foundation

let fileManager = FileManager.default
let trillExecutable: String
let examplesDir: String
let stdlibDir: String
if CommandLine.arguments.count == 4 {
  trillExecutable = CommandLine.arguments[1]
  examplesDir = CommandLine.arguments[2]
  stdlibDir = CommandLine.arguments[3]
} else {
  trillExecutable = "build/DerivedData/Trill/Build/Products/Debug/trill"
  examplesDir = "examples"
  stdlibDir = "stdlib"
}

var success = true
let examples = try! fileManager.contentsOfDirectory(atPath: examplesDir)
let stdlib = try! fileManager.contentsOfDirectory(atPath: stdlibDir).map { "\(stdlibDir)/\($0)" }
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
    "cat.tr": ["\(examplesDir)/cat.tr", "\(stdlibDir)/String.tr"],
    "fib.tr": ["11"],
    "same.tr": ["\(examplesDir)/same.tr"],
  ]

  let requiresStdin = ["area.tr", "string.tr"]
  if requiresStdin.contains(example) { command = ["-emit", "ast"] }
  print("running \(example)...")
  let exampleArgs = argv[example].map { ["--args"] + $0 } ?? []
  let args = command + stdlib + files.map { "\(examplesDir)/\($0)" } + exampleArgs
  let process = Process()
  process.launchPath = trillExecutable
  process.arguments = args
  process.standardOutput = nil
  process.launch()
  process.waitUntilExit()
  if process.terminationStatus != 0 {
    success = false
    print("\n\nrunning \(example) failed\n\n")
  }
}

exit(success ? 0 : 1)
