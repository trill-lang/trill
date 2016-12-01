//
//  BuiltinIRGen.swift
//  Trill
//
//  Created by Harlan Haskins on 9/2/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

import Foundation

extension IRGenerator {
  func codegenTypeOfCall(_ expr: FuncCallExpr) -> LLVMValueRef? {
    guard
      let arg = expr.args.first,
      let type = arg.val.type else {
        return nil
    }
    if case .any = type {
        let getMetadata = codegenIntrinsic(named: "trill_getAnyTypeMetadata")
        var binding = visit(expr.args[0].val)
        return LLVMBuildCall(builder, getMetadata, &binding, 1, "any-binding")
    }
    let meta = codegenTypeMetadata(context.canonicalType(type))
    return LLVMBuildBitCast(builder, meta, LLVMPointerType(LLVMInt8Type(), 0), "")
  }
}
