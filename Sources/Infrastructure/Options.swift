//
//  Options.swift
//  Trill
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

public struct Options {
  let filenames: [String]
  let targetTriple: String?
  let outputFilename: String?
  let mode: Mode
  let importC: Bool
  let emitTiming: Bool
  let isStdin: Bool
  let optimizationLevel: OptimizationLevel
  
  init(_ raw: RawOptions) {
    self.mode = Mode(raw.mode)
    var filenames = [String]()
    for i in 0..<raw.filenameCount {
      filenames.append(String(cString: raw.filenames[i]!))
    }
    self.filenames = filenames
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
    DestroyRawOptions(raw)
  }
}
