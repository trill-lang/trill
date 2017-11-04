///
/// SourceLocation.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

public struct SourceLocation: CustomStringConvertible {
  public let file: SourceFile
  public var line: Int
  public var column: Int
  public var charOffset: Int

  public init(line: Int, column: Int, file: SourceFile, charOffset: Int = 0) {
    self.file = file
    self.line = line
    self.column = column
    self.charOffset = charOffset
  }

  public var description: String {
    let basename = file.path.basename
    return "<\(basename):\(line):\(column)>"
  }
}

extension SourceLocation: Comparable {}
public func ==(lhs: SourceLocation, rhs: SourceLocation) -> Bool {
  guard lhs.file == rhs.file else { return false }
  if lhs.charOffset == rhs.charOffset { return true }
  return lhs.line == rhs.line && lhs.column == rhs.column
}

public func <(lhs: SourceLocation, rhs: SourceLocation) -> Bool {
  precondition(lhs.file == rhs.file, "only SourceLocations from the same file are ordered")

  if lhs.charOffset != rhs.charOffset { return lhs.charOffset < rhs.charOffset }
  if lhs.line != rhs.line { return lhs.line < rhs.line }
  return lhs.column < rhs.column
}

public struct SourceRange {
  public let start: SourceLocation
  public let end: SourceLocation

  public init(start: SourceLocation, end: SourceLocation) {
    assert(start.file == end.file, "a SourceRange must contain locations from the same file")
    assert(start <= end, "a SourceRange must have start <= end")

    self.start = start
    self.end = end
  }
}

extension SourceRange: Equatable {
  public static func ==(lhs: SourceRange, rhs: SourceRange) -> Bool {
    return lhs.start == rhs.start && lhs.end == rhs.end
  }
}

extension SourceRange {
  private var contents: String { return start.file.contents }

  public var length: Int {
    return end.charOffset - start.charOffset
  }

  public var source: String {
    let startIndex = contents.index(contents.startIndex, offsetBy: start.charOffset)
    let endIndex = contents.index(startIndex, offsetBy: length)
    return String(contents[startIndex...endIndex])
  }
}
