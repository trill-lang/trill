///
/// SourceFileManager.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Dispatch

public final class SourceFileManager {
  private let cacheQueue = DispatchQueue(label: "SourceFileManager")
  private var contentsCache = [SourceFile: String]()
  private var linesCache = [SourceFile: [String]]()

  public init() {}

  public func contents(of file: SourceFile) throws -> String {
    return try cacheQueue.sync {
      if let contents = contentsCache[file] { return contents }
      let contents = try fetchContents(file: file)
      contentsCache[file] = contents
      return contents
    }
  }

  public func lines(in file: SourceFile) throws -> [String] {
    let contents = try self.contents(of: file)
    return cacheQueue.sync {
      if let lines = linesCache[file] { return lines }
      let lines = contents.components(separatedBy: .newlines)
      linesCache[file] = lines
      return lines
    }
  }

  private func fetchContents(file: SourceFile) throws -> String {
    switch file.path {
    case .stdin:
      var str = ""
      while let line = readLine() {
        str += line
      }
      return str
    case .input(_, let contents):
      return contents
    case .file(let url):
      return try String(contentsOf: url)
    case .none:
      return ""
    }
  }
}
