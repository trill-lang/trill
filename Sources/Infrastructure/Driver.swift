//
//  Driver.swift
//  Trill
//

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

class Driver: Pass {
  private(set) var passes = [Pass]()
  let context: ASTContext
  required init(context: ASTContext) {
    self.context = context
  }
  
  var timings = [(String, Double)]()
  
  func add<PassType: Pass>(pass: PassType.Type) {
    passes.append(pass.init(context: context))
  }
  
  func add(_ title: String, pass: @escaping (ASTContext) throws -> Void) {
    passes.append(AnyPass(title: title, function: pass, context: context))
  }
  
  func run(in context: ASTContext) {
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
  var title: String {
    return "Driver"
  }
}
