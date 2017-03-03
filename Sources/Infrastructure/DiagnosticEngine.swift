//
//  DiagnosticEngine.swift
//  Trill
//

import Foundation

public struct Diagnostic: Error, CustomStringConvertible, Hashable {
  enum DiagnosticType: CustomStringConvertible {
    case error, warning, note
    var description: String {
      switch self {
      case .error: return "error"
      case .warning: return "warning"
      case .note: return "note"
      }
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
      if let file = sourceLoc.file {
        description += "\(file):"
      }
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
  static func note(_ note: Error, loc: SourceLocation? = nil, highlights: [SourceRange] = []) -> Diagnostic {
    return Diagnostic(message: "\(note)", diagnosticType: .note, loc: loc, highlights: highlights)
  }

  public var hashValue: Int {
    return description.hashValue ^ 7
  }

  public static func ==(lhs: Diagnostic, rhs: Diagnostic) -> Bool {
    return lhs.description == rhs.description
  }
}

public class DiagnosticEngine {
  private(set) var diagnostics = [Diagnostic]()
  private(set) var consumers = [DiagnosticConsumer]()
  
  func error(_ err: Error, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    error("\(err)", loc: loc, highlights: highlights)
  }
  
  func error(_ message: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    add(Diagnostic(message: message, diagnosticType: .error, loc: loc, highlights: highlights.flatMap { $0 }))
  }
  
  func warning(_ message: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    add(Diagnostic(message: message, diagnosticType: .warning, loc: loc, highlights: highlights.flatMap { $0 }))
  }
  func note(_ message: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    add(Diagnostic(message: message, diagnosticType: .note, loc: loc, highlights: highlights.flatMap { $0 }))
  }
  
  func add(_ diag: Diagnostic) {
    diagnostics.append(diag)
  }
  
  func consumeDiagnostics() {
    for diag in diagnostics.unique() {
      for consumer in consumers {
        consumer.consume(diag)
      }
    }
    for consumer in consumers {
      consumer.finalize()
    }
  }
  
  func register(_ consumer: DiagnosticConsumer) {
    consumers.append(consumer)
  }
  
  var errors: [Diagnostic] {
    return diagnostics.filter { $0.diagnosticType == .error }
  }
  
  var hasErrors: Bool { return !errors.isEmpty }
}
