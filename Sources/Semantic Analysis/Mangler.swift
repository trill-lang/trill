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

enum Mangler {
  static func mangle(_ c: ClosureExpr, in d: FuncDecl) -> String {
    return "_WC" + mangle(d, root: false)  // FIXME: number closures.
  }
  static func mangle(_ d: FuncDecl, root: Bool = true) -> String {
    if d.has(attribute: .foreign) {
      return d.name.name
    }
    var s = root ? "_WF" : ""
    if case .deinitializer(let type) = d.kind {
      s += "D" + mangle(type, root: false)
    } else {
      switch d.kind {
      case .initializer(let type):
        s += "I" + mangle(type, root: false)
      case .method(let type):
        s += "M" + mangle(type, root: false)
        s += d.name.name.withCount
      case .operator(let op):
        s += "O" // FIXME: Full support for mangling all operators
        switch op {
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
        default: s += "\(op)" // this will get caught by Sema
        }
      case .subscript(let type):
        s += "S" + mangle(type, root: false)
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
      s += "_"
      let returnType = d.returnType.type ?? .void
      if returnType != .void {
        s += "R" + mangle(returnType, root: false)
      }
    }
    return s
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
