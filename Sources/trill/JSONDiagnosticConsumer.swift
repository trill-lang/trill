///
/// JSONDiagnosticConsumer.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Source
import Diagnostics
import Foundation

private extension SourceLocation {
  var json: [String: Any] {
    return [
      "line": line,
      "column": column,
      "offset": charOffset
    ]
  }
}

private extension SourceRange {
  var json: [String: Any] {
    return [
      "start": start.json,
      "end": end.json
    ]
  }
}

private extension Diagnostic {
  var json: [String: Any] {
    var js: [String: Any] = [
      "type": "\(diagnosticType)",
      "message": message,
    ]
    if let loc = self.loc {
      js["file"] = loc.file
      js["sourceLocation"] = loc.json
    }

    js["highlights"] = highlights.map {
      [
        "start": $0.start.json,
        "end": $0.end.json,
      ]
    }
    return js
  }
}

class JSONDiagnosticConsumer<StreamType: TextOutputStream>: DiagnosticConsumer {
  var diagnostics = [Diagnostic]()
  var stream: StreamType

  init(stream: inout StreamType) {
    self.stream = stream
  }

  func consume(_ diagnostic: Diagnostic) {
    diagnostics.append(diagnostic)
  }

  func finalize() {
    let jsonData = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
    stream.write(String(data: jsonData, encoding: .utf8)!)
    stream.write("\n")
  }

  var json: [[String: Any]] {
    return diagnostics.map { $0.json }
  }
}
