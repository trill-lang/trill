//
//  DiagnosticEngine.swift
//  Trill
//

import Foundation

public struct Diagnostic: Error, CustomStringConvertible {
  enum DiagnosticType: CustomStringConvertible {
    case error, warning
    var description: String {
      return self == .error ? "error" : "warning"
    }
  }
  let message: String
  let diagnosticType: DiagnosticType
  let loc: SourceLocation?
  private(set) var highlights: [SourceRange]
  
  func highlighting(_ range: SourceRange?) -> Diagnostic {
    guard let range = range else { return self }
    var c = self
    c.highlight(range)
    return c
  }
  
  mutating func highlight(_ range: SourceRange?) {
    guard let range = range else { return }
    highlights.append(range)
  }
  
  public var description: String {
    var description = ""
    if let sourceLoc = loc {
      description += "\(sourceLoc.line):\(sourceLoc.column): "
    }
    return description + "\(diagnosticType): \(message)"
  }
  
  static func error(_ err: Error, loc: SourceLocation? = nil, highlights: [SourceRange] = []) -> Diagnostic {
    return Diagnostic(message: "\(err)", diagnosticType: .error, loc: loc, highlights: highlights)
  }
  
  static func warning(_ err: Error, loc: SourceLocation? = nil, highlights: [SourceRange] = []) -> Diagnostic {
    return Diagnostic(message: "\(err)", diagnosticType: .warning, loc: loc, highlights: highlights)
  }
}

public class DiagnosticEngine {
  private(set) var warnings = [Diagnostic]()
  private(set) var errors = [Diagnostic]()
  private(set) var consumers = [DiagnosticConsumer]()
  
  func error(_ err: Error, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    error("\(err)", loc: loc, highlights: highlights)
  }
  
  func error(_ message: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    errors.append(Diagnostic(message: message, diagnosticType: .error, loc: loc, highlights: highlights.flatMap { $0 }))
  }
  
  func warning(_ message: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    warnings.append(Diagnostic(message: message, diagnosticType: .warning, loc: loc, highlights: highlights.flatMap { $0 }))
  }
  
  func add(error: Diagnostic) { errors.append(error) }
  func add(warning: Diagnostic) { warnings.append(warning) }
  
  func consumeDiagnostics() {
    let diags = (warnings + errors).sorted { a, b in
      guard let aLoc = a.loc else { return false }
      guard let bLoc = b.loc else { return true }
      return aLoc.charOffset < bLoc.charOffset
    }
    for diag in diags {
      for consumer in consumers {
        consumer.consume(diag)
      }
    }
  }
  
  func register(_ consumer: DiagnosticConsumer) {
    consumers.append(consumer)
  }
  
  var hasErrors: Bool { return !errors.isEmpty }
}
