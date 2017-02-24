//
//  TypeParser.swift
//  Trill
//

import Foundation

extension Parser {
  /// Type Declaration
  ///
  /// type-decl ::= type <typename> {
  ///   [<field-decl> | <func-decl>]*
  /// }
  func parseTypeDecl(_ modifiers: [DeclModifier]) throws -> ASTNode {
    try consume(.type)
    let startLoc = sourceLoc
    let name = try parseIdentifier()
    var conformances = [TypeRefExpr]()
    var genericParams = [GenericParamDecl]()

    if peek() == .leftAngle {
      genericParams = try parseGenericParamDecls()
    }
    
    if case .operator(op: .assign) = peek() {
      consumeToken()
      let bound = try parseType()
      return TypeAliasDecl(name: name,
                           bound: bound,
                           sourceRange: range(start: startLoc))
    }
    if case .colon = peek() {
      consumeToken()
      conformances = try parseSeparated(by: .comma, until: .leftBrace, parseType)
    }
    try consume(.leftBrace)
    var properties = [PropertyDecl]()
    var methods = [MethodDecl]()
    var staticMethods = [MethodDecl]()
    var subscripts = [SubscriptDecl]()
    var initializers = [InitializerDecl]()
    var deinitializer: DeinitializerDecl?
    let type = DataType(name: name.name)
    loop: while true {
      if case .rightBrace = peek() {
        consumeToken()
        break
      }
      let modifiers = try parseModifiers()
      switch peek() {
      case .poundError, .poundWarning:
        context.add(try parsePoundDiagnosticExpr())
      case .func:
        let decl = try parseFuncDecl(modifiers, forType: type) as! MethodDecl
        if decl.has(attribute: .static) {
          staticMethods.append(decl)
        } else {
          methods.append(decl)
        }
      case .Init:
        initializers.append(try parseFuncDecl(modifiers, forType: type) as! InitializerDecl)
      case .var, .let:
        properties.append(try parsePropertyDecl(modifiers, forType: type))
      case .subscript:
        subscripts.append(try parseFuncDecl(modifiers, forType: type) as! SubscriptDecl)
      case .deinit:
        if deinitializer != nil {
          throw Diagnostic.error(ParseError.duplicateDeinit, loc: sourceLoc)
        }
        deinitializer = try parseFuncDecl(modifiers, forType:type) as? DeinitializerDecl
      default:
        throw unexpectedToken()
      }
      try consumeAtLeastOneLineSeparator()
    }
    return TypeDecl(name: name,
                    properties: properties,
                    methods: methods,
                    staticMethods: staticMethods,
                    initializers: initializers,
                    subscripts: subscripts,
                    modifiers: modifiers,
                    conformances: conformances,
                    deinit: deinitializer,
                    genericParams: genericParams,
                    sourceRange: range(start: startLoc))
  }

  func parsePropertyDecl(_ modifiers: [DeclModifier],
                         forType type: DataType) throws -> PropertyDecl {
    let startLoc = sourceLoc
    let mutable: Bool
    if case .var = peek() {
      mutable = true
    } else if case .let = peek() {
      mutable = false
    } else {
      throw unexpectedToken()
    }
    consumeToken()
    let id = try parseIdentifier()
    var rhs: Expr? = nil
    var getter: PropertyGetterDecl? = nil
    var setter: PropertySetterDecl? = nil
    try consume(.colon)
    let propType = try parseType()
    switch peek() {
    case .operator(op: .assign):
      consumeToken()
      rhs = try parseValExpr()
    case .leftBrace:
      guard mutable else {
        throw Diagnostic.error(ParseError.computedPropertyMustBeMutable,
                               loc: startLoc)
      }
      consumeToken()
      accessors: while true {
        switch peek() {
        case .identifier("get"):
          guard getter == nil else {
            throw Diagnostic.error(ParseError.duplicateGetter,
                                   loc: sourceLoc)
          }
          getter = try parsePropertyGetter(type: type, name: id, propType: propType)
        case .identifier("set"):
          guard setter == nil else {
            throw Diagnostic.error(ParseError.duplicateSetter,
                                   loc: sourceLoc)
          }
          setter = try parsePropertySetter(type: type, name: id, propType: propType)
        case .rightBrace:
          consumeToken()
          break accessors
        default:
          let loc = sourceLoc
          let body = try parseCompoundStmt(leftBraceOptional: true)
          getter = PropertyGetterDecl(parentType: type,
                                      propertyName: id,
                                      type: propType,
                                      body: body,
                                      sourceRange: range(start: loc))
          break accessors
        }
      }
    default:
      break
    }
    return PropertyDecl(name: id,
                        type: propType,
                        mutable: mutable,
                        rhs: rhs,
                        modifiers: modifiers,
                        getter: getter,
                        setter: setter,
                        sourceRange: range(start: startLoc))
  }

