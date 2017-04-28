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

class VarAssignDecl: Decl {
  let rhs: Expr?
  let name: Identifier
  var typeRef: TypeRefExpr?
  var kind: VarKind
  var mutable: Bool
  init?(name: Identifier,
        typeRef: TypeRefExpr?,
        kind: VarKind = .global,
        rhs: Expr? = nil,
        modifiers: [DeclModifier] = [],
        mutable: Bool = true,
        sourceRange: SourceRange? = nil) {
    guard rhs != nil || typeRef != nil else { return nil }
    self.rhs = rhs
    self.typeRef = typeRef
    self.mutable = mutable
    self.name = name
    self.kind = kind
    super.init(type: typeRef?.type ?? .void,
               modifiers: modifiers,
               sourceRange: sourceRange)
  }

  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["type"] = typeRef?.type.description
    superAttrs["name"] = name.name
    superAttrs["kind"] = {
      switch kind {
      case .local: return "local"
      case .global: return "global"
      case .implicitSelf: return "implicit_self"
      case .property: return "property"
      }
    }()
    superAttrs["mutable"] = mutable
    return superAttrs
  }
}
