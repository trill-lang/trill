//
//  Builtins.swift
//  Trill
//
//  Created by Harlan Haskins on 9/2/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

import Foundation

enum IntrinsicFunctions {
  static let typeOf = FuncDecl(name: "typeOf",
                               returnType: DataType.pointer(type: .void).ref(),
                               args: [
                                ParamDecl(name: "", type: DataType.any.ref())
                               ])
  static let allIntrinsics = [typeOf]
}
