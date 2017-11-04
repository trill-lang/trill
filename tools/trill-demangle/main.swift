///
/// main.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation
import trillRuntime

func demangle(_ symbol: String) -> String? {
  return symbol.withCString { cStr -> String? in
    guard let demangled = trill_demangle(cStr) else {
      return nil
    }
    defer { free(demangled) }
    return String(cString: demangled)
  }
}

func demangleArgs() {
  for arg in CommandLine.arguments.dropFirst() {
    if let demangled = demangle(arg) {
      print("\(arg) --> \(demangled)")
    } else {
      print("could not demangle \(arg)")
    }
  }
}

class DemangleRegex: NSRegularExpression {
  convenience init() {
    try! self.init(pattern: "_?_W\\w+", options: [])
  }
  override func replacementString(for result: NSTextCheckingResult,
                                  in string: String,
                                  offset: Int,
                                  template templ: String) -> String {
    let res = result.adjustingRanges(offset: offset)
    let start = string.characters.index(string.startIndex, offsetBy: res.range.location)
    let end = string.characters.index(start, offsetBy: res.range.length)
    let symbol = String(string[start..<end])
    return demangle(symbol) ?? symbol
  }
}

func demangleStdin() {
  let r = DemangleRegex()
  while let line = readLine() {
    let string = (line as NSString).mutableCopy() as! NSMutableString
    r.replaceMatches(in: string,
                     options: [],
                     range: NSRange(location: 0, length: string.length),
                     withTemplate: "")
    print(string)
  }
}

if CommandLine.argc > 1 {
  demangleArgs()
} else {
  demangleStdin()
}
