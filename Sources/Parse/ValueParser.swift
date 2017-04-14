//
//  ValueParser.swift
//  Trill
//

import Foundation

extension Parser {
  
  /// Value Expression
  ///
  /// val-expr ::= <identifier>[. <identifier>]
  ///            | <val-expr><func-call-args>
  ///            | <op><val-expr> | <val-expr> <op> <val-expr>
  ///            | <val-expr> [ <num> ]
  ///            |
  func parseValExpr() throws -> Expr {
    var valExpr: Expr? = nil
    let startLoc = sourceLoc
    
    let tok = currentToken()
    switch tok.kind {
    case .operator(let op) where op.isPrefix:
      let opRange = currentToken().range
      consumeToken()
      let val = try parseValExpr()
      if let num = val as? NumExpr, op == .minus {
        return NumExpr(value: -num.value,
                       raw: "-" + num.raw,
                       sourceRange: tok.range)
      } else if let infix = val as? InfixOperatorExpr {
        return attachPrefixToInfix(op, prefixRange: opRange,
                                   startLoc: tok.range.start, expr: infix)
      } else if let isExpr = val as? IsExpr {
        return attachPrefixToIsExpr(op, prefixRange: opRange,
                                    startLoc: tok.range.start, expr: isExpr)
      } else if let coercionExpr = val as? CoercionExpr {
        return attachPrefixToCoercionExpr(op, prefixRange: opRange,
                                          startLoc: tok.range.start,
                                          expr: coercionExpr)
      }
      return PrefixOperatorExpr(op: op, rhs: val, opRange: opRange,
                                sourceRange: range(start: startLoc))
    case .leftParen:
      consumeToken()
      let val = try parseValExpr()
      switch peek() {
      case .rightParen:
        consumeToken()
        valExpr = ParenExpr(value: val, sourceRange: range(start: startLoc))
      case .comma:
        var fields = [val]
        consumeToken()
        while true {
          fields.append(try parseValExpr())
          if case .rightParen = peek() { break }
          try consume(.comma)
        }
        try consume(.rightParen)
        valExpr = TupleExpr(values: fields, sourceRange: range(start: startLoc))
      default:
        throw unexpectedToken()
      }
    case .leftBracket:
      consumeToken()
      var values = [Expr]()
      while peek() != .rightBracket {
        values.append(try parseValExpr())
        if peek() != .rightBracket {
          try consume(.comma)
        }
      }
      consumeToken()
      return ArrayExpr(values: values, sourceRange: range(start: startLoc))
    case .char(let value):
      consumeToken()
      valExpr = CharExpr(value: value, sourceRange: range(start: startLoc))
    case .number(let num, let raw):
      consumeToken()
      valExpr = NumExpr(value: num,
                        raw: raw,
                        sourceRange: tok.range)
    case .float(let value):
      consumeToken()
      valExpr = FloatExpr(value: value,
                          sourceRange: range(start: startLoc))
    case .true:
      consumeToken()
      valExpr = BoolExpr(value: true,
                         sourceRange: tok.range)
    case .false:
      consumeToken()
      valExpr = BoolExpr(value: false,
                         sourceRange: tok.range)
    case .poundFile:
      consumeToken()
      valExpr = PoundFileExpr(value: filename,
                              sourceRange: tok.range)
    case .poundLine:
      consumeToken()
      valExpr = NumExpr(value: IntMax(sourceLoc.line),
                        raw: "\(sourceLoc.line)",
                        sourceRange: tok.range)
    case .poundFunction:
      consumeToken()
      valExpr = PoundFunctionExpr(sourceRange: tok.range)
    case .nil:
      consumeToken()
      valExpr = NilExpr(sourceRange: tok.range)
    case .stringLiteral(let value):
      consumeToken()
      valExpr = StringExpr(value: value,
                           sourceRange: tok.range)
    case .stringInterpolationLiteral(let segments):
      consumeToken()
      let segmentExprs = try segments.map { tokens -> Expr in
        let parser = Parser(tokens: tokens, filename: filename, context: context)
        return try parser.parseValExpr()
      }
      valExpr = StringInterpolationExpr(
        segments: segmentExprs,
        sourceRange: tok.range)
    case .identifier:
      let name = try parseIdentifier()
      var genericParams = [GenericParam]()
      if case .operator(.lessThan) = peek(),
         let genericParamList = try? attempt(try parseGenericParams()) {
        genericParams = genericParamList
      }
      valExpr = VarExpr(name: name, genericParams: genericParams,
                        sourceRange: tok.range)
    case .sizeOf:
      consumeToken()
      var expectRightParen = false
      if case .leftParen = peek() {
        expectRightParen = true
        consumeToken()
      }
      valExpr = SizeofExpr(value: try parseValExpr(),
                           sourceRange: range(start: startLoc))
      if expectRightParen {
        try consume(.rightParen)
      }
    case .leftBrace:
      consumeToken()
      let (args, ret, _) = try parseFuncSignature()
      try consume(.in)
      let exprs = try parseStatements(terminators: [.rightBrace])
      consumeToken()
      valExpr = ClosureExpr(args: args,
                            returnType: ret,
                            body: CompoundStmt(stmts: exprs),
                            sourceRange: range(start: startLoc))
    default:
      throw Diagnostic.error(ParseError.unexpectedExpression(expected: "value"),
                             loc: currentToken().range.start)
                      .highlighting(currentToken().range)
    }
    var expr = valExpr!
    outer: while true {
      switch peek() {
      case .leftParen:
        // Only allow function calls on the same line
        if peek(ahead: -1).isLineSeparator { break outer }
        
        let args = try parseFunCallArgs(open: .leftParen, close: .rightParen)
        expr = FuncCallExpr(lhs: expr, args: args,
                            sourceRange: range(start: startLoc))
      case .dot:
        let dotToken = consumeToken()
        let loc = sourceLoc
        if case .identifier = peek() {
          let field = try parseIdentifier()
          var genericParams = [GenericParam]()
          if case .operator(.lessThan) = peek(),
            let genericParamList = try? attempt(try parseGenericParams()) {
            genericParams = genericParamList
          }
          expr = PropertyRefExpr(lhs: expr,
                                 name: field,
                                 genericParams: genericParams,
                                 dotLoc: dotToken.range.start,
                                 sourceRange: range(start: loc))
        } else if case .number(let n, _) = peek() {
          let tok = consumeToken()
            expr = TupleFieldLookupExpr(lhs: expr, field: Int(n),
                                        fieldRange: tok.range,
                                        sourceRange: range(start: startLoc))
        } else {
          throw unexpectedToken()
        }
      case .leftBracket:
        let args = try parseFunCallArgs(open: .leftBracket, close: .rightBracket)
        expr = SubscriptExpr(lhs: expr,
                             args: args,
                             sourceRange: range(start: startLoc))
      case .questionMark:
        consumeToken()
        let trueVal = try parseValExpr()
        try consume(.colon)
        let falseVal = try parseValExpr()
        expr = TernaryExpr(condition: expr, trueCase: trueVal, falseCase: falseVal,
                           sourceRange: range(start: startLoc))
      case .as:
        let asToken = consumeToken()
        let rhs = try parseType()
        expr = CoercionExpr(lhs: expr, rhs: rhs,
                            asRange: asToken.range,
                            sourceRange: range(start: startLoc))
      case .is:
        let isToken = consumeToken()
        let rhs = try parseType()
        expr = IsExpr(lhs: expr, rhs: rhs,
                      isRange: isToken.range,
                      sourceRange: range(start: startLoc))
      case .operator(let op):
        if op == .star && peek(ahead: -1).isLineSeparator { break outer }

        let opRange = currentToken().range
        consumeToken()
        let val = try parseValExpr()
        if let infix = val as? InfixOperatorExpr, infix.op.infixPrecedence < op.infixPrecedence {
          let r: SourceRange?
          if let exprRange = expr.sourceRange, let lhsRange = infix.lhs.sourceRange {
            r = SourceRange(start: exprRange.start, end: lhsRange.end)
          } else { r = nil }
          expr = InfixOperatorExpr(op: infix.op,
                                   lhs: InfixOperatorExpr(op: op,
                                                          lhs: expr,
                                                          rhs: infix.lhs,
                                                          sourceRange: r),
                                   rhs: infix.rhs,
                                   opRange: opRange,
                                   sourceRange: range(start: startLoc))
        } else if let ternary = val as? TernaryExpr {
          let r: SourceRange?
          if let exprRange = expr.sourceRange, let lhsRange = ternary.condition.sourceRange {
            r = SourceRange(start: exprRange.start, end: lhsRange.end)
          } else { r = nil }
          expr = TernaryExpr(condition: InfixOperatorExpr(op: op,
                                                          lhs: expr,
                                                          rhs: ternary.condition,
                                                          opRange: opRange,
                                                          sourceRange: r),
                             trueCase: ternary.trueCase,
                             falseCase: ternary.falseCase,
                             sourceRange: range(start: startLoc))
        } else {
          expr = InfixOperatorExpr(op: op,
                                   lhs: expr,
                                   rhs: val,
                                   opRange: opRange,
                                   sourceRange: range(start: startLoc))
        }
      default:
        break outer
      }
    }
    return expr
  }
  
