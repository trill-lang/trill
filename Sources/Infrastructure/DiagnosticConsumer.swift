//
//  DiagnosticConsumer.swift
//  Trill
//

import Foundation

enum ANSIColor: String {
  case black = "\u{001B}[30m"
  case red = "\u{001B}[31m"
  case green = "\u{001B}[32m"
  case yellow = "\u{001B}[33m"
  case blue = "\u{001B}[34m"
  case magenta = "\u{001B}[35m"
  case cyan = "\u{001B}[36m"
  case white = "\u{001B}[37m"
  case bold = "\u{001B}[1m"
  case reset = "\u{001B}[0m"
  
  func name() -> String {
    switch self {
    case .black: return "Black"
    case .red: return "Red"
    case .green: return "Green"
    case .yellow: return "Yellow"
    case .blue: return "Blue"
    case .magenta: return "Magenta"
    case .cyan: return "Cyan"
    case .white: return "White"
    case .bold: return "Bold"
    case .reset: return "Reset"
    }
  }
  
  static func all() -> [ANSIColor] {
    return [.black, .red, .green,
            .yellow, .blue, .magenta,
            .cyan, .white, .bold, .reset]
  }
}

func + (left: ANSIColor, right: String) -> String {
  return left.rawValue + right
}

protocol DiagnosticConsumer: class {
  func consume(_ diagnostic: Diagnostic)
}

class StreamConsumer<StreamType: TextOutputStream>: DiagnosticConsumer {
  let files: [SourceFile]
  let colored: Bool
  
  var stream: StreamType
  
  init(files: [SourceFile], stream: inout StreamType, colored: Bool) {
    self.files = files
    self.colored = colored
    self.stream = stream
  }
  
  func with(_ colors: [ANSIColor], block: () -> ()) {
    if colored {
      for color in colors {
        stream.write(color.rawValue)
      }
    }
    block()
    if colored {
      stream.write(ANSIColor.reset.rawValue)
    }
  }
  
  func highlightString(forDiag diag: Diagnostic) -> String {
    guard let loc = diag.loc, loc.line > 0 && loc.column > 0 else { return "" }
    var s = [Character]()
    let ranges = diag.highlights
      .filter { $0.start.line == loc.line && $0.end.line == loc.line }
      .sorted { $0.start.charOffset < $1.start.charOffset }
    if !ranges.isEmpty {
      s = [Character](repeating: " ", count: ranges.last!.end.column)
      for r in ranges {
        let range = (r.start.column - 1)..<(r.end.column - 1)
        let tildes = [Character](repeating: "~", count: range.count)
        s.replaceSubrange(range, with: tildes)
      }
    }
    let index = loc.column - 1
    if index >= s.endIndex {
      s += [Character](repeating: " ", count: s.endIndex.distance(to: index))
      s.append("^")
    } else {
      s[index] = "^" as Character
    }
    return String(s)
  }
  
  func sourceFile(for diag: Diagnostic) -> SourceFile? {
    guard let diagFile = diag.loc?.file else { return nil }
    for file in files where file.path.filename == diagFile {
      return file
    }
    return nil
  }
  
  func consume(_ diagnostic: Diagnostic) {
    let file = sourceFile(for: diagnostic)
    switch diagnostic.diagnosticType {
    case .warning:
      with([.bold, .magenta]) {
        stream.write("warning: ")
      }
    case .error:
      with([.bold, .red]) {
        stream.write("error: ")
      }
    case .note:
      with([.bold, .green]) {
        stream.write("note: ")
      }
    }
    with([.bold]) {
      stream.write("\(diagnostic.message)\n")
    }
    if let loc = diagnostic.loc,
       let line = file?.lines[loc.line - 1],
       loc.line > 0 {
      with([.bold]) {
        stream.write(" --> ")
      }
      let filename = file?.path.basename ?? "<unknown>"
      stream.write("\(filename)")
      if let sourceLoc = diagnostic.loc {
        with([.bold]) {
          stream.write(":\(sourceLoc.line):\(sourceLoc.column)")
        }
      }
      stream.write("\n")
      let lineStr = "\(loc.line)"
      let indentation = "\(indent(lineStr.characters.count))"
      stream.write(" \(indentation)|\n")
      stream.write(" \(lineStr)| \(line)\n")
      stream.write(" \(indentation)| ")
      with([.bold, .green]) {
        stream.write(highlightString(forDiag: diagnostic))
      }
      stream.write("\n\n")
    }
  }
}
