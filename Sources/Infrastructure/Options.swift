//
//  Options.swift
//  Trill
//
//  Created by Harlan Haskins on 8/30/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

import Foundation


enum Mode: Int {
  case emitLLVM, emitAST, emitASM, emitObj, emitBinary
  case emitJavaScript, prettyPrint, jit
  
  init(_ raw: RawMode) {
    switch raw {
    case EmitLLVM: self = .emitLLVM
    case EmitAST: self = .emitAST
    case EmitASM: self = .emitASM
    case EmitObj: self = .emitObj
    case EmitBinary: self = .emitBinary
    case PrettyPrint: self = .prettyPrint
    case EmitJavaScript: self = .emitJavaScript
    case JIT: self = .jit
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
  let isStdin: Bool
  let optimizationLevel: OptimizationLevel
  let raw: RawOptions
  
  init(_ raw: RawOptions) {
    self.raw = raw
    self.mode = Mode(raw.mode)
    self.filenames = swiftArrayFromCStrings(raw.filenames, count: raw.filenameCount)
    self.importC = raw.importC
    self.emitTiming = raw.emitTiming
    self.isStdin = raw.isStdin
    self.optimizationLevel = raw.optimizationLevel
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
