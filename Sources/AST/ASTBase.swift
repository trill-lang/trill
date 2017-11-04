///
/// ASTBase.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation
import Source

public class ASTNode: Equatable, Hashable {
  public let sourceRange: SourceRange?
  public init(sourceRange: SourceRange? = nil) {
    self.sourceRange = sourceRange
  }
  public var startLoc: SourceLocation? { return sourceRange?.start }
  public var endLoc: SourceLocation? { return sourceRange?.end }

  public var hashValue: Int {
    return ObjectIdentifier(self).hashValue ^ 0x2a0294ba
  }

  public static func ==(lhs: ASTNode, rhs: ASTNode) -> Bool {
    return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  public func attributes() -> [String: Any] {
    return [:]
  }
}
