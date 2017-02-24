//
//  Exp.swift
//  Trill
//

import Foundation

class ASTNode: Equatable, Hashable {
  let sourceRange: SourceRange?
  init(sourceRange: SourceRange? = nil) {
    self.sourceRange = sourceRange
  }
  var startLoc: SourceLocation? { return sourceRange?.start }
  var endLoc: SourceLocation? { return sourceRange?.end }
  
  var hashValue: Int {
    return ObjectIdentifier(self).hashValue ^ 0x2a0294ba
  }

  static func ==(lhs: ASTNode, rhs: ASTNode) -> Bool {
    return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }
    
  func attributes() -> [String: Any] {
    return [:]
  }
}
