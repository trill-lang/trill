//
//  BuiltinIRGen.swift
//  Trill
//
//  Created by Harlan Haskins on 9/2/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

import Foundation
import LLVM

extension IRGenerator {
  func codegenTypeOfCall(_ expr: FuncCallExpr) -> Result {
    guard
      let arg = expr.args.first,
      let type = arg.val.type else {
        return nil
    }
    if case .any = type {
        let getMetadata = codegenIntrinsic(named: "trill_getAnyTypeMetadata")
        return builder.buildCall(getMetadata, args: [visit(expr.args[0].val)!], name: "any-binding")
    }
    let meta = codegenTypeMetadata(context.canonicalType(type))
    return builder.buildBitCast(meta, type: PointerType(pointee: IntType.int8))
  }
}
