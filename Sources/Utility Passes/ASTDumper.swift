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
    printExpr("NumExpr \(expr.value)", expr.startLoc())
  }
  override func visitCharExpr(_ expr: CharExpr) {
    printExpr("CharExpr \(Character(UnicodeScalar(expr.value)))", expr.startLoc())
  }
  override func visitVarExpr(_ expr: VarExpr) {
    printExpr("VarExpr \(expr.name)", expr.startLoc())
  }
  override func visitVoidExpr(_ expr: VoidExpr) {
    printExpr("VoidExpr", expr.startLoc())
  }
  override func visitBoolExpr(_ expr: BoolExpr) {
    printExpr("BoolExpr \(expr.value)", expr.startLoc())
  }
  override func visitVarAssignExpr(_ expr: VarAssignExpr) {
    var s = "VarAssignExpr \(expr.name)"
    if let type = expr.typeRef?.type {
      s += ": \(type)"
    }
    printExpr(s, expr.startLoc()) {
      super.visitVarAssignExpr(expr)
    }
  }
  override func visitFuncArgumentAssignExpr(_ expr: FuncArgumentAssignExpr) -> Result {
    var str = "FuncArgumentAssignExpr "
    if let externalName = expr.externalName {
      str += externalName.name + " "
    }
    str += expr.name.name + " "
    if let type = expr.typeRef {
      str += type.name.name
    }
    printExpr(str, expr.startLoc()) {
      super.visitFuncArgumentAssignExpr(expr)
    }
  }
  override func visitTypeAliasExpr(_ expr: TypeAliasExpr) -> Result {
    printExpr("TypeAliasExpr \(expr.name) \(expr.bound.name)", expr.startLoc())
  }
  
  override func visitFuncDeclExpr(_ expr: FuncDeclExpr) -> Result {
    if expr.has(attribute: .foreign) { return }
    printExpr("FuncDeclExpr \(expr.name) \(expr.returnType.name)", expr.startLoc()) {
      super.visitFuncDeclExpr(expr)
    }
  }
  override func visitClosureExpr(_ expr: ClosureExpr) -> Result {
    printExpr("ClosureExpr \(expr.returnType.name)", expr.startLoc()) {
      super.visitClosureExpr(expr)
    }
  }
  override func visitReturnExpr(_ expr: ReturnExpr) -> Result {
    printExpr("ReturnExpr", expr.startLoc()) {
      super.visitReturnExpr(expr)
    }
  }
  override func visitBreakExpr(_ expr: BreakExpr) -> Result {
    printExpr("BreakExpr", expr.startLoc())
  }
  override func visitContinueExpr(_ expr: ContinueExpr) -> Result {
    printExpr("ContinueExpr", expr.startLoc())
  }
  
  override func visitStringExpr(_ expr: StringExpr) {
    printExpr("StringExpr \"\(expr.value.escaped())\"", expr.startLoc())
  }
  
  override func visitSubscriptExpr(_ expr: SubscriptExpr) {
    printExpr("SubscriptExpr", expr.startLoc()) {
      super.visitSubscriptExpr(expr)
    }
  }
  
  override func visitTypeRefExpr(_ expr: TypeRefExpr) -> Result {
    printExpr("TypeRefExpr \"\(expr.name)\"", expr.startLoc()) {
      super.visitTypeRefExpr(expr)
    }
  }
  
  override func visitFloatExpr(_ expr: FloatExpr) {
    printExpr("FloatExpr \(expr.value)", expr.startLoc())
  }
  
  override func visitCompoundExpr(_ expr: CompoundExpr) -> Result {
    printExpr("CompoundExpr", expr.startLoc()) {
      super.visitCompoundExpr(expr)
    }
  }
  override func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result {
    printExpr("FuncCallExpr", expr.startLoc()) {
      super.visitFuncCallExpr(expr)
    }
  }
  override func visitTypeDeclExpr(_ expr: TypeDeclExpr) -> Result {
    if expr.has(attribute: .foreign) { return }
    printExpr("TypeDeclExpr \(expr.name)", expr.startLoc()) {
      super.visitTypeDeclExpr(expr)
    }
  }
  override func visitExtensionExpr(_ expr: ExtensionExpr) -> Result {
    printExpr("ExtensionExpr \(expr.type!)", expr.startLoc()) {
      super.visitExtensionExpr(expr)
    }
  }
  override func visitWhileExpr(_ expr: WhileExpr) -> Result {
    printExpr("WhileExpr", expr.startLoc()) {
      super.visitWhileExpr(expr)
    }
  }
  override func visitForLoopExpr(_ expr: ForLoopExpr) -> Result {
    printExpr("ForLoopExpr", expr.startLoc()) {
      super.visitForLoopExpr(expr)
    }
  }
  override func visitIfExpr(_ expr: IfExpr) -> Result {
    printExpr("IfExpr", expr.startLoc()) {
      super.visitIfExpr(expr)
    }
  }
  override func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    printExpr("TernaryExpr", expr.startLoc()) {
      super.visitTernaryExpr(expr)
    }
  }
  override func visitSwitchExpr(_ expr: SwitchExpr) -> Result {
    printExpr("SwitchExpr", expr.startLoc()) {
      super.visitSwitchExpr(expr)
    }
  }
  override func visitCaseExpr(_ expr: CaseExpr) -> Result {
    printExpr("CaseExpr", expr.startLoc()) {
      super.visitCaseExpr(expr)
    }
  }
  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) -> Result {
    printExpr("InfixOperatorExpr \(expr.op)", expr.startLoc()) {
      super.visitInfixOperatorExpr(expr)
    }
  }
  override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) -> Result {
    printExpr("PrefixOperatorExpr \(expr.op)", expr.startLoc()) {
      super.visitPrefixOperatorExpr(expr)
    }
  }
  override func visitFieldLookupExpr(_ expr: FieldLookupExpr) -> Result {
    printExpr("FieldLookupExpr \(expr.name)", expr.startLoc()) {
      super.visitFieldLookupExpr(expr)
    }
  }
  override func visitTupleExpr(_ expr: TupleExpr) {
    printExpr("TupleExpr", expr.startLoc()) {
      super.visitTupleExpr(expr)
    }
  }
  override func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) {
    printExpr("TupleFieldLookupExpr \(expr.field)", expr.startLoc()) {
      super.visitTupleFieldLookupExpr(expr)
    }
  }
  override func visitParenExpr(_ expr: ParenExpr) -> Result {
    printExpr("ParenExpr", expr.startLoc()) {
      super.visitParenExpr(expr)
    }
  }
  override func visitPoundDiagnosticExpr(_ expr: PoundDiagnosticExpr) -> () {
    printExpr("PoundDiagnostic \(expr.isError ? "error" : "warning")", expr.startLoc()) {
      super.visitPoundDiagnosticExpr(expr)
    }
  }
}
