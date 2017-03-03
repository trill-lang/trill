#!/usr/bin/env swift

import Foundation

let fileManager = FileManager.default

var success = true
let examples = try! fileManager.contentsOfDirectory(atPath: "examples")
let stdlib = try! fileManager.contentsOfDirectory(atPath: "stdlib").map { "stdlib/\($0)" }
for example in examples {
  let files: [String]
  if example.hasSuffix(".tr") { files = [example] }
  else if example == "multi-file" {
    files = try! fileManager.contentsOfDirectory(atPath: "examples/\(example)").map { "\(example)/\($0)" }
  }
  else { continue }

  var command = ["-run"]
  var argv = [
    "bf.tr": ["examples/bf.bf"],
    "cat.tr": ["examples/cat.tr", "README.md"],
    "fib.tr": ["11"],
    "same.tr": ["examples/same.tr"],
  ]

  let requiresStdin = ["area.tr", "string.tr"]
  if requiresStdin.contains(example) { command = ["-emit", "ast"] }
  print("running \(example)...")
  let exampleArgs = argv[example].map { ["--args"] + $0 } ?? []
  let args = command + stdlib + files.map { "examples/\($0)" } + exampleArgs
  let process = Process()
  process.launchPath = "build/DerivedData/Trill/Build/Products/Debug/trill"
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
