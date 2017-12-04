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

    public init(stream: inout StreamType) {
        self.stream = stream
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
      return diag.loc?.file
    }

    public func consume(_ diagnostic: Diagnostic) {
        let file = sourceFile(for: diagnostic)
        stream.write("\(diagnostic.diagnosticType): ",
            with: [.bold, diagnostic.diagnosticType.color])
        stream.write("\(diagnostic.message)\n", with: [.bold])

        if let loc = diagnostic.loc,
            let line = file?.lines[loc.line - 1],
            loc.line > 0 {
            stream.write(" --> ", with: [.bold, .cyan])
            let filename = file?.path.basename ?? "<unknown>"
            stream.write("\(filename)")
            if let sourceLoc = diagnostic.loc {
                stream.write(":\(sourceLoc.line):\(sourceLoc.column)",
                    with: [.bold])
            }
            stream.write("\n")
            let lineStr = "\(loc.line)"
            let indentation = "\(indent(lineStr.count))"
            stream.write(" \(indentation)|\n", with: [.cyan])
            if let prior = file?.lines[safe: loc.line - 2] {
              stream.write(" \(indentation)| ", with: [.cyan])
              stream.write("\(prior)\n")
            }
            stream.write(" \(lineStr)| ", with: [.cyan])
            stream.write("\(line)\n")
            stream.write(" \(indentation)| ", with: [.cyan])
            stream.write(highlightString(forDiag: diagnostic),
                         with: [.bold, .green])
            stream.write("\n")
            if let next = file?.lines[safe: loc.line] {
              stream.write(" \(indentation)| ", with: [.cyan])
              stream.write("\(next)\n")
            }
            stream.write("\n")
        }
    }
}

func indent(_ n: Int) -> String {
  return String(repeating: " ", count: n)
}
