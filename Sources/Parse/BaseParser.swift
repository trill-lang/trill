//
//  Parser.swift
//  Trill
//

import Foundation

enum ParseError: Error, CustomStringConvertible {
  case unexpectedToken(token: TokenKind)
  case missingLineSeparator
  case expectedIdentifier(got: TokenKind)
  case duplicateDefault
  case caseMustBeConstant
  case unexpectedExpression(expected: String)
  case duplicateDeinit
  case invalidAttribute(DeclModifier, DeclKind)
  
  var description: String {
    switch self {
    case .unexpectedToken(let token):
      return "unexpected token '\(token.text)'"
    case .missingLineSeparator:
      return "missing line separator"
    case .expectedIdentifier(let got):
      return "expected identifier (got '\(got.text)')"
    case .caseMustBeConstant:
      return "case statement expressions must be constants"
    case .duplicateDefault:
      return "only one default statement is allowed in a switch"
    case .unexpectedExpression(let expected):
      return "unexpected expression (expected '\(expected)')"
    case .duplicateDeinit:
      return "cannot have multiple 'deinit's within a type"
    case .invalidAttribute(let attr, let kind):
      return "'\(attr)' is not valid on \(kind)s"
    }
  }
}

class Parser {
  var tokenIndex = 0
  var tokens: [Token]
  let filename: String
  let context: ASTContext
  
  init(tokens: [Token], filename: String, context: ASTContext) {
    self.tokens = tokens
    self.filename = filename
    self.context = context
  }
  
  func adjustedEnd() -> SourceLocation {
    if (tokens.indices).contains(tokenIndex - 1)  {
      let t = tokens[tokenIndex - 1]
      return t.range.end
    } else {
      return SourceLocation(line: 1, column: 1)
    }
  }
  
  func missingLineSeparator() -> Error {
    let end = adjustedEnd()
    return Diagnostic.error(ParseError.missingLineSeparator,
                            loc: end)
  }
  
  func unexpectedToken() -> Error {
    let end = adjustedEnd()
    return Diagnostic.error(ParseError.unexpectedToken(token: peek()),
                            loc: end,
                            highlights: [
                              currentToken().range
                        ])
  }
  
  func attempt<T>(_ block: @autoclosure () throws -> T) throws -> T {
    let startIndex = tokenIndex
    do {
      return try block()
    } catch {
      tokenIndex = startIndex
      throw error
    }
  }
  
  func range(start: SourceLocation) -> SourceRange {
    let end: SourceLocation
    if (tokens.indices).contains(tokenIndex - 1)  {
      let t = tokens[tokenIndex - 1]
      end = t.range.end
    } else {
      end = start
    }
    return SourceRange(start: start, end: end)
  }
  
  var sourceLoc: SourceLocation {
    return currentToken().range.start
  }
  
  func consume(_ token: TokenKind) throws {
    guard token == peek() else {
      throw unexpectedToken()
    }
    consumeToken()
  }
  
  func consumeAtLeastOneLineSeparator() throws {
    if case .eof = peek() { return }
    if [.newline, .semicolon].contains(peek()) {
      consumeToken()
    } else if ![.newline, .semicolon].contains(peek(ahead: -1)) {
      throw missingLineSeparator()
    }
    consumeLineSeparators()
  }
  func consumeLineSeparators() {
    while [.newline, .semicolon].contains(peek()) {
      tokenIndex += 1
    }
  }
  
  func comesAfterLineSeparator() -> Bool {
    var n = -1
    while case .semicolon = peek(ahead: n) {
      n -= 1
    }
    return peek(ahead: n) == .newline
  }
  
  func peek(ahead offset: Int = 0) -> TokenKind {
    let idx = tokenIndex + offset
    guard tokens.indices.contains(idx) else {
      return .eof
    }
    return tokens[idx].kind
  }
  
  func currentToken() -> Token {
    guard tokens.indices.contains(tokenIndex) else {
      return Token(kind: .eof,
                   range: .zero)
    }
    return tokens[tokenIndex]
  }
  
  @discardableResult
  func consumeToken() -> Token {
    let c = currentToken()
    tokenIndex += 1
    while case .newline = peek() {
      tokenIndex += 1
    }
    return c
  }
  
  func backtrack(_ n: Int = 1) {
    tokenIndex -= n
  }
  
  func parseTopLevel(into context: ASTContext) throws {
    while true {
      if case .eof = peek() {
        break
      }
      consumeLineSeparators()
      let attrs = try parseAttributes()
      switch peek() {
      case .poundWarning, .poundError:
        context.add(try parsePoundDiagnosticExpr())
      case .func:
        let decl = try parseFuncDecl(attrs)
        if let op = decl as? OperatorDecl {
          context.add(op)
        } else {
          context.add(decl)
        }
      case .type:
        let expr = try parseTypeDecl(attrs)
        if let typeDecl = expr as? TypeDecl {
          context.add(typeDecl)
        } else if let alias = expr as? TypeAliasDecl {
          context.add(alias)
        } else {
          fatalError("non-type expr returned from parseTypeDecl()")
        }
      case .extension:
        context.add(try parseExtensionDecl())
      case .var, .let:
        context.add(try parseVarAssignDecl(attrs))
      default:
        throw Diagnostic.error(
          ParseError.unexpectedExpression(expected: "function, type, or extension"),
          loc: sourceLoc)
      }
      try consumeAtLeastOneLineSeparator()
    }
  }
  
