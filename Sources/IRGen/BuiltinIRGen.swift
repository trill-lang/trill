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
      let type = arg.val.type,
      let meta = codegenTypeMetadata(context.canonicalType(type)) else {
        return nil
    }
    return LLVMBuildBitCast(builder, meta, LLVMPointerType(LLVMInt8Type(), 0), "")
  }
}
