//
//  ASTPrinter.swift
//  Trill
//

import Foundation

class ASTPrinter<StreamType: TextOutputStream>: ASTTransformer {
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
  
  func writeIndent() {
    stream.write(String(repeating: " ", count: indentLevel))
  }
  
  func indent() {
    indentLevel += 2
  }
  
  func dedent() {
    indentLevel -= 2
  }
  
  func withIndent(_ f: () -> Void) {
    indent()
    f()
    dedent()
  }
  
  override public func run(in context: ASTContext) {
    var topLevel = [ASTNode]()
    topLevel.append(contentsOf: context.globals as [ASTNode])
    topLevel.append(contentsOf: context.types as [ASTNode])
    topLevel.append(contentsOf: context.functions as [ASTNode])
    topLevel.append(contentsOf: context.typeAliases as [ASTNode])
    topLevel.append(contentsOf: context.extensions as [ASTNode])
    topLevel.sort { e1, e2 in
      // foreign and implicit decls show up first
      guard
        let e1Loc = e1.startLoc,
        let e2Loc = e2.startLoc
        else { return true }
      return e1Loc < e2Loc
    }
    for e in topLevel {
      visit(e)
      stream.write("\n\n")
    }
  }
  
  override func visitNumExpr(_ expr: NumExpr) {
    stream.write("\(expr.raw)")
  }
  
  override func visitCharExpr(_ expr: CharExpr) {
    stream.write("'\(Character(UnicodeScalar(expr.value)))'")
  }
  
  override func visitVarExpr(_ expr: VarExpr) {
    stream.write("\(expr.name)")
  }
  
  override func visitVoidExpr(_ expr: VoidExpr) {
    stream.write("")
  }
  
  override func visitBoolExpr(_ expr: BoolExpr) {
    stream.write("\(expr.value)")
  }
  
  override func visitVarAssignDecl(_ decl: VarAssignDecl) {
    for modifier in decl.modifiers {
      stream.write(modifier.rawValue + " ")
    }
    let tok = decl.mutable ? "var" : "let"
    stream.write("\(tok) \(decl.name)")
    if let type = decl.typeRef?.type {
      stream.write(": \(type)")
    }
    if let rhs = decl.rhs {
      stream.write(" = ")
      visit(rhs)
    }
  }
  
  override func visitFuncArgumentAssignDecl(_ decl: FuncArgumentAssignDecl) -> Result {
    if let externalName = decl.externalName {
      stream.write(externalName.name)
    } else {
      stream.write("_")
    }
    if !decl.name.name.isEmpty && decl.name != decl.externalName {
      stream.write(" " + decl.name.name)
    }
    if let type = decl.typeRef {
      stream.write(": " + type.name.name)
    }
  }
  
  override func visitTypeAliasDecl(_ decl: TypeAliasDecl) -> Result {
    stream.write("type \(decl.name) = ")
    visit(decl.bound)
  }
  
  override func visitNilExpr(_ expr: NilExpr) -> Result {
    stream.write("nil")
  }
  
  override func visitSizeofExpr(_ expr: SizeofExpr) {
    stream.write("sizeof(")
    _ = expr.value.map(visit)
    stream.write(")")
  }
  
  override func visitFuncDecl(_ expr: FuncDecl) -> Result {
    for attribute in expr.modifiers {
      stream.write(attribute.rawValue + " ")
    }
    if expr.isInitializer {
      stream.write("init")
    } else {
      stream.write("func \(expr.name)")
    }
    writeSignature(args: expr.args, ret: expr.returnType, hasVarArgs: expr.hasVarArgs)
    stream.write(" ")
    if let body = expr.body { visitCompoundStmt(body) }
  }
  
  func writeSignature(args: [FuncArgumentAssignDecl], ret: TypeRefExpr, hasVarArgs: Bool) {
    stream.write("(")
    for (idx, arg) in args.enumerated() {
      visitFuncArgumentAssignDecl(arg)
      if idx != args.count - 1 || hasVarArgs {
        stream.write(", ")
      }
    }
    if hasVarArgs {
      stream.write("_: ...")
    }
    stream.write(")")
    if ret != .void {
      stream.write(" -> ")
      visit(ret)
    }
  }
  
  override func visitClosureExpr(_ expr: ClosureExpr) -> Result {
    stream.write("{")
    writeSignature(args: expr.args, ret: expr.returnType, hasVarArgs: false)
    stream.write(" in\n")
    withIndent {
      for e in expr.body.exprs {
        writeIndent()
        visit(e)
        stream.write("\n")
      }
    }
    stream.write("}")
  }
  
  override func visitReturnStmt(_ stmt: ReturnStmt) -> Result {
    stream.write("return ")
    visit(stmt.value)
  }
  
  override func visitBreakStmt(_ stmt: BreakStmt) -> Result {
    stream.write("break")
  }
  
  override func visitContinueStmt(_ stmt: ContinueStmt) -> Result {
    stream.write("continue")
  }
  
  override func visitStringExpr(_ expr: StringExpr) {
    stream.write("\"\(expr.value.escaped())\"")
  }
  
  override func visitSubscriptExpr(_ expr: SubscriptExpr) {
    visit(expr.lhs)
    stream.write("[")
    visit(expr.amount)
    stream.write("]")
  }
  
