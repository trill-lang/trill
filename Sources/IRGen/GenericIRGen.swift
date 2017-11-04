///
/// GenericIRGen.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import LLVM

extension IRGenerator {

  func codegenWitnessTables(_ type: TypeDecl) -> [Global] {
    var globals = [Global]()
    for typeRef in type.conformances {
      guard let proto = context.protocol(named: typeRef.name) else {
        fatalError("no protocol named \(typeRef.name)")
      }
      let table = WitnessTable(proto: proto, implementingType: type)
      globals.append(codegenWitnessTable(table))
    }
    return globals
  }

  /// Generates code for a witness table that contains all requirements of a
  /// type conforming to a given protocol.
  ///
  /// A Witness Table for a protocol consists of:
  ///
  /// - A pointer to the type metadata for the protocol type
  /// - A pointer to an array of the protocol's witness table
  func codegenWitnessTable(_ table: WitnessTable) -> Global {
    let tableSymbol = Mangler.mangle(table)
    if let global = module.global(named: tableSymbol) {
      return global
    }
    let methodArrayType = ArrayType(elementType: PointerType.toVoid,
                                     count: table.proto.methods.count)
    var array = builder.addGlobal(tableSymbol,
                                  type: methodArrayType)

    let methods = table.implementingType.methodsSatisfyingRequirements(of: table.proto)

    let entries: [IRValue] = methods.map {
      let function = codegenFunctionPrototype($0)
      return builder.buildBitCast(function, type: PointerType.toVoid)
    }

    array.initializer = ArrayType.constant(entries, type: PointerType.toVoid)

    _ = codegenProtocolMetadata(table.proto)

    return array
  }
}
