//
//  ASTDumper.swift
//  Trill
//

import Foundation

class ASTDumper<StreamType: TextOutputStream>: ASTTransformer {
  typealias Result = Void
  
  var indentLevel = 0
  
  var stream: StreamType
  init(stream: inout StreamType, context: ASTContext) {
    self.stream = stream
    super.init(context: context)
  }
  
  required init(context: ASTContext) {
    fatalError("Cannot instantiate with just context")
  }
  
  func printExpr(_ description: String, _ loc: SourceLocation?, then: (() -> ())? = nil) {
    stream.write(String(repeating: " ", count: indentLevel))
    stream.write("\(description) \(loc?.description ?? "<unknown>")\n")
    if let then = then {
      indent()
      then()
      dedent()
    }
  }
  
  func indent() {
    indentLevel += 2
  }
  
  func dedent() {
    indentLevel -= 2
  }
  
  override func visitNumExpr(_ expr: NumExpr) {
    printExpr("NumExpr \(expr.value)", expr.startLoc)
  }
  override func visitCharExpr(_ expr: CharExpr) {
    printExpr("CharExpr \(Character(UnicodeScalar(expr.value)))", expr.startLoc)
  }
  override func visitVarExpr(_ expr: VarExpr) {
    printExpr("VarExpr \(expr.name)", expr.startLoc)
  }
  override func visitVoidExpr(_ expr: VoidExpr) {
    printExpr("VoidExpr", expr.startLoc)
  }
  override func visitBoolExpr(_ expr: BoolExpr) {
    printExpr("BoolExpr \(expr.value)", expr.startLoc)
  }
  override func visitVarAssignDecl(_ decl: VarAssignDecl) {
    guard decl.startLoc != nil else { return }
    var s = "VarAssignDecl \(decl.name)"
    if let type = decl.typeRef?.type {
      s += ": \(type)"
    }
    printExpr(s, decl.startLoc) {
      super.visitVarAssignDecl(decl)
    }
  }
  override func visitFuncArgumentAssignDecl(_ decl: FuncArgumentAssignDecl) -> Result {
    var str = "FuncArgumentAssignDecl "
    if let externalName = decl.externalName {
      str += externalName.name + " "
    }
    str += decl.name.name + " "
    if let type = decl.typeRef {
      str += type.name.name
    }
    printExpr(str, decl.startLoc) {
      super.visitFuncArgumentAssignDecl(decl)
    }
  }
  override func visitTypeAliasDecl(_ decl: TypeAliasDecl) -> Result {
    guard decl.startLoc != nil else { return }
    printExpr("TypeAliasDecl \(decl.name) \(decl.bound.name)", decl.startLoc)
  }
  
  override func visitFuncDecl(_ expr: FuncDecl) -> Result {
    if expr.has(attribute: .foreign) { return }
    printExpr("FuncDecl \(expr.name) \(expr.returnType.name)", expr.startLoc) {
      super.visitFuncDecl(expr)
    }
  }
  override func visitClosureExpr(_ expr: ClosureExpr) -> Result {
    printExpr("ClosureExpr \(expr.returnType.name)", expr.startLoc) {
      super.visitClosureExpr(expr)
    }
  }
  override func visitReturnStmt(_ stmt: ReturnStmt) -> Result {
    printExpr("ReturnStmt", stmt.startLoc) {
      super.visitReturnStmt(stmt)
    }
  }
  override func visitBreakStmt(_ stmt: BreakStmt) -> Result {
    printExpr("BreakStmt", stmt.startLoc)
  }
  override func visitContinueStmt(_ stmt: ContinueStmt) -> Result {
    printExpr("ContinueStmt", stmt.startLoc)
  }
  
  override func visitStringExpr(_ expr: StringExpr) {
    printExpr("StringExpr \"\(expr.value.escaped())\"", expr.startLoc)
  }
  
