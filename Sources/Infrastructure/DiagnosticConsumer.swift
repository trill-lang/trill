//
//  DiagnosticConsumer.swift
//  Trill
//

import Foundation

extension Diagnostic.DiagnosticType {
    var color: ANSIColor {
        switch self {
        case .error: return .red
        case .warning: return .magenta
        case .note: return .green
        }
    }
}

protocol DiagnosticConsumer: class {
  func consume(_ diagnostic: Diagnostic)
  func finalize()
}

extension DiagnosticConsumer {
  func finalize() {}
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
    with([.bold, diagnostic.diagnosticType.color]) {
        stream.write("\(diagnostic.diagnosticType): ")
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
