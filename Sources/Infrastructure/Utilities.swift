//
//  Utilities.swift
//  Trill
//

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

func indent(_ n: Int) -> String {
  return String(repeating: " ", count: n)
}

extension String {
    func splitCapitals() -> [String] {
        var s = ""
        var words = [String]()
        for char in unicodeScalars {
            if isupper(Int32(char.value)) != 0 && !s.isEmpty {
                words.append(s)
                s = ""
            }
            s.append(String(char))
        }
        if !s.isEmpty {
            words.append(s)
        }
        return words
    }
    func snakeCase() -> String {
        return splitCapitals().map { $0.lowercased() }.joined(separator: "_")
    }
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

    subscript(safe index: Int) -> Element? {
      guard index < count, index >= 0 else { return nil }
      return self[index]
    }
}

let ansiEscapeSupportedOnStdErr: Bool = {
    guard isatty(STDERR_FILENO) != 0 else {
        return false
    }

    if let xpcServiceName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] {
        return !xpcServiceName.hasPrefix("com.apple.dt.Xcode")
    }
    
    return true
}()

let runtimeFramework: Bundle? = Bundle(identifier: "com.trill-lang.trillRuntime")

extension FileManager {
  func recursiveChildren(of path: String) -> [String]? {
    guard let enumerator = enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil, options: [], errorHandler: nil) else {
      return nil
    }
    return enumerator.map { ($0 as! URL).path }
  }
}
