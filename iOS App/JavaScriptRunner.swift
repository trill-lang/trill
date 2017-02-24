//
//  JavaScriptRunner.swift
//  Trill
//

import Foundation
import JavaScriptCore

class JavaScriptRunner: TextOutputStream {
  var input = ""
  weak var objCReceiver: NSObject?
  var output: (String) -> Void
  let jsContext = JSContext(virtualMachine: JSVirtualMachine())
  let context: ASTContext
  
  init(output: @escaping (String) -> Void, context: ASTContext) {
    self.context = context
    self.output = output
  }
  
  func write(_ string: String) {
    input += string
  }
  
  func onMain(_ block: @escaping () -> ()) {
    DispatchQueue.main.async(execute: block)
  }
  
  func run() {
    jsContext?.exceptionHandler = { ctx, exception in
      guard let exception = exception else { return }
      self.context.diag.error("JavaScript Error: \(exception)")
    }
    let printlnFn: @convention(block) (AnyObject) -> Void = { v in
      self.onMain { self.output("\(v)\n") }
    }
    jsContext?.setObject(unsafeBitCast(printlnFn, to: AnyObject.self), forKeyedSubscript: "println" as NSString)
    let printFn: @convention(block) (AnyObject) -> Void = { v in
      self.onMain { self.output("\(v)") }
    }
    jsContext?.setObject(unsafeBitCast(printFn, to: AnyObject.self), forKeyedSubscript: "print" as NSString)
    
    let callObjC: @convention(block) (String) -> Void = { sel in
      self.onMain {
        self.objCReceiver!.perform(Selector(sel))
      }
    }
    jsContext?.setObject(unsafeBitCast(callObjC, to: AnyObject.self), forKeyedSubscript: "callObjC" as NSString)
    
    let callObjC1: @convention(block) (String, AnyObject) -> Void = { sel, arg in
      self.onMain {
        self.objCReceiver!.perform(Selector(sel), with: arg)
      }
    }
    jsContext?.setObject(unsafeBitCast(callObjC1, to: AnyObject.self), forKeyedSubscript: "callObjC1" as NSString)
    
    let callObjC2: @convention(block) (String, AnyObject, AnyObject) -> Void = { sel, arg1, arg2 in
      self.onMain {
        self.objCReceiver!.perform(Selector(sel), with: arg1, with: arg2)
      }
    }
    jsContext?.setObject(unsafeBitCast(callObjC2, to: AnyObject.self), forKeyedSubscript: "callObjC2" as NSString)
    _ = jsContext?.evaluateScript(input)
  }
}
