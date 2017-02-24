//
//  ASTWalker.swift
//  Trill
//

import Foundation

// Boy, do I wish that this were automatically generated...

protocol ASTVisitor {
  associatedtype Result
  var context: ASTContext { get }
  @discardableResult
  func visit(_ expr: Expr) -> Result
  @discardableResult
  func visit(_ decl: Decl) -> Result
  @discardableResult
  func visit(_ stmt: Stmt) -> Result
  @discardableResult
  func visit(_ node: ASTNode) -> Result
  @discardableResult
  func visitNumExpr(_ expr: NumExpr) -> Result
  @discardableResult
  func visitCharExpr(_ expr: CharExpr) -> Result
  @discardableResult
  func visitFloatExpr(_ expr: FloatExpr) -> Result
  @discardableResult
  func visitVarExpr(_ expr: VarExpr) -> Result
  @discardableResult
  func visitParenExpr(_ expr: ParenExpr) -> Result
  @discardableResult
  func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) -> Result
  @discardableResult
  func visitVoidExpr(_ expr: VoidExpr) -> Result
  @discardableResult
  func visitArrayExpr(_ expr: ArrayExpr) -> Result
  @discardableResult
  func visitTupleExpr(_ expr: TupleExpr) -> Result
  @discardableResult
  func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) -> Result
  @discardableResult
  func visitNilExpr(_ expr: NilExpr) -> Result
  @discardableResult
  func visitSizeofExpr(_ expr: SizeofExpr) -> Result
  @discardableResult
  func visitTypeRefExpr(_ expr: TypeRefExpr) -> Result
  @discardableResult
  func visitBoolExpr(_ expr: BoolExpr) -> Result
  @discardableResult
  func visitStringExpr(_ expr: StringExpr) -> Result
  @discardableResult
  func visitVarAssignDecl(_ decl: VarAssignDecl) -> Result
  @discardableResult
  func visitParamDecl(_ decl: ParamDecl) -> Result
  @discardableResult
  func visitFuncDecl(_ decl: FuncDecl) -> Result
  @discardableResult
  func visitOperatorDecl(_ decl: OperatorDecl) -> Result
  @discardableResult
  func visitProtocolDecl(_ decl: ProtocolDecl) -> Result
  @discardableResult
  func visitReturnStmt(_ stmt: ReturnStmt) -> Result
  @discardableResult
  func visitBreakStmt(_ stmt: BreakStmt) -> Result
  @discardableResult
  func visitContinueStmt(_ stmt: ContinueStmt) -> Result
  @discardableResult
  func visitSubscriptExpr(_ expr: SubscriptExpr) -> Result
  @discardableResult
  func visitCompoundStmt(_ expr: CompoundStmt) -> Result
  @discardableResult
  func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result
  @discardableResult
  func visitTypeDecl(_ expr: TypeDecl) -> Result
  @discardableResult
  func visitPropertyDecl(_ decl: PropertyDecl) -> Result
  @discardableResult
  func visitTypeAliasDecl(_ decl: TypeAliasDecl) -> Result
  @discardableResult
  func visitExtensionDecl(_ expr: ExtensionDecl) -> Result
  @discardableResult
  func visitWhileStmt(_ expr: WhileStmt) -> Result
  @discardableResult
  func visitForStmt(_ expr: ForStmt) -> Result
  @discardableResult
  func visitIfStmt(_ expr: IfStmt) -> Result
  @discardableResult
  func visitTernaryExpr(_ expr: TernaryExpr) -> Result
  @discardableResult
  func visitCaseStmt(_ expr: CaseStmt) -> Result
  @discardableResult
  func visitExprStmt(_ expr: ExprStmt) -> Result
  @discardableResult
  func visitDeclStmt(_ expr: DeclStmt) -> Result
  @discardableResult
  func visitClosureExpr(_ expr: ClosureExpr) -> Result
  @discardableResult
  func visitSwitchStmt(_ expr: SwitchStmt) -> Result
  @discardableResult
  func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) -> Result
  @discardableResult
  func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) -> Result
  @discardableResult
  func visitPropertyRefExpr(_ expr: PropertyRefExpr) -> Result
  @discardableResult
  func visitPoundDiagnosticStmt(_ expr: PoundDiagnosticStmt) -> Result
}

