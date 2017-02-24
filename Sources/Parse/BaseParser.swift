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
  case unexpectedExpression(expected: String)
  case duplicateDeinit
  case invalidAttribute(DeclModifier, DeclKind)
  case duplicateSetter
  case duplicateGetter
  case computedPropertyRequiresType
  case computedPropertyMustBeMutable
  case globalSubscript
  
  var description: String {
    switch self {
    case .unexpectedToken(let token):
      return "unexpected token '\(token.text)'"
    case .missingLineSeparator:
      return "missing line separator"
    case .expectedIdentifier(let got):
      return "expected identifier (got '\(got.text)')"
    case .duplicateDefault:
      return "only one default statement is allowed in a switch"
    case .unexpectedExpression(let expected):
      return "unexpected expression (expected '\(expected)')"
    case .duplicateDeinit:
      return "cannot have multiple 'deinit's within a type"
    case .invalidAttribute(let attr, let kind):
      return "'\(attr)' is not valid on \(kind)s"
    case .globalSubscript:
      return "subscript is only valid inside a type"
    case .duplicateSetter:
      return "only one setter is allowed per property"
    case .duplicateGetter:
      return "only one getter is allowed per property"
    case .computedPropertyRequiresType:
      return "computed properties require an explicit type"
    case .computedPropertyMustBeMutable:
      return "computed property must be declared with 'var'"
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
    tokenIndex -= 1
  }
  
  func parseTopLevel(into context: ASTContext) throws {
    while true {
      if case .eof = peek() {
        break
      }
      consumeLineSeparators()
      let modifiers = try parseModifiers()
      switch peek() {
      case .poundWarning, .poundError:
        context.add(try parsePoundDiagnosticExpr())
      case .func:
        let decl = try parseFuncDecl(modifiers)
        if let op = decl as? OperatorDecl {
          context.add(op)
        } else {
          context.add(decl)
        }
      case .type:
        let expr = try parseTypeDecl(modifiers)
        if let typeDecl = expr as? TypeDecl {
          context.add(typeDecl)
        } else if let alias = expr as? TypeAliasDecl {
          context.add(alias)
        } else {
          fatalError("non-type expr returned from parseTypeDecl()")
        }
      case .extension:
        context.add(try parseExtensionDecl())
      case .protocol:
        context.add(try parseProtocolDecl(modifiers: modifiers))
      case .var, .let:
        context.add(try parseVarAssignDecl(modifiers: modifiers))
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
  
  func parseModifiers() throws -> [DeclModifier] {
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
    case .func, .Init, .deinit, .operator, .subscript:
      nextKind = .function
    case .var, .let:
      nextKind = .variable
    case .type:
      nextKind = .type
    case .extension:
      nextKind = .extension
    case .protocol:
      nextKind = .protocol
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
    var methods = [MethodDecl]()
    var staticMethods = [MethodDecl]()
    var subscripts = [SubscriptDecl]()
    while true {
      if case .rightBrace = peek() {
        consumeToken()
        break
      }
      let attrs = try parseModifiers()
      switch peek() {
      case .func:
        let decl = try parseFuncDecl(attrs, forType: type.type) as! MethodDecl
        if attrs.contains(.static) {
          staticMethods.append(decl)
        } else {
          methods.append(decl)
        }
      case .subscript:
        subscripts.append(try parseFuncDecl(attrs, forType: type.type) as! SubscriptDecl)
      default:
        throw Diagnostic.error(ParseError.unexpectedExpression(expected: "function or subscript"),
                               loc: sourceLoc)
      }
    }
    return ExtensionDecl(type: type,
                         methods: methods,
                         staticMethods: staticMethods,
                         subscripts: subscripts,
                         sourceRange: range(start: startLoc))
  }
  
  /// Compound Statement
  ///
  /// { [<stmt>]* }
  func parseCompoundStmt(leftBraceOptional: Bool = false) throws -> CompoundStmt {
    let startLoc = sourceLoc
    if leftBraceOptional {
      if case .leftBrace = peek() {
        consumeToken()
      }
    } else {
      try consume(.leftBrace)
    }
    let stmts = try parseStatements(terminators: [.rightBrace])
    consumeToken()
    return CompoundStmt(stmts: stmts, sourceRange: range(start: startLoc))
  }
  
  func parseStatements(terminators: [TokenKind]) throws -> [Stmt] {
    var stmts = [Stmt]()
    while !terminators.contains(peek()) {
      let stmt = try parseStatement()
      if !terminators.contains(peek()) {
        try consumeAtLeastOneLineSeparator()
      }
      if let diag = stmt as? PoundDiagnosticStmt {
        context.add(diag)
      } else {
        stmts.append(stmt)
      }
    }
    return stmts
  }
  
  func parseStatement() throws -> Stmt {
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
      return DeclStmt(decl: try parseVarAssignDecl())
    case .break:
      return try parseBreakStmt()
    case .continue:
      return try parseContinueStmt()
    case .return:
      return try parseReturnStmt()
    case .poundError, .poundWarning:
      return try parsePoundDiagnosticExpr()
    default:
      return ExprStmt(expr: try parseValExpr())
    }
  }
}
