///
/// DiagnosticEngine.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Source
import Foundation

public struct Diagnostic: Error, CustomStringConvertible, Hashable {
  public enum DiagnosticType: CustomStringConvertible {
    case error, warning, note
    public var description: String {
      switch self {
      case .error: return "error"
      case .warning: return "warning"
      case .note: return "note"
      }
    }
  }
  public let message: String
  public let diagnosticType: DiagnosticType
  public let loc: SourceLocation?
  private(set) public var highlights: [SourceRange]

  public func highlighting(_ range: SourceRange?) -> Diagnostic {
    guard let range = range else { return self }
    var c = self
    c.highlight(range)
    return c
  }

  public mutating func highlight(_ range: SourceRange?) {
    guard let range = range else { return }
    highlights.append(range)
  }

  public var description: String {
    var description = ""
    if let sourceLoc = loc {
      description += "\(sourceLoc.file.path):\(sourceLoc.line):\(sourceLoc.column): "
    }
    return description + "\(diagnosticType): \(message)"
  }

  public static func error(_ err: Error, loc: SourceLocation? = nil, highlights: [SourceRange] = []) -> Diagnostic {
    return Diagnostic(message: "\(err)", diagnosticType: .error, loc: loc, highlights: highlights)
  }

  public static func warning(_ err: Error, loc: SourceLocation? = nil, highlights: [SourceRange] = []) -> Diagnostic {
    return Diagnostic(message: "\(err)", diagnosticType: .warning, loc: loc, highlights: highlights)
  }

  public static func note(_ note: Error, loc: SourceLocation? = nil, highlights: [SourceRange] = []) -> Diagnostic {
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

  public init() {}

  public func error(_ err: Error,
                    loc: SourceLocation? = nil,
                    highlights: [SourceRange?] = []) {
    error("\(err)", loc: loc, highlights: highlights)
  }

  public func error(_ message: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    add(Diagnostic(message: message, diagnosticType: .error, loc: loc, highlights: highlights.flatMap { $0 }))
  }

  public func warning(_ message: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    add(Diagnostic(message: message, diagnosticType: .warning, loc: loc, highlights: highlights.flatMap { $0 }))
  }
  public func note(_ message: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    add(Diagnostic(message: message, diagnosticType: .note, loc: loc, highlights: highlights.flatMap { $0 }))
  }

  public func add(_ diag: Diagnostic) {
    diagnostics.append(diag)
  }

  public func consumeDiagnostics() {
    for diag in Set(diagnostics) {
      for consumer in consumers {
        consumer.consume(diag)
      }
    }
    for consumer in consumers {
      consumer.finalize()
    }
  }

  public func register(_ consumer: DiagnosticConsumer) {
    consumers.append(consumer)
  }

  public var errors: [Diagnostic] {
    return diagnostics.filter { $0.diagnosticType == .error }
  }

  public var hasErrors: Bool { return !errors.isEmpty }
}
