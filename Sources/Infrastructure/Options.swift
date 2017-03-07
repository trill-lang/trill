//
//  Options.swift
//  Trill
//
//  Created by Harlan Haskins on 8/30/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

import Foundation

enum OutputFormat {
  case javaScript, ast, asm, obj, binary, llvm, bitCode
  
  init(_ raw: RawOutputFormat) {
    switch raw {
    case LLVM: self = .llvm
    case Bitcode: self = .bitCode
    case Binary: self = .binary
    case Object: self = .obj
    case ASM: self = .asm
    case AST: self = .ast
    case JavaScript: self = .javaScript
    default: fatalError("invalid output format \(raw)")
    }
  }
}

enum Mode {
  case emit(OutputFormat)
  case jit, onlyDiagnostics
  
  init(_ raw: RawMode, outputFormat: RawOutputFormat) {
    switch raw {
    case Emit: self = .emit(OutputFormat(outputFormat))
    case RunJIT: self = .jit
    case OnlyDiagnostics: self = .onlyDiagnostics
    default: fatalError("invalid mode \(raw)")
    }
  }
}

func swiftArrayFromCStrings(_ ptr: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, count: Int) -> [String] {
  var strings = [String]()
  for str in UnsafeMutableBufferPointer(start: ptr, count: count) {
    guard let str = str else { continue }
    strings.append(String(cString: str))
  }
  return strings
}

public class Options {
  let filenames: [String]
  let targetTriple: String?
  let outputFilename: String?
  let mode: Mode
  let importC: Bool
  let emitTiming: Bool
  let jsonDiagnostics: Bool
  let parseOnly: Bool
  let isStdin: Bool
  let showImports: Bool
  let includeStdlib: Bool
  let optimizationLevel: OptimizationLevel
  let raw: RawOptions
  let jitArgs: [String]
  
  init(_ raw: RawOptions) {
    self.raw = raw
    self.mode = Mode(raw.mode, outputFormat: raw.outputFormat)
    self.filenames = swiftArrayFromCStrings(raw.filenames, count: raw.filenameCount)
    self.jitArgs = swiftArrayFromCStrings(raw.jitFlags, count: raw.jitFlagCount)
    self.importC = raw.importC
    self.emitTiming = raw.emitTiming
    self.isStdin = raw.isStdin
    self.optimizationLevel = raw.optimizationLevel
    self.jsonDiagnostics = raw.jsonDiagnostics
    self.parseOnly = raw.parseOnly
    self.showImports = raw.showImports
    self.includeStdlib = raw.stdlib
    if let outputFilename = raw.outputFilename {
      self.outputFilename = String(cString: outputFilename)
    } else {
      self.outputFilename = nil
    }
    if let target = raw.target {
      self.targetTriple = String(cString: target)
    } else {
      self.targetTriple = nil
    }
  }
  
  deinit {
    DestroyRawOptions(raw)
  }
}
