///
/// WitnessTable.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Source

public struct WitnessTable {
    public let proto: ProtocolDecl
    public let implementingType: TypeDecl

  public init(proto: ProtocolDecl, implementingType: TypeDecl) {
    self.proto = proto
    self.implementingType = implementingType
  }
}
