//
//  FunctionParser.swift
//  Trill
//

import Foundation

extension Parser {
  /// Function Declaration
  ///
  /// func-decl ::= fun <name>([<name> [internal-name]: <typename>,]*): <typename> <braced-expr-block>
  func parseFuncDecl(_ modifiers: [DeclModifier],
                     forType type: DataType? = nil,
                     isDeinit: Bool = false) throws -> FuncDecl {
    var modifiers = modifiers
    let startLoc = sourceLoc
    var args = [FuncArgumentAssignDecl]()
    var returnType = TypeRefExpr(type: .void, name: "Void")
    var hasVarArgs = false
    var kind: FunctionKind = .free
    var nameRange: SourceRange? = nil
    if case .Init = peek(), let type = type {
      modifiers.append(.mutating)
      kind = .initializer(type: type)
      nameRange = consumeToken().range
    } else if isDeinit, case .deinit = peek(), let type = type{
      kind = .deinitializer(type: type)
      nameRange = consumeToken().range
    } else if case .subscript = peek(), let type = type {
      let tok = consumeToken()
      nameRange = tok.range
      kind = .subscript(type: type)
    } else {
      try consume(.func)
      if let type = type {
        if modifiers.contains(.static) {
          kind = .staticMethod(type: type)
        } else {
          kind = .method(type: type)
        }
      } else if case .operator(let op) = peek() {
        let tok = consumeToken()
        nameRange = tok.range
        kind = .operator(op: op)
      } else if case .subscript = peek() {
        throw Diagnostic.error(ParseError.globalSubscript,
                               loc: currentToken().range.start)
      } else {
        kind = .free
      }
    }
    var name: Identifier = ""
    switch kind {
    case .deinitializer:
      name = Identifier(name: "deinit", range: nameRange)
    case .initializer:
      name = Identifier(name: "\(type!)", range: nameRange)
    case .operator(let op):
      name = Identifier(name: "operator\(op)", range: nameRange)
    case .subscript:
        name = Identifier(name: "subscript", range: nameRange)
    default:
      name = try parseIdentifier()
    }
    if case .deinitializer = kind {
    } else {
      (args, returnType, hasVarArgs) = try parseFuncSignature()
    }
    var body: CompoundStmt? = nil
    if case .leftBrace = peek() {
      body = try parseCompoundExpr()
      if case .initializer(let type) = kind {
        returnType = type.ref()
      }
    }
    if case .operator(let op) = kind {
      return OperatorDecl(op: op,
                          args: args,
                          returnType: returnType,
                          body: body,
                          modifiers: modifiers,
                          opRange: nameRange)
    }
    if case .subscript(let type) = kind {
      return SubscriptDecl(returnType: returnType,
                           args: args,
                           parentType: type,
                           body: body,
                           modifiers: modifiers,
                           sourceRange: range(start: startLoc))
    }
    return FuncDecl(name: name,
                    returnType: returnType,
                    args: args,
                    kind: kind,
                    body: body,
                    modifiers: modifiers,
                    hasVarArgs: hasVarArgs,
                    sourceRange: range(start: startLoc))
  }
  
  func parseFuncSignature() throws -> (args: [FuncArgumentAssignDecl], ret: TypeRefExpr, hasVarArgs: Bool) {
    try consume(.leftParen)
    var hasVarArgs = false
    var args = [FuncArgumentAssignDecl]()
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
      let arg = FuncArgumentAssignDecl(name: internalName,
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
  func parseFunCallArgs(open: TokenKind, close: TokenKind) throws -> [Argument] {
    try consume(open)
    var args = [Argument]()
    while true {
      if peek() == close {
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
      
      if peek() == close {
        consumeToken()
        break
      }
      
      try consume(.comma)
    }
    return args
  }
}