extension ASTVisitor {
  @discardableResult
  func visit(_ node: ASTNode) -> Result {
    switch node {
    case let decl as Decl:
      return visit(decl)
    case let expr as Expr:
      return visit(expr)
    case let stmt as Stmt:
      return visit(stmt)
    default:
      fatalError("unknown node \(node)")
    }
  }
  @discardableResult
  func visit(_ decl: Decl) -> Result {
    switch decl {
    case let decl as ParamDecl:
      return visitParamDecl(decl)
    case let decl as PropertyDecl:
      return visitPropertyDecl(decl)
    case let decl as VarAssignDecl:
      return visitVarAssignDecl(decl)
    case let decl as OperatorDecl:
      return visitOperatorDecl(decl)
    case let decl as FuncDecl:
      return visitFuncDecl(decl)
    case let decl as ProtocolDecl:
      return visitProtocolDecl(decl)
    case let decl as TypeDecl:
      return visitTypeDecl(decl)
    case let decl as ExtensionDecl:
      return visitExtensionDecl(decl)
    case let decl as TypeAliasDecl:
      return visitTypeAliasDecl(decl)
    default:
      fatalError("unknown decl \(decl)")
    }
  }
  @discardableResult
  func visit(_ stmt: Stmt) -> Result {
    switch stmt {
    case let stmt as ReturnStmt:
      return visitReturnStmt(stmt)
    case let stmt as BreakStmt:
      return visitBreakStmt(stmt)
    case let stmt as ContinueStmt:
      return visitContinueStmt(stmt)
    case let stmt as CompoundStmt:
      return visitCompoundStmt(stmt)
    case let stmt as WhileStmt:
      return visitWhileStmt(stmt)
    case let stmt as ForStmt:
      return visitForStmt(stmt)
    case let stmt as IfStmt:
      return visitIfStmt(stmt)
    case let stmt as SwitchStmt:
      return visitSwitchStmt(stmt)
    case let stmt as CaseStmt:
      return visitCaseStmt(stmt)
    case let stmt as ExprStmt:
      return visitExprStmt(stmt)
    case let stmt as DeclStmt:
      return visitDeclStmt(stmt)
    case let stmt as PoundDiagnosticStmt:
      return visitPoundDiagnosticStmt(stmt)
    default:
      fatalError("unknown stmt \(stmt)")
    }
  }
  @discardableResult
  func visit(_ expr: Expr) -> Result {
    switch expr {
    case let expr as NumExpr:
      return visitNumExpr(expr)
    case let expr as CharExpr:
      return visitCharExpr(expr)
    case let expr as FloatExpr:
      return visitFloatExpr(expr)
    case let expr as BoolExpr:
      return visitBoolExpr(expr)
    case let expr as ArrayExpr:
      return visitArrayExpr(expr)
    case let expr as TupleExpr:
      return visitTupleExpr(expr)
    case let expr as TupleFieldLookupExpr:
      return visitTupleFieldLookupExpr(expr)
    case let expr as SizeofExpr:
      return visitSizeofExpr(expr)
    case let expr as PoundFunctionExpr:
      return visitPoundFunctionExpr(expr)
    case let expr as StringExpr:
      return visitStringExpr(expr)
    case let expr as VarExpr:
      return visitVarExpr(expr)
    case let expr as ParenExpr:
      return visitParenExpr(expr)
    case let expr as SubscriptExpr:
      return visitSubscriptExpr(expr)
    case let expr as FuncCallExpr:
      return visitFuncCallExpr(expr)
    case let expr as TernaryExpr:
      return visitTernaryExpr(expr)
    case let expr as ClosureExpr:
      return visitClosureExpr(expr)
    case let expr as TypeRefExpr:
      return visitTypeRefExpr(expr)
    case let expr as NilExpr:
      return visitNilExpr(expr)
    case let expr as InfixOperatorExpr:
      return visitInfixOperatorExpr(expr)
    case let expr as PrefixOperatorExpr:
      return visitPrefixOperatorExpr(expr)
    case let expr as PropertyRefExpr:
      return visitPropertyRefExpr(expr)
    case let expr as VoidExpr:
      return visitVoidExpr(expr)
    default:
      fatalError("unknown expr \(expr)")
    }
  }
}

public protocol Pass {
  func run(in context: ASTContext) throws
  var title: String { get }
  var context: ASTContext { get }
  init(context: ASTContext)
}

extension ASTVisitor {
  func error(_ err: Error, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    context.error(err, loc: loc, highlights: highlights)
  }
  
  func warning(_ warn: Error, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    context.warning("\(warn)", loc: loc, highlights: highlights)
  }
  
  func warning(_ msg: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    context.warning(msg, loc: loc, highlights: highlights)
  }
  
  func note(_ note: Error, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    context.note("\(note)", loc: loc, highlights: highlights)
  }
  
  func note(_ msg: String, loc: SourceLocation? = nil, highlights: [SourceRange?] = []) {
    context.note(msg, loc: loc, highlights: highlights)
  }
}
