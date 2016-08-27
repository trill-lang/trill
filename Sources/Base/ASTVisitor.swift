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
  func visitVarAssignExpr(_ expr: VarAssignExpr) -> Result
  @discardableResult
  func visitFuncArgumentAssignExpr(_ expr: FuncArgumentAssignExpr) -> Result
  @discardableResult
  func visitFuncDeclExpr(_ expr: FuncDeclExpr) -> Result
  @discardableResult
  func visitReturnExpr(_ expr: ReturnExpr) -> Result
  @discardableResult
  func visitBreakExpr(_ expr: BreakExpr) -> Result
  @discardableResult
  func visitContinueExpr(_ expr: ContinueExpr) -> Result
  @discardableResult
  func visitSubscriptExpr(_ expr: SubscriptExpr) -> Result
  @discardableResult
  func visitCompoundExpr(_ expr: CompoundExpr) -> Result
  @discardableResult
  func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result
  @discardableResult
  func visitTypeDeclExpr(_ expr: TypeDeclExpr) -> Result
  @discardableResult
  func visitTypeAliasExpr(_ expr: TypeAliasExpr) -> Result
  @discardableResult
  func visitExtensionExpr(_ expr: ExtensionExpr) -> Result
  @discardableResult
  func visitWhileExpr(_ expr: WhileExpr) -> Result
  @discardableResult
  func visitForLoopExpr(_ expr: ForLoopExpr) -> Result
  @discardableResult
  func visitIfExpr(_ expr: IfExpr) -> Result
  @discardableResult
  func visitTernaryExpr(_ expr: TernaryExpr) -> Result
  @discardableResult
  func visitCaseExpr(_ expr: CaseExpr) -> Result
  @discardableResult
  func visitClosureExpr(_ expr: ClosureExpr) -> Result
  @discardableResult
  func visitSwitchExpr(_ expr: SwitchExpr) -> Result
  @discardableResult
  func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) -> Result
  @discardableResult
  func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) -> Result
  @discardableResult
  func visitFieldLookupExpr(_ expr: FieldLookupExpr) -> Result
  @discardableResult
  func visitPoundDiagnosticExpr(_ expr: PoundDiagnosticExpr) -> Result
}

extension ASTVisitor {
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
    case let expr as FuncArgumentAssignExpr:
      return visitFuncArgumentAssignExpr(expr)
    case let expr as VarAssignExpr:
      return visitVarAssignExpr(expr)
    case let expr as FuncDeclExpr:
      return visitFuncDeclExpr(expr)
    case let expr as ReturnExpr:
      return visitReturnExpr(expr)
    case let expr as BreakExpr:
      return visitBreakExpr(expr)
    case let expr as ContinueExpr:
      return visitContinueExpr(expr)
    case let expr as SubscriptExpr:
      return visitSubscriptExpr(expr)
    case let expr as CompoundExpr:
      return visitCompoundExpr(expr)
    case let expr as FuncCallExpr:
      return visitFuncCallExpr(expr)
    case let expr as TypeDeclExpr:
      return visitTypeDeclExpr(expr)
    case let expr as TypeAliasExpr:
      return visitTypeAliasExpr(expr)
    case let expr as ExtensionExpr:
      return visitExtensionExpr(expr)
    case let expr as WhileExpr:
      return visitWhileExpr(expr)
    case let expr as ForLoopExpr:
      return visitForLoopExpr(expr)
    case let expr as IfExpr:
      return visitIfExpr(expr)
    case let expr as TernaryExpr:
      return visitTernaryExpr(expr)
    case let expr as SwitchExpr:
      return visitSwitchExpr(expr)
    case let expr as CaseExpr:
      return visitCaseExpr(expr)
    case let expr as ClosureExpr:
      return visitClosureExpr(expr)
    case let expr as TypeRefExpr:
      return visitTypeRefExpr(expr)
    case let expr as PoundDiagnosticExpr:
      return visitPoundDiagnosticExpr(expr)
    case let expr as NilExpr:
      return visitNilExpr(expr)
    case let expr as InfixOperatorExpr:
      return visitInfixOperatorExpr(expr)
    case let expr as PrefixOperatorExpr:
      return visitPrefixOperatorExpr(expr)
    case let expr as FieldLookupExpr:
      return visitFieldLookupExpr(expr)
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
}
