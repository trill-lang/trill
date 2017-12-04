/// TrillInvocation.swift
///
/// Copyright 2017, The Trill Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Symbolic

/// Finds the trill executable relative to the location of the `lite` executable.
func findTrillExecutable() -> URL? {
  let fm = FileManager.default
  guard let path = SymbolInfo(address: #dsohandle)?.filename else { return nil }
  let trillURL = path.deletingLastPathComponent()
                     .appendingPathComponent("trill")
  guard fm.fileExists(atPath: trillURL.path) else { return nil }
  return trillURL
}
