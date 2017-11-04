///
/// Generic.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation
import Source

public class GenericParamDecl: TypeDecl {
    public var constraints: [TypeRefExpr] {
        return conformances
    }
    public init(name: Identifier, constraints: [TypeRefExpr]) {
      super.init(name: name,
                 properties: [],
                 methods: [],
                 staticMethods: [],
                 initializers: [],
                 subscripts: [],
                 modifiers: [],
                 conformances: constraints,
                 deinit: nil,
                 sourceRange: name.range)
      self.type = .typeVariable(name: name.name)
    }

    public override func attributes() -> [String : Any] {
        var superAttrs = super.attributes()
        if !conformances.isEmpty {
            superAttrs["conformances"] = conformances.map { $0.name.name }.joined(separator: ", ")
        }
        return superAttrs
    }
}

public class GenericParam: ASTNode {
    public let typeName: TypeRefExpr
    public var decl: GenericParamDecl? = nil

    public init(typeName: TypeRefExpr) {
        self.typeName = typeName
        super.init(sourceRange: typeName.sourceRange)
    }

    public override func attributes() -> [String : Any] {
        var superAttrs = super.attributes()
        superAttrs["type"] = typeName.name.name
        if let decl = decl {
            superAttrs["decl"] = decl.name.name
        }
        return superAttrs
    }
}
