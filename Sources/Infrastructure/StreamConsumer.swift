//
//  StreamConsumer.swift
//  Trill
//

import Foundation

class StreamConsumer<StreamType: ColoredStream>: DiagnosticConsumer {
    let files: [SourceFile]
    var stream: StreamType
    
    init(files: [SourceFile], stream: inout StreamType) {
        self.files = files
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
        guard let diagFile = diag.loc?.file else { return nil }
        for file in files where file.path.filename == diagFile {
            return file
        }
        return nil
    }
    
    func consume(_ diagnostic: Diagnostic) {
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
            let indentation = "\(indent(lineStr.characters.count))"
            stream.write(" \(indentation)|\n", with: [.cyan])
            stream.write(" \(lineStr)| ", with: [.cyan])
            stream.write("\(line)\n")
            stream.write(" \(indentation)| ", with: [.cyan])
            stream.write(highlightString(forDiag: diagnostic),
                         with: [.bold, .green])
            stream.write("\n\n")
        }
    }
}
