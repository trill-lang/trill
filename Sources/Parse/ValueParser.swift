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
    case .float(let left, let right, let raw):
      consumeToken()
      let newValue: Double = Double(left) + (Double(right) / 100.0)
      valExpr = FloatExpr(value: newValue,
                          raw: raw,
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
      valExpr = StringExpr(value: filename,
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
    case .identifier:
      let name = try parseIdentifier()
      valExpr = VarExpr(name: name, sourceRange: tok.range)
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
      let exprs = try parseStatementExprs(terminators: [.rightBrace])
      consumeToken()
      valExpr = ClosureExpr(args: args,
                            returnType: ret,
                            body: CompoundStmt(exprs: exprs),
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
        
        let args = try parseFunCallArgs()
        expr = FuncCallExpr(lhs: expr, args: args,
                            sourceRange: range(start: startLoc))
      case .dot:
        consumeToken()
        let loc = sourceLoc
        if case .identifier = peek() {
          let field = try parseIdentifier()
          expr = FieldLookupExpr(lhs: expr,
                                 name: field,
                                 sourceRange: range(start: loc))
        } else if case .number(let n, _) = peek() {
          let tok = consumeToken()
          expr = TupleFieldLookupExpr(lhs: expr, field: Int(n), fieldRange: tok.range)
        } else {
          throw unexpectedToken()
        }
      case .leftBracket:
        consumeToken()
        let val = try parseValExpr()
        guard case .rightBracket = peek() else {
          throw unexpectedToken()
        }
        consumeToken()
        expr = SubscriptExpr(lhs: expr,
                             amount: val,
                             sourceRange: range(start: startLoc))
      case .questionMark:
        consumeToken()
        let trueVal = try parseValExpr()
        try consume(.colon)
        let falseVal = try parseValExpr()
        expr = TernaryExpr(condition: expr, trueCase: trueVal, falseCase: falseVal,
                           sourceRange: range(start: startLoc))
      case .operator(let op):
        if op == .star && peek(ahead: -1).isLineSeparator { break outer }
        let opRange = currentToken().range
        consumeToken()
        let val: Expr
        if [.as, .is].contains(op) {
          val = try parseType()
        } else {
          val = try parseValExpr()
        }
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
  
  func attachPrefixToInfix(_ prefixOp: BuiltinOperator, prefixRange: SourceRange, startLoc: SourceLocation, expr: InfixOperatorExpr) -> Expr {
    if let infix = expr.lhs as? InfixOperatorExpr {
      let prefix = attachPrefixToInfix(prefixOp, prefixRange: prefixRange, startLoc: startLoc, expr: infix)
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
}