  func parsePropertyGetter(type: DataType, name: Identifier, propType: TypeRefExpr) throws -> PropertyGetterDecl {
    let loc = sourceLoc
    try consume(.identifier("get"))
    let body = try parseCompoundStmt()

    return PropertyGetterDecl(parentType: type,
                              propertyName: name,
                              type: propType,
                              body: body,
                              sourceRange: range(start: loc))
  }

  func parsePropertySetter(type: DataType, name: Identifier, propType: TypeRefExpr) throws -> PropertySetterDecl {
    let loc = sourceLoc
    try consume(.identifier("set"))
    let body = try parseCompoundStmt()
    return PropertySetterDecl(parentType: type,
                              propertyName: name,
                              type: propType,
                              body: body,
                              sourceRange: range(start: loc))
  }

  func parseSeparated<T>(by separator: TokenKind, until end: TokenKind, _ parser: () throws -> T) throws -> [T] {
    var values = [T]()
    while peek() != end {
      values.append(try parser())
      if peek() != end {
        try consume(separator)
      }
    }
    return values
  }
  
  func parseType() throws -> TypeRefExpr {
    let startLoc = sourceLoc
    while true {
      switch peek() {
      // HACK
      case .unknown(let char):
        var pointerLevel = 0
        for c in char.characters {
          if c != "*" {
            throw unexpectedToken()
          }
          pointerLevel += 1
        }
        consumeToken()
        return PointerTypeRefExpr(pointedTo: try parseType(),
                                  level: pointerLevel,
                                  sourceRange: range(start: startLoc))
      case .leftParen:
        consumeToken()
        let args = try parseSeparated(by: .comma, until: .rightParen, parseType)
        try consume(.rightParen)
        if case .arrow = peek() {
          consumeToken()
          let ret = try parseType()
          return FuncTypeRefExpr(argNames: args,
                                 retName: ret,
                                 sourceRange: range(start: startLoc))
        } else {
          return TupleTypeRefExpr(fieldNames: args,
                                  sourceRange: range(start: startLoc))
        }
      case .leftBracket:
        consumeToken()
        let innerType = try parseType()
        try consume(.rightBracket)
        return ArrayTypeRefExpr(element: innerType,
                                length: nil,
                                sourceRange: range(start: startLoc))
      case .operator(op: .star):
        consumeToken()
        return PointerTypeRefExpr(pointedTo: try parseType(),
                                  level: 1,
                                  sourceRange: range(start: startLoc))
      case .identifier:
        var id = try parseIdentifier()
        let r = range(start: startLoc)
        id = Identifier(name: id.name, range: r)
        let type = TypeRefExpr(type: DataType(name: id.name),
                               name: id, sourceRange: r)
        guard case .operator(op: .lessThan) = peek() else {
          return type
        }
        let args = try parseGenericParams()
        return GenericTypeRefExpr(unspecializedType: type, args: args)
      default:
        throw unexpectedToken()
      }
    }
  }
  
  func parseProtocolDecl(modifiers: [DeclModifier]) throws -> ProtocolDecl {
    let startLoc = sourceLoc
    try consume(.protocol)
    let name = try parseIdentifier()
    var conformances = [TypeRefExpr]()
    if case .colon = peek() {
      consumeToken()
      guard case .identifier = peek() else {
        throw Diagnostic.error(ParseError.expectedIdentifier(got: peek()),
                               loc: currentToken().range.start,
                               highlights: [
                                 currentToken().range
                               ])
      }
      conformances = try parseSeparated(by: .comma, until: .leftBrace) {
        let name = try parseIdentifier()
        return TypeRefExpr(type: DataType(name: name.name), name: name)
      }
    }
    try consume(.leftBrace)
    var methods = [ProtocolMethodDecl]()
    while true {
      if case .rightBrace = peek() {
        consumeToken()
        break
      }
      let modifiers = try parseModifiers()
      guard case .func = peek()  else {
        throw Diagnostic.error(ParseError.unexpectedExpression(expected: "function"),
                               loc: sourceLoc)
      }
      methods.append(try parseFuncDecl(modifiers,
                                       forType: DataType(name: name.name),
                                       isProtocol: true) as! ProtocolMethodDecl)
    }
    return ProtocolDecl(name: name,
                        properties: [],
                        methods: methods,
                        modifiers: [],
                        conformances: conformances,
                        sourceRange: range(start: startLoc))
  }
}
