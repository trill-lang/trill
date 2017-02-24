//
//  Decl.swift
//  Trill
//
//  Created by Harlan Haskins on 9/18/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

enum DeclKind {
  case function
  case variable
  case type
  case `extension`
  case `protocol`
  case diagnostic
}

enum DeclModifier: String {
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
