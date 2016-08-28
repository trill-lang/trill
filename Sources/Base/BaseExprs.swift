//
//  Exp.swift
//  Trill
//

import Foundation

enum DeclKind {
  case function
  case variable
  case type
  case `extension`
  case diagnostic
}

enum DeclAttribute: String {
  case foreign = "foreign"
  case `static` = "static"
  case mutating = "mutating"
  case indirect = "indirect"
  case noreturn = "noreturn"
  case implicit = "implicit"
  var description: String {
    return self.rawValue
  }
  
  func isValid(on kind: DeclKind) -> Bool {
    switch (self, kind) {
    case (.foreign, .function),
         (.static, .function),
         (.mutating, .function),
         (.noreturn, .function),
         (.indirect, .type),
         (.implicit, .function),
         (.implicit, .type),
         (.implicit, .variable),
         (.foreign, .type),
         (.foreign, .variable):
      return true
    default:
      return false
    }
  }
}

struct SourceLocation: CustomStringConvertible {
  var line: Int
  var column: Int
  var charOffset: Int
  init(line: Int, column: Int, charOffset: Int = 0) {
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

struct Identifier: CustomStringConvertible, ExpressibleByStringLiteral, Equatable, Hashable {
  let name: String
  let range: SourceRange?
  
  init(name: String, range: SourceRange? = nil) {
    self.name = name
    self.range = range
  }
  
  init(stringLiteral value: String) {
    name = value
    range = nil
  }
  
  init(unicodeScalarLiteral value: UnicodeScalarType) {
    name = value
    range = nil
  }
  
  init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterType) {
    name = value
    range = nil
  }
  
  var hashValue: Int {
    return name.hashValue ^ 0x23423454
  }
  
  var description: String {
    return name
  }
}

func ==(lhs: Identifier, rhs: Identifier) -> Bool {
  return lhs.name == rhs.name
}

class ASTNode: Equatable, Hashable {
  let sourceRange: SourceRange?
  init(sourceRange: SourceRange? = nil) {
    self.sourceRange = sourceRange
  }
  func startLoc() -> SourceLocation? { return sourceRange?.start }
  func endLoc() -> SourceLocation? { return sourceRange?.end }
  func equals(_ rhs: ASTNode) -> Bool {
    return false
  }
  
  
  var hashValue: Int {
    return ObjectIdentifier(self).hashValue ^ 0x2a0294ba
  }
}

func ==(lhs: ASTNode, rhs: ASTNode) -> Bool {
  return lhs.equals(rhs)
}
