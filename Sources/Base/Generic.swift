//
//  Generic.swift
//  Trill
//
//  Created by Harlan Haskins on 1/26/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

class GenericParamDecl: TypeDecl {
    var constraints: [TypeRefExpr] {
        return conformances
    }
    init(name: Identifier, constraints: [TypeRefExpr]) {
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
    }

    override func attributes() -> [String : Any] {
        var superAttrs = super.attributes()
        if !conformances.isEmpty {
            superAttrs["conformances"] = conformances.map { $0.name.name }.joined(separator: ", ")
        }
        return superAttrs
    }
}

class GenericParam: ASTNode {
    let typeName: TypeRefExpr
    var decl: GenericParamDecl? = nil

    init(typeName: TypeRefExpr) {
        self.typeName = typeName
        super.init(sourceRange: typeName.sourceRange)
    }

    override func attributes() -> [String : Any] {
        var superAttrs = super.attributes()
        superAttrs["type"] = typeName.name.name
        if let decl = decl {
            superAttrs["decl"] = decl.name.name
        }
        return superAttrs
    }
}
