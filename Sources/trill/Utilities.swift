///
/// Utilities.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

func format(time: Double) -> String {
  var time = time
  let unit: String
  let formatter = NumberFormatter()
  formatter.maximumFractionDigits = 3
  if time > 1.0 {
    unit = "s"
  } else if time > 0.001 {
    unit = "ms"
    time *= 1_000
  } else if time > 0.000_001 {
    unit = "µs"
    time *= 1_000_000
  } else {
    unit = "ns"
    time *= 1_000_000_000
  }
  return formatter.string(from: NSNumber(value: time))! + unit
}

extension Array where Element: Hashable {
    func unique() -> Array<Element> {
        var uniqued = Array<Element>()
        var set = Set<Element>()
        for item in self {
            if set.insert(item).inserted { uniqued.append(item) }
        }
        return uniqued
    }
}

let ansiEscapeSupportedOnStdErr: Bool = {
    guard isatty(STDERR_FILENO) != 0 else {
        return false
    }

    #if os(macOS)
    if let xpcServiceName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] {
        return !xpcServiceName.hasPrefix("com.apple.dt.Xcode")
    }
    #endif

    return true
}()

extension FileManager {
  func recursiveChildren(of path: String) -> [String]? {
    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    guard let enumerator = enumerator(at: url, includingPropertiesForKeys: nil) else {
      return nil
    }
    return enumerator.map { ($0 as! URL).path }
  }
}
