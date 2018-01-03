///
/// StreamConsumer.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Source
import Foundation

public class StreamConsumer<StreamType: ColoredStream>: DiagnosticConsumer {
  var stream: StreamType
  let sourceFileManager: SourceFileManager

  public init(stream: inout StreamType, sourceFileManager: SourceFileManager) {
    self.stream = stream
    self.sourceFileManager = sourceFileManager
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

  public func consume(_ diagnostic: Diagnostic) {
    stream.write("\(diagnostic.diagnosticType): ",
      with: [.bold, diagnostic.diagnosticType.color])
    stream.write("\(diagnostic.message)\n", with: [.bold])
    guard let loc = diagnostic.loc, loc.line > 0 else { return }
    let file = loc.file
    let lines: [Substring]
    do {
      lines = try sourceFileManager.lines(in: file)
    } catch {
      return
    }
    let line = lines[loc.line - 1]
    stream.write(" --> ", with: [.bold, .cyan])
    let filename = file.path.basename
    stream.write("\(filename)")
    if let sourceLoc = diagnostic.loc {
      stream.write(":\(sourceLoc.line):\(sourceLoc.column)",
        with: [.bold])
    }
    stream.write("\n")
    let lineStr = "\(loc.line)"
    let indentation = "\(indent(lineStr.count))"
    stream.write(" \(indentation)|\n", with: [.cyan])
    if let prior = lines[safe: loc.line - 2] {
      stream.write(" \(indentation)| ", with: [.cyan])
      stream.write("\(prior)\n")
    }
    stream.write(" \(lineStr)| ", with: [.cyan])
    stream.write("\(line)\n")
    stream.write(" \(indentation)| ", with: [.cyan])
    stream.write(highlightString(forDiag: diagnostic),
                 with: [.bold, .green])
    stream.write("\n")
    if let next = lines[safe: loc.line] {
      stream.write(" \(indentation)| ", with: [.cyan])
      stream.write("\(next)\n")
    }
    stream.write("\n")
  }
}

func indent(_ n: Int) -> String {
  return String(repeating: " ", count: n)
}

extension Diagnostic.DiagnosticType {
  public var color: ANSIColor {
    switch self {
    case .error: return .red
    case .warning: return .magenta
    case .note: return .green
    }
  }
}