  func parseIdentifier() throws -> Identifier {
    guard case .identifier(let name) = peek() else {
      throw Diagnostic.error(ParseError.expectedIdentifier(got: peek()),
                             loc: sourceLoc)
    }
    return Identifier(name: name, range: consumeToken().range)
  }
  
  func parseAttributes() throws -> [DeclModifier] {
    var attrs = [DeclModifier]()
    while case .identifier(let attrId) = peek() {
      if let attr = DeclModifier(rawValue: attrId) {
        consumeToken()
        attrs.append(attr)
      } else {
        throw Diagnostic.error(ParseError.expectedIdentifier(got: peek()),
                               loc: sourceLoc)
      }
    }
    let nextKind: DeclKind
    switch peek() {
    case .func, .Init, .deinit, .operator:
      nextKind = .function
    case .var, .let:
      nextKind = .variable
    case .type:
      nextKind = .type
    case .extension:
      nextKind = .extension
    case .poundWarning, .poundError:
      nextKind = .diagnostic
    default:
      throw unexpectedToken()
    }
    for attr in attrs {
      if !attr.isValid(on: nextKind) {
        throw Diagnostic.error(ParseError.invalidAttribute(attr, nextKind),
                               loc: sourceLoc)
      }
    }
    return attrs
  }
  
  func parseExtensionDecl() throws -> ExtensionDecl {
    let startLoc = sourceLoc
    try consume(.extension)
    let type = try parseType()
    guard case .leftBrace = peek() else {
      throw unexpectedToken()
    }
    consumeToken()
    var methods = [FuncDecl]()
    while true {
      if case .rightBrace = peek() {
        consumeToken()
        break
      }
      let attrs = try parseAttributes()
      guard case .func = peek()  else {
        throw Diagnostic.error(ParseError.unexpectedExpression(expected: "function"),
                               loc: sourceLoc)
      }
      methods.append(try parseFuncDecl(attrs, forType: type.type))
    }
    return ExtensionDecl(type: type, methods: methods,
                         sourceRange: range(start: startLoc))
  }
  
  /// Type Declaration
  ///
  /// type-decl ::= type <typename> {
  ///   [<field-decl> | <func-decl>]*
  /// }
  func parseTypeDecl(_ modifiers: [DeclModifier]) throws -> ASTNode {
    try consume(.type)
    let startLoc = sourceLoc
    let name = try parseIdentifier()
    
    if case .operator(op: .assign) = peek() {
      consumeToken()
      let bound = try parseType()
      return TypeAliasDecl(name: name,
                           bound: bound,
                           sourceRange: range(start: startLoc))
    }
    try consume(.leftBrace)
    var fields = [VarAssignDecl]()
    var methods = [FuncDecl]()
    var initializers = [FuncDecl]()
    var deinitializer: FuncDecl?
    let type = DataType(name: name.name)
    loop: while true {
      if case .rightBrace = peek() {
        consumeToken()
        break
      }
      let attrs = try parseAttributes()
      switch peek() {
      case .poundError, .poundWarning:
        context.add(try parsePoundDiagnosticExpr())
      case .func:
        methods.append(try parseFuncDecl(attrs, forType: type))
      case .Init:
        initializers.append(try parseFuncDecl(attrs, forType: type))
      case .var, .let:
        fields.append(try parseVarAssignDecl(attrs))
      case .deinit:
        if deinitializer != nil {
          throw Diagnostic.error(ParseError.duplicateDeinit, loc: sourceLoc)
        }
        deinitializer = try parseFuncDecl(modifiers, forType:type, isDeinit: true)
      default:
        throw unexpectedToken()
      }
      try consumeAtLeastOneLineSeparator()
    }
    return TypeDecl(name: name, fields: fields, methods: methods,
                        initializers: initializers,
                        modifiers: modifiers,
                        deinit: deinitializer,
                        sourceRange: range(start: startLoc))
  }
  
  /// Braced Expression Block
  ///
  /// { [<if-expr> | <while-expr> | <var-assign-expr> | <return-expr> | <val-expr>];* }
  func parseCompoundExpr() throws -> CompoundStmt {
    let startLoc = sourceLoc
    try consume(.leftBrace)
    let exprs = try parseStatementExprs(terminators: [.rightBrace])
    consumeToken()
    return CompoundStmt(exprs: exprs, sourceRange: range(start: startLoc))
  }
  
  func parseStatementExprs(terminators: [TokenKind]) throws -> [ASTNode] {
    var exprs = [ASTNode]()
    while !terminators.contains(peek()) {
      let expr = try parseStatementExpr()
      if !terminators.contains(peek()) {
        try consumeAtLeastOneLineSeparator()
      }
      if let diag = expr as? PoundDiagnosticStmt {
        context.add(diag)
      } else {
        exprs.append(expr)
      }
    }
    return exprs
  }
  
  func parseStatementExpr() throws -> ASTNode {
    let tok = peek()
    switch tok {
    case .if:
      return try parseIfExpr()
    case .while:
      return try parseWhileExpr()
    case .for:
      return try parseForLoopExpr()
    case .switch:
      return try parseSwitchExpr()
    case .var, .let:
      return try parseVarAssignDecl()
    case .break:
      return try parseBreakStmt()
    case .continue:
      return try parseContinueStmt()
    case .return:
      return try parseReturnExpr()
    case .poundError, .poundWarning:
      return try parsePoundDiagnosticExpr()
    default:
      return try parseValExpr()
    }
  }
}