  override func visitTupleExpr(_ expr: TupleExpr) {
    stream.write("(")
    for (idx, value) in expr.values.enumerated() {
      visit(value)
      if idx != expr.values.endIndex - 1 {
        stream.write(", ")
      }
    }
    stream.write(")")
  }
  
  override func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) {
    visit(expr.lhs)
    stream.write(".\(expr.field)")
  }
  
  override func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) {
    stream.write("#function")
  }
  
  override func visitTypeRefExpr(_ expr: TypeRefExpr) -> Result {
    stream.write("\(expr.name)")
  }
  
  override func visitFloatExpr(_ expr: FloatExpr) {
    stream.write("\(expr.value)")
  }
  
  override func visitCompoundStmt(_ stmt: CompoundStmt) -> Result {
    visitCompoundStmt(stmt, braced: true)
  }
  
  func visitCompoundStmt(_ stmt: CompoundStmt, braced: Bool) -> Result {
    if braced {
      stream.write("{")
    }
    stream.write("\n")
    withIndent {
      for e in stmt.exprs {
        writeIndent()
        visit(e)
        stream.write("\n")
      }
    }
    if braced {
      writeIndent()
      stream.write("}")
    }
  }
  
  override func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result {
    visit(expr.lhs)
    stream.write("(")
    for (idx, arg) in expr.args.enumerated() {
      if let label = arg.label {
        stream.write(label.name + ": ")
      }
      visit(arg.val)
      if idx != expr.args.count - 1 {
        stream.write(", ")
      }
    }
    stream.write(")")
  }
  override func visitTypeDecl(_ expr: TypeDecl) -> Result {
    for attribute in expr.modifiers {
      stream.write(attribute.rawValue + " ")
    }
    stream.write("type \(expr.name) {")
    if expr.fields.count + expr.methods.count == 0 {
      stream.write("}")
      return
    }
    stream.write("\n")
    withIndent {
      for field in expr.fields {
        writeIndent()
        visitVarAssignDecl(field)
        stream.write("\n")
      }
      for method in expr.methods {
        writeIndent()
        visitFuncDecl(method)
        stream.write("\n")
      }
    }
    stream.write("}")
  }
  override func visitExtensionDecl(_ expr: ExtensionDecl) -> Result {
    stream.write("extension ")
    visit(expr.typeRef)
    stream.write(" {\n")
    withIndent {
      for method in expr.methods {
        writeIndent()
        visitFuncDecl(method)
        stream.write("\n")
      }
    }
    stream.write("}")
  }
  override func visitWhileStmt(_ stmt: WhileStmt) -> Result {
    stream.write("while ")
    visit(stmt.condition)
    stream.write(" ")
    visitCompoundStmt(stmt.body)
  }
  override func visitForStmt(_ stmt: ForStmt) -> Result {
    stream.write("for ")
    if let initial = stmt.initializer {
      visit(initial)
    }
    stream.write("; ")
    if let cond = stmt.condition {
      visit(cond)
    }
    stream.write("; ")
    if let incr = stmt.incrementer {
      visit(incr)
    }
    stream.write("; ")
    visitCompoundStmt(stmt.body)
  }
  override func visitIfStmt(_ stmt: IfStmt) -> Result {
    var hasPrintedInitial = false
    for (cond, body) in stmt.blocks {
      if hasPrintedInitial {
        stream.write(" else ")
      }
      hasPrintedInitial = true
      stream.write("if ")
      visit(cond)
      stream.write(" ")
      visitCompoundStmt(body)
    }
    if let els = stmt.elseBody {
      stream.write(" else ")
      visitCompoundStmt(els)
    }
  }
  override func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    visit(expr.condition)
    stream.write(" ? ")
    visit(expr.trueCase)
    stream.write(" : ")
    visit(expr.falseCase)
  }
  override func visitSwitchStmt(_ stmt: SwitchStmt) -> Result {
    stream.write("switch ")
    visit(stmt.value)
    stream.write(" {\n")
    for c in stmt.cases {
      writeIndent()
      visitCaseStmt(c)
    }
    if let def = stmt.defaultBody {
      writeIndent()
      stream.write("default:")
      visitCompoundStmt(def, braced: false)
    }
    writeIndent()
    stream.write("}")
  }
  
  override func visitCaseStmt(_ stmt: CaseStmt) -> Result {
    stream.write("case ")
    visit(stmt.constant)
    stream.write(":")
    visitCompoundStmt(stmt.body, braced: false)
  }
  
  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) -> Result {
    visit(expr.lhs)
    stream.write(" \(expr.op) ")
    visit(expr.rhs)
  }
  
  override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) -> Result {
    stream.write("\(expr.op) ")
    visit(expr.rhs)
  }
  
  override func visitFieldLookupExpr(_ expr: FieldLookupExpr) -> Result {
    visit(expr.lhs)
    stream.write(".")
    stream.write(expr.name.name)
  }
  
  override func visitParenExpr(_ expr: ParenExpr) -> Result {
    stream.write("(")
    visit(expr.value)
    stream.write(")")
  }
  
  override func visitPoundDiagnosticStmt(_ stmt: PoundDiagnosticStmt) {
    stream.write("#\(stmt.isError ? "error" : "warning") ")
    visit(stmt.content)
  }
}
