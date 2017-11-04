///
/// Driver.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import Foundation

struct AnyPass: Pass {
  let function: (ASTContext) throws -> Void
  let title: String
  let context: ASTContext
  init(context: ASTContext) {
    fatalError("use init(title:function:context:)")
  }
  init(title: String, function: @escaping (ASTContext) throws -> Void, context: ASTContext) {
    self.title = title
    self.context = context
    self.function = function
  }

  func run(in context: ASTContext) throws {
    try function(context)
  }
}

public class Driver: Pass {
  private(set) var passes = [Pass]()

  public let context: ASTContext
  required public init(context: ASTContext) {
    self.context = context
  }

  public private(set) var timings = [(String, Double)]()

  public func add<PassType: Pass>(pass: PassType.Type) {
    passes.append(pass.init(context: context))
  }

  public func add(_ title: String, pass: @escaping (ASTContext) throws -> Void) {
    passes.append(AnyPass(title: title, function: pass, context: context))
  }

  public func run(in context: ASTContext) {
    for pass in passes {
      let start = CFAbsoluteTimeGetCurrent()
      do {
        try pass.run(in: context)
      } catch {
        context.error(error)
      }
      let end = CFAbsoluteTimeGetCurrent()
      timings.append((pass.title, end - start))
      if context.diag.hasErrors { break }
    }
  }

  public var title: String {
    return "Driver"
  }
}
