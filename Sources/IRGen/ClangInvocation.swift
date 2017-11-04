//
//  ClangInvocation.swift
//  trill
//
//  Created by Harlan Haskins on 7/30/17.
//

import Foundation

public struct RunResult {
  let stdoutData: Data
  let stderrData: Data
  let exitStatus: Int

  var stdout: String { return String(data: stdoutData, encoding: .utf8)! }
  var stderr: String { return String(data: stderrData, encoding: .utf8)! }

  var wasSuccessful: Bool {
    return exitStatus == 0
  }
}

@discardableResult
private func run(_ path: URL, arguments: [String] = [],
                 workingDirectory: URL? = nil,
                 input: String? = nil) -> RunResult {
  let outPipe = Pipe()
  let errPipe = Pipe()
  let process = Process()
  process.launchPath = path.path
  process.arguments = arguments
  process.standardOutput = outPipe
  process.standardError = errPipe
  if let input = input {
    let inputPipe = Pipe()
    process.standardInput = inputPipe
    inputPipe.fileHandleForWriting.write(input)
  }
  if let dir = workingDirectory {
    process.currentDirectoryPath = dir.path
  }
  process.launch()
  process.waitUntilExit()
  let stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
  let stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
  return RunResult(stdoutData: stdout, stderrData: stderr,
                   exitStatus: Int(process.terminationStatus))
}

private func which(_ exeName: String) -> URL? {
  let whichURL = URL(fileURLWithPath: "/usr/bin/which")
  let result = run(whichURL, arguments: [exeName])
  guard result.wasSuccessful else { return nil }
  let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  return URL(fileURLWithPath: path)
}

/// Represents an invocation of Clang with whatever arguments you'd like.
public struct ClangInvocation {
  enum Error: Swift.Error {
    case couldNotFindClang
  }
  let clangPath: URL

  static func findClang() -> URL? {
    return which("clang")
  }

  public func invoke(_ arguments: [String], linkerFlags: [String]) {
    var args = arguments
    for flag in linkerFlags {
      args.append(contentsOf: ["-Xlinker", flag])
    }
    run(clangPath, arguments: args)
  }

  /// Creates an invocation with the provided path to clang. If no path is
  /// provided, this will look into your PATH to find Clang.
  init(path: URL? = nil) throws {
    guard let clangPath = path ?? ClangInvocation.findClang() else {
      throw Error.couldNotFindClang
    }
    self.clangPath = clangPath
  }
}
