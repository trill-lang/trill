//
//  SourceLocation.swift
//  Trill
//

struct SourceLocation: CustomStringConvertible {
  let file: String?
  var line: Int
  var column: Int
  var charOffset: Int
  init(line: Int, column: Int, file: String? = nil, charOffset: Int = 0) {
    self.file = file
    self.line = line
    self.column = column
    self.charOffset = charOffset
  }
  var description: String {
    return "<line: \(line), col: \(column)>"
  }
  static let zero = SourceLocation(line: 0, column: 0)
}

extension SourceLocation: Comparable {}
func ==(lhs: SourceLocation, rhs: SourceLocation) -> Bool {
  if lhs.charOffset == rhs.charOffset { return true }
  return lhs.line == rhs.line && lhs.column == rhs.column
}

func <(lhs: SourceLocation, rhs: SourceLocation) -> Bool {
  if lhs.charOffset < rhs.charOffset { return true }
  if lhs.line < rhs.line { return true }
  return lhs.column < rhs.column
}

struct SourceRange {
  let start: SourceLocation
  let end: SourceLocation
  
  static let zero = SourceRange(start: .zero, end: .zero)
}