  override func visitSubscriptExpr(_ expr: SubscriptExpr) {
    printExpr("SubscriptExpr", expr.startLoc) {
      super.visitSubscriptExpr(expr)
    }
  }
  
  override func visitTypeRefExpr(_ expr: TypeRefExpr) -> Result {
    printExpr("TypeRefExpr \"\(expr.name)\"", expr.startLoc) {
      super.visitTypeRefExpr(expr)
    }
  }
  
  override func visitFloatExpr(_ expr: FloatExpr) {
    printExpr("FloatExpr \(expr.value)", expr.startLoc)
  }
  
  override func visitCompoundStmt(_ stmt: CompoundStmt) -> Result {
    printExpr("CompoundStmt", stmt.startLoc) {
      super.visitCompoundStmt(stmt)
    }
  }
  override func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result {
    printExpr("FuncCallExpr", expr.startLoc) {
      super.visitFuncCallExpr(expr)
    }
  }
  override func visitTypeDecl(_ decl: TypeDecl) -> Result {
    if decl.has(attribute: .foreign) { return }
    printExpr("TypeDecl \(decl.name)", decl.startLoc) {
      super.visitTypeDecl(decl)
    }
  }
  override func visitExtensionDecl(_ decl: ExtensionDecl) -> Result {
    printExpr("ExtensionDecl \(decl.type)", decl.startLoc) {
      super.visitExtensionDecl(decl)
    }
  }
  override func visitWhileStmt(_ stmt: WhileStmt) -> Result {
    printExpr("WhileStmt", stmt.startLoc) {
      super.visitWhileStmt(stmt)
    }
  }
  override func visitForStmt(_ stmt: ForStmt) -> Result {
    printExpr("ForStmt", stmt.startLoc) {
      super.visitForStmt(stmt)
    }
  }
  override func visitIfStmt(_ stmt: IfStmt) -> Result {
    printExpr("IfStmt", stmt.startLoc) {
      super.visitIfStmt(stmt)
    }
  }
  override func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    printExpr("TernaryExpr", expr.startLoc) {
      super.visitTernaryExpr(expr)
    }
  }
  override func visitSwitchStmt(_ stmt: SwitchStmt) -> Result {
    printExpr("SwitchStmt", stmt.startLoc) {
      super.visitSwitchStmt(stmt)
    }
  }
  override func visitCaseStmt(_ stmt: CaseStmt) -> Result {
    printExpr("CaseStmt", stmt.startLoc) {
      super.visitCaseStmt(stmt)
    }
  }
  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) -> Result {
    printExpr("InfixOperatorExpr \(expr.op)", expr.startLoc) {
      super.visitInfixOperatorExpr(expr)
    }
  }
  override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) -> Result {
    printExpr("PrefixOperatorExpr \(expr.op)", expr.startLoc) {
      super.visitPrefixOperatorExpr(expr)
    }
  }
  override func visitFieldLookupExpr(_ expr: FieldLookupExpr) -> Result {
    printExpr("FieldLookupExpr \(expr.name)", expr.startLoc) {
      super.visitFieldLookupExpr(expr)
    }
  }
  override func visitTupleExpr(_ expr: TupleExpr) {
    printExpr("TupleExpr", expr.startLoc) {
      super.visitTupleExpr(expr)
    }
  }
  override func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) {
    printExpr("TupleFieldLookupExpr \(expr.field)", expr.startLoc) {
      super.visitTupleFieldLookupExpr(expr)
    }
  }
  override func visitParenExpr(_ expr: ParenExpr) -> Result {
    printExpr("ParenExpr", expr.startLoc) {
      super.visitParenExpr(expr)
    }
  }
  override func visitPoundDiagnosticStmt(_ stmt: PoundDiagnosticStmt) -> () {
    printExpr("PoundDiagnostic \(stmt.isError ? "error" : "warning")", stmt.startLoc) {
      super.visitPoundDiagnosticStmt(stmt)
    }
  }
}
