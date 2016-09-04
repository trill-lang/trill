//
//  JSONDiagnosticConsumer.swift
//  Trill
//
//  Created by Harlan Haskins on 9/3/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

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
      if let file = loc.file {
        js["file"] = file
      }
      js["sourceLocation"] = loc.json
    }
    var highlightJSON = [[String: Any]]()
    for highlight in highlights {
      highlightJSON.append([
        "start": highlight.start
      ])
    }
    js["highlights"] = highlightJSON
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
  }
  
  var json: [[String: Any]] {
    return diagnostics.map { $0.json }
  }
}
