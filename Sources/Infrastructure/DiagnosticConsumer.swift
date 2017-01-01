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
