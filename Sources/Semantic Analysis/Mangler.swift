//
//  Mangler.swift
//  Trill
//

import Foundation

extension String {
  var withCount: String {
    return "\(self.characters.count)\(self)"
  }
}

enum GlobalDeclKind {
  case initializer, accessor
}

enum Mangler {
  static func mangle(_ c: ClosureExpr, in d: FuncDecl) -> String {
    return "_WC" + mangle(d, root: false)  // FIXME: number closures.
  }
  
  static func mangle(global decl: VarAssignDecl, kind: GlobalDeclKind) -> String {
    var s = "_W"
    switch kind {
    case .initializer:
      s.append("G")
    case .accessor:
      s.append("g")
    }
    s += decl.name.name.withCount
    return s
  }

  static func mangle(_ t: WitnessTable) -> String {
    var s = "_WW"
    s += t.implementingType.name.name.withCount
    s += t.proto.name.name.withCount
    return s
  }
  
  static func mangle(_ d: FuncDecl, root: Bool = true) -> String {
    if d.has(attribute: .foreign) && !(d is OperatorDecl) {
      return d.name.name
    }
    var s = root ? "_WF" : ""
    switch d {
    case let d as DeinitializerDecl:
      s += "D" + mangle(d.parentType, root: false)
    case let d as InitializerDecl:
      s += "I" + mangle(d.parentType, root: false)
    case let d as PropertyGetterDecl:
      s += "g" + mangle(d.parentType, root: false)
      s += d.propertyName.name.withCount
      s += mangle(d.returnType.type!, root: false)
      return s
    case let d as PropertySetterDecl:
      s += "s" + mangle(d.parentType, root: false)
      s += d.propertyName.name.withCount
      s += mangle(d.args[1].type, root: false)
      return s
    case let d as MethodDecl:
      let sigil = d.has(attribute: .static) ? "m" : "M"
      s += sigil + mangle(d.parentType, root: false)
      s += d.name.name.withCount
    case let d as OperatorDecl:
      s += "O"
      switch d.op {
      case .plus: s += "p"
      case .minus: s += "m"
      case .star: s += "t"
      case .divide: s += "d"
      case .mod: s += "M"
      case .equalTo: s += "e"
      case .notEqualTo: s += "n"
      case .lessThan: s += "l"
      case .lessThanOrEqual: s += "L"
      case .greaterThan: s += "g"
      case .greaterThanOrEqual: s += "G"
      case .and: s += "a"
      case .or: s += "o"
      case .xor: s += "x"
      case .ampersand: s += "A"
      case .bitwiseOr: s += "O"
      case .not: s += "N"
      case .bitwiseNot: s += "B"
      case .leftShift: s += "s"
      case .rightShift: s += "S"
      default: s += "\(d.op)" // this will get caught by Sema
      }
    case let d as SubscriptDecl:
      s += "S" + mangle(d.parentType, root: false)
    default:
      s += d.name.name.withCount
    }
    for arg in d.args where !arg.isImplicitSelf {
      if let external = arg.externalName {
        if external == arg.name {
          s += "S"
        } else {
          s += "E"
          s += external.name.withCount
        }
      }
      s += arg.name.name.withCount
      s += mangle(arg.type, root: false)
    }
    let returnType = d.returnType.type ?? .void
    if returnType != .void && !(d is InitializerDecl) {
      s += "R" + mangle(returnType, root: false)
    }
    return s
  }

  static func mangle(_ proto: ProtocolDecl) -> String {
    return "_WP\(proto.name.name.withCount)"
  }

  static func mangle(_ t: DataType, root: Bool = true) -> String {
    var s = root ? "_WT" : ""
    switch t {
    case .function(let args, let ret):
      s += "F"
      for arg in args {
        s += mangle(arg, root: false)
      }
      s += "R" + mangle(ret, root: false)
    case .tuple(let fields):
      s += "t"
      for field in fields {
        s += mangle(field, root: false)
      }
      s += "T"
    case .array(let field, _):
      s += "A"
      s += mangle(field, root: false)
    case .int(let width, let signed):
      s += "s"
      if width == 64 {
        s += signed ? "I" : "U"
      } else {
        s += (signed ? "i" : "u") + "\(width)"
      }
    case .floating(let type):
      s += "s"
      switch type {
      case .float: s += "f"
      case .double: s += "d"
      case .float80: s += "F"
      }
    case .bool:
      s += "sb"
    case .void:
      s += "sv"
    case .any:
      s += "sa"
    case .pointer:
      let level = t.pointerLevel()
      if level > 0 {
        s += "P\(level)T"
        s += mangle(t.rootType, root: false)
      }
    default:
      s += t.description.withCount
    }
    return s
  }
}
