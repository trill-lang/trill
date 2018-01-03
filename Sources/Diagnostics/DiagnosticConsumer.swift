///
/// DiagnosticConsumer.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

public protocol DiagnosticConsumer: class {
  func consume(_ diagnostic: Diagnostic)
  func finalize()
}

extension DiagnosticConsumer {
  public func finalize() {}
}
