///
/// String+Escaping.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

extension StringProtocol {
  public func escaped() -> String {
    var s = ""
    for c in self {
      switch c {
      case "\n": s += "\\n"
      case "\t": s += "\\t"
      case "\"": s += "\\\""
      default: s.append(c)
      }
    }
    return s
  }

  public func unescaped() -> String {
    var s = ""
    var nextCharIsEscaped = false
    for c in self {
      if c == "\\" {
        nextCharIsEscaped = true
        continue
      }
      if nextCharIsEscaped {
        switch c {
        case "n": s.append("\n")
        case "t": s.append("\t")
        case "\"": s.append("\"")
        default: s.append(c)
        }
      } else {
        s.append(c)
      }
      nextCharIsEscaped = false
    }
    return s
  }
}
