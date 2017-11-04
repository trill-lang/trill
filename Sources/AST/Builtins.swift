///
/// Builtins.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

public enum IntrinsicFunctions {
  public static let typeOf = FuncDecl(name: "typeOf",
                               returnType: DataType.pointer(type: .void).ref(),
                               args: [
                                ParamDecl(name: "", type: DataType.any.ref())
                               ])
  public static let allIntrinsics = [typeOf]
}
