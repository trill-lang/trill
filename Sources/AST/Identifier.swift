///
/// Identifier.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Source

public struct Identifier: CustomStringConvertible, ExpressibleByStringLiteral,
                          Equatable, Hashable {
  public let name: String
  public let range: SourceRange?

  public init(name: String, range: SourceRange? = nil) {
    self.name = name
    self.range = range
  }

  public init(stringLiteral value: String) {
    name = value
    range = nil
  }

  public init(unicodeScalarLiteral value: UnicodeScalarType) {
    name = value
    range = nil
  }

  public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterType) {
    name = value
    range = nil
  }

  public var hashValue: Int {
    return name.hashValue ^ 0x23423454
  }

  public var description: String {
    return name
  }
}

public func ==(lhs: Identifier, rhs: Identifier) -> Bool {
  return lhs.name == rhs.name
}
