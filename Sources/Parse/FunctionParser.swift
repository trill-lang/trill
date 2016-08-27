//
//  FunctionParser.swift
//  Trill
//

import Foundation

extension Parser {
  /// Function Declaration
  ///
  /// func-decl ::= fun <name>([<name> [internal-name]: <typename>,]*): <typename> <braced-expr-block>
  func parseFuncDecl(_ attributes: [DeclAttribute],
                     forType type: DataType? = nil,
                     isDeinit: Bool = false) throws -> FuncDeclExpr {
    var attributes = attributes
    let startLoc = sourceLoc
    var args = [FuncArgumentAssignExpr]()
    var returnType = TypeRefExpr(type: .void, name: "Void")
    var hasVarArgs = false
    let kind: FunctionKind
    var nameRange: SourceRange? = nil
    if case .Init = peek(), type != nil {
      attributes.append(.mutating)
      kind = .initializer(type: type!)
      nameRange = consumeToken().range
    } else if isDeinit, case .deinit = peek(), type != nil {
      kind = .deinitializer(type: type!)
      nameRange = consumeToken().range
    } else {
      try consume(.func)
      if let type = type {
        kind = .method(type: type)
      } else {
        kind = .free
      }
    }
    var name: Identifier = ""
    switch kind {
    case .deinitializer:
      name = Identifier(name: "deinit", range: nameRange)
    case .initializer:
      name = Identifier(name: "init", range: nameRange)
    default:
      name = try parseIdentifier()
    }
    if case .deinitializer = kind {
    } else {
      (args, returnType, hasVarArgs) = try parseFuncSignature()
    }
    var body: CompoundExpr? = nil
    if case .leftBrace = peek() {
      body = try parseCompoundExpr()
      if case .initializer(let type) = kind {
        returnType = type.ref()
      }
    }
    return FuncDeclExpr(name: name,
                        returnType: returnType,
                        args: args,
                        kind: kind,
                        body: body,
                        attributes: attributes,
                        hasVarArgs: hasVarArgs,
                        sourceRange: range(start: startLoc))
  }
  
  func parseFuncSignature() throws -> (args: [FuncArgumentAssignExpr], ret: TypeRefExpr, hasVarArgs: Bool) {
    try consume(.leftParen)
    var hasVarArgs = false
    var args = [FuncArgumentAssignExpr]()
    while true {
      if case .rightParen = peek() {
        consumeToken()
        break
      }
      let startLoc = sourceLoc
      // An argument has both an internal and external name.
      // If there is only one name specified, then the internal
      // and external names match.
      var externalName: Identifier? = nil
      var internalName: Identifier = ""
      if let name = try? attempt(try parseIdentifier()) {
        externalName = name
        internalName = name
      } else if case .underscore = peek() {
        // allow for discarding a external name using '_'
        externalName = nil
        consumeToken()
      } else {
        throw unexpectedToken()
      }
      if let id = try? attempt(try parseIdentifier()) {
        internalName = id
      }
      try consume(.colon)
      
      if case .ellipsis = peek() {
        consumeToken()
        try consume(.rightParen)
        hasVarArgs = true
        break
      }
      let type = try parseType()
      let arg = FuncArgumentAssignExpr(name: internalName,
                                       type: type,
                                       externalName: externalName,
                                       sourceRange: range(start: startLoc))
      args.append(arg)
      if case .rightParen = peek() {
        consumeToken()
        break
      }
      try consume(.comma)
    }
    let returnType: TypeRefExpr
    if case .arrow = peek() {
      consumeToken()
      returnType = try parseType()
    } else {
      returnType = TypeRefExpr(type: .void, name: "Void")
    }
    return (args: args, ret: returnType, hasVarArgs: hasVarArgs)
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
        var args = [TypeRefExpr]()
        while peek() != .rightParen {
          let t = try parseType()
          args.append(t)
          if peek() != .rightParen {
            try consume(.comma)
          }
        }
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
      case .operator(op: .star):
        consumeToken()
        return PointerTypeRefExpr(pointedTo: try parseType(),
                                  level: 1,
                                  sourceRange: range(start: startLoc))
      case .identifier:
        var id = try parseIdentifier()
        let r = range(start: startLoc)
        id = Identifier(name: id.name, range: r)
        return TypeRefExpr(type: DataType(name: id.name),
                           name: id, sourceRange: r)
      default:
        throw unexpectedToken()
      }
    }
  }
  
  /// Function Call Args
  ///
  /// func-call-args ::= ([<label>:] <val-expr>,*)
  func parseFunCallArgs() throws -> [Argument] {
    try consume(.leftParen)
    var args = [Argument]()
    while true {
      if case .rightParen = peek() {
        consumeToken()
        break
      }
      var label: Identifier? = nil
      if let id = try? attempt(try parseIdentifier()) {
        if case .colon = peek() {
          consumeToken()
          label = id
        } else {
          // backtrack behind the identifier
          backtrack()
        }
      }
      let expr = try parseValExpr()
      args.append(Argument(val: expr, label: label))
      
      if case .rightParen = peek() {
        consumeToken()
        break
      }
      
      try consume(.comma)
    }
    return args
  }
}
