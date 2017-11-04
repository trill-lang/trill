///
/// SourceFile.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

public enum SourceFileType: Equatable, Hashable {
  public var hashValue: Int {
    switch self {
    case .input(let url, _):
      return url.hashValue ^ 0x4324
    case .file(let url):
      return url.hashValue ^ 0x33345
    case .stdin:
      return 0x314159
    case .none:
      return 0xE271
    }
  }

  public static func ==(lhs: SourceFileType, rhs: SourceFileType) -> Bool {
    switch (lhs, rhs) {
    case (.input(let lhsURL, _), .input(let rhsURL, _)),
         (.file(let lhsURL), .file(let rhsURL)):
      return lhsURL == rhsURL
    case (.stdin, .stdin):
      return true
    case (.none, .none):
      return true
    default:
      return false
    }
  }

  case input(url: URL, contents: String)
  case file(URL)
  case stdin
  case none
  
  public var basename: String {
    switch self {
    case .file(let url), .input(let url, _):
      return url.lastPathComponent
    case .stdin, .none:
      return filename
    }
  }
  
  public var filename: String {
    switch self {
    case .file(let url), .input(let url, _):
      return url.path
    case .stdin:
      return "<stdin>"
    case .none:
      return "<none>"
    }
  }
}

public struct SourceFile: Equatable, Hashable {
  public static func ==(lhs: SourceFile, rhs: SourceFile) -> Bool {
    return lhs.path == rhs.path
  }

  public var hashValue: Int { return path.hashValue ^ 0x35 }

  public let path: SourceFileType
  internal unowned let sourceFileManager: SourceFileManager
  public var contents: String { return try! sourceFileManager.contents(of: self) }
  public var lines: [String] { return try! sourceFileManager.lines(in: self) }
  
  public init(path: SourceFileType, sourceFileManager: SourceFileManager) throws {
    self.path = path
    self.sourceFileManager = sourceFileManager
  }
}

extension SourceFile {
  public var start: SourceLocation {
    return SourceLocation(line: 1, column: 1, file: self, charOffset: 0)
  }
}