  func attachPrefixToInfix(_ prefixOp: BuiltinOperator,
                           prefixRange: SourceRange,
                           startLoc: SourceLocation,
                           expr: InfixOperatorExpr) -> Expr {
    if let infix = expr.lhs as? InfixOperatorExpr {
      let prefix = attachPrefixToInfix(prefixOp, prefixRange: prefixRange,
                                       startLoc: startLoc, expr: infix)
      return InfixOperatorExpr(op: expr.op,
                               lhs: prefix,
                               rhs: expr.rhs,
                               opRange: expr.opRange,
                               sourceRange: range(start: startLoc))
    }
    let r = expr.lhs.sourceRange.map { SourceRange(start: startLoc, end: $0.end) }
    return InfixOperatorExpr(op: expr.op,
                             lhs: PrefixOperatorExpr(op: prefixOp,
                                                     rhs: expr.lhs,
                                                     opRange: prefixRange,
                                                     sourceRange: r),
                             rhs: expr.rhs,
                             opRange: expr.opRange,
                             sourceRange: expr.sourceRange)
  }

  func attachPrefixToIsExpr(_ prefixOp: BuiltinOperator,
                            prefixRange: SourceRange,
                            startLoc: SourceLocation,
                            expr: IsExpr) -> Expr {
    let r = expr.lhs.sourceRange.map {
      SourceRange(start: startLoc, end: $0.end)
    }
    let prefix = PrefixOperatorExpr(op: prefixOp,
                                    rhs: expr.lhs,
                                    opRange: prefixRange,
                                    sourceRange: r)
    return IsExpr(lhs: prefix, rhs: expr.rhs)
  }

