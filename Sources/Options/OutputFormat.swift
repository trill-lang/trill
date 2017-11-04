///
/// OutputFormat.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

public enum Mode {
  case emit(OutputFormat)
  case jit, onlyDiagnostics
}

public enum OutputFormat: String {
  case ast
  case asm
  case obj = "object"
  case binary
  case llvm = "ir"
  case bitCode = "bitcode"

  public func addExtension(to basename: String) -> String {
    var url = URL(fileURLWithPath: basename)
    url.deletePathExtension()
    return url.appendingPathExtension(fileExtension).lastPathComponent
  }

  public var fileExtension: String {
    switch self {
    case .llvm: return "ll"
    case .asm: return "s"
    case .obj, .binary: return "o"
    case .bitCode: return "bc"
    default: fatalError("should not be serializing \(self)")
    }
  }

  public var description: String {
    switch self {
    case .llvm: return "LLVM IR"
    case .binary: return "Executable"
    case .asm: return "Assembly"
    case .obj: return "Object File"
    case .ast: return "AST"
    case .bitCode: return "LLVM Bitcode File"
    }
  }
}
