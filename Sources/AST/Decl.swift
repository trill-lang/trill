///
/// Decl.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Source

public enum DeclKind {
  case function
  case variable
  case type
  case `extension`
  case `protocol`
  case diagnostic
}

public enum DeclModifier: String {
  case foreign = "foreign"
  case `static` = "static"
  case mutating = "mutating"
  case indirect = "indirect"
  case noreturn = "noreturn"
  case implicit = "implicit"
  public var description: String {
    return self.rawValue
  }

  public func isValid(on kind: DeclKind) -> Bool {
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