  func attachPrefixToCoercionExpr(_ prefixOp: BuiltinOperator,
                                  prefixRange: SourceRange,
                                  startLoc: SourceLocation,
                                  expr: CoercionExpr) -> CoercionExpr {
    let r = expr.lhs.sourceRange.map {
      SourceRange(start: startLoc, end: $0.end)
    }
    let prefix = PrefixOperatorExpr(op: prefixOp,
                                    rhs: expr.lhs,
                                    opRange: prefixRange,
                                    sourceRange: r)
    return CoercionExpr(lhs: prefix, rhs: expr.rhs)
  }

  /// Any token that begins with '>' will be split and re-inserted
  /// into the token stream. This will allow us to accept fully formed
  /// generic specializations that might have an ambiguity with '>>', '>',
  /// or '>='
  func splitAndConsumeIfAngleBracketLike() -> Bool {
    let tok = currentToken()
    let tokDesc: String
    switch tok.kind {
    case .operator(let op):
      tokDesc = op.rawValue
    case .unknown(let value):
      tokDesc = value
    default: return false
    }
    guard tokDesc.hasPrefix(">") else { return false }

    // Consume the >-starting token and create a new token from the end piece

    consumeToken()

    if comesAfterLineSeparator() { return false }
    guard [.leftParen, .leftBracket, .dot, .comma].contains(peek()) else {
      return false
    }
    let newTokDesc = tokDesc.substring(from:
      tokDesc.index(after: tokDesc.startIndex))
    if newTokDesc.characters.count > 0 {
      var newStart = tok.range.start
      newStart.charOffset += 1
      newStart.column += 1
      let newTokKind: TokenKind
      if let op = BuiltinOperator(rawValue: newTokDesc) {
        newTokKind = .operator(op)
      } else {
        newTokKind = .unknown(newTokDesc)
      }
      let newTok = Token(kind: newTokKind,
                         range: SourceRange(start: newStart,
                                            end: tok.range.end))
      var newEnd = tok.range.start
      newEnd.column += 1
      newEnd.charOffset += 1
      let oldTok = Token(kind: .operator(.lessThan),
                         range: SourceRange(start: tok.range.start,
                                            end: newEnd))
      tokens.insert(oldTok, at: tokenIndex - 1)
      tokens[tokenIndex] = newTok
    }
    return true
  }

  func parseGenericParams() throws -> [GenericParam] {
    try consume(.operator(.lessThan))
    var names = [TypeRefExpr]()
    while true {
      let id = try parseType()
      names.append(id)
      if splitAndConsumeIfAngleBracketLike() {
        break
      }
      try consume(.comma)
    }
    return names.map { GenericParam(typeName: $0) }
  }
}
