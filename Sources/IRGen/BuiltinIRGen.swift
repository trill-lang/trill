///
/// BuiltinIRGen.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import Foundation
import LLVM

extension IRGenerator {
  func codegenTypeOfCall(_ expr: FuncCallExpr) -> Result {
    guard
      let arg = expr.args.first,
      arg.val.type != .error else {
        return nil
    }
    let type = arg.val.type
    if case .any = type {
        let getMetadata = codegenIntrinsic(named: "trill_getAnyTypeMetadata")
        return builder.buildCall(getMetadata, args: [visit(arg.val)!], name: "any-binding")
    }
    let meta = codegenTypeMetadata(context.canonicalType(type))
    return builder.buildBitCast(meta, type: PointerType(pointee: IntType.int8))
  }
}
