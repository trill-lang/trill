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
    var topLevel = [Expr]()
    topLevel.append(contentsOf: context.globals as [Expr])
    topLevel.append(contentsOf: context.types as [Expr])
    topLevel.append(contentsOf: context.functions as [Expr])
    topLevel.append(contentsOf: context.typeAliases as [Expr])
    topLevel.append(contentsOf: context.extensions as [Expr])
    topLevel.sort { e1, e2 in
      // foreign and implicit decls show up first
      guard
        let e1Loc = e1.startLoc(),
        let e2Loc = e2.startLoc()
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
  
  override func visitVarAssignExpr(_ expr: VarAssignExpr) {
    for attribute in expr.attributes {
      stream.write(attribute.rawValue + " ")
    }
    let tok = expr.mutable ? "var" : "let"
    stream.write("\(tok) \(expr.name)")
    if let type = expr.typeRef?.type {
      stream.write(": \(type)")
    }
    if let rhs = expr.rhs {
      stream.write(" = ")
      visit(rhs)
    }
  }
  
  override func visitFuncArgumentAssignExpr(_ expr: FuncArgumentAssignExpr) -> Result {
    if let externalName = expr.externalName {
      stream.write(externalName.name)
    } else {
      stream.write("_")
    }
    if !expr.name.name.isEmpty && expr.name != expr.externalName {
      stream.write(" " + expr.name.name)
    }
    if let type = expr.typeRef {
      stream.write(": " + type.name.name)
    }
  }
  
  override func visitTypeAliasExpr(_ expr: TypeAliasExpr) -> Result {
    stream.write("type \(expr.name) = ")
    visit(expr.bound)
  }
  
  override func visitNilExpr(_ expr: NilExpr) -> Result {
    stream.write("nil")
  }
  
  override func visitSizeofExpr(_ expr: SizeofExpr) {
    stream.write("sizeof(")
    _ = expr.value.map(visit)
    stream.write(")")
  }
  
  override func visitFuncDeclExpr(_ expr: FuncDeclExpr) -> Result {
    for attribute in expr.attributes {
      stream.write(attribute.rawValue + " ")
    }
    if expr.isInitializer {
      stream.write("init")
    } else {
      stream.write("func \(expr.name)")
    }
    writeSignature(args: expr.args, ret: expr.returnType, hasVarArgs: expr.hasVarArgs)
    stream.write(" ")
    if let body = expr.body { visitCompoundExpr(body) }
  }
  
  func writeSignature(args: [FuncArgumentAssignExpr], ret: TypeRefExpr, hasVarArgs: Bool) {
    stream.write("(")
    for (idx, arg) in args.enumerated() {
      visitFuncArgumentAssignExpr(arg)
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
  
  override func visitReturnExpr(_ expr: ReturnExpr) -> Result {
    stream.write("return ")
    visit(expr.value)
  }
  
  override func visitBreakExpr(_ expr: BreakExpr) -> Result {
    stream.write("break")
  }
  
  override func visitContinueExpr(_ expr: ContinueExpr) -> Result {
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
  
  override func visitCompoundExpr(_ expr: CompoundExpr) -> Result {
    visitCompoundExpr(expr, braced: true)
  }
  
  func visitCompoundExpr(_ expr: CompoundExpr, braced: Bool) -> Result {
    if braced {
      stream.write("{")
    }
    stream.write("\n")
    withIndent {
      for e in expr.exprs {
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
  override func visitTypeDeclExpr(_ expr: TypeDeclExpr) -> Result {
    for attribute in expr.attributes {
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
        visitVarAssignExpr(field)
        stream.write("\n")
      }
      for method in expr.methods {
        writeIndent()
        visitFuncDeclExpr(method)
        stream.write("\n")
      }
    }
    stream.write("}")
  }
  override func visitExtensionExpr(_ expr: ExtensionExpr) -> Result {
    stream.write("extension ")
    visit(expr.typeRef)
    stream.write(" {\n")
    withIndent {
      for method in expr.methods {
        writeIndent()
        visitFuncDeclExpr(method)
        stream.write("\n")
      }
    }
    stream.write("}")
  }
  override func visitWhileExpr(_ expr: WhileExpr) -> Result {
    stream.write("while ")
    visit(expr.condition)
    stream.write(" ")
    visitCompoundExpr(expr.body)
  }
  override func visitForLoopExpr(_ expr: ForLoopExpr) -> Result {
    stream.write("for ")
    if let initial = expr.initializer {
      visit(initial)
    }
    stream.write("; ")
    if let cond = expr.condition {
      visit(cond)
    }
    stream.write("; ")
    if let incr = expr.incrementer {
      visit(incr)
    }
    stream.write("; ")
    visitCompoundExpr(expr.body)
  }
  override func visitIfExpr(_ expr: IfExpr) -> Result {
    var hasPrintedInitial = false
    for (cond, body) in expr.blocks {
      if hasPrintedInitial {
        stream.write(" else ")
      }
      hasPrintedInitial = true
      stream.write("if ")
      visit(cond)
      stream.write(" ")
      visitCompoundExpr(body)
    }
    if let els = expr.elseBody {
      stream.write(" else ")
      visitCompoundExpr(els)
    }
  }
  override func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    visit(expr.condition)
    stream.write(" ? ")
    visit(expr.trueCase)
    stream.write(" : ")
    visit(expr.falseCase)
  }
  override func visitSwitchExpr(_ expr: SwitchExpr) -> Result {
    stream.write("switch ")
    visit(expr.value)
    stream.write(" {\n")
    for c in expr.cases {
      writeIndent()
      visitCaseExpr(c)
    }
    if let def = expr.defaultBody {
      writeIndent()
      stream.write("default:")
      visitCompoundExpr(def, braced: false)
    }
    writeIndent()
    stream.write("}")
  }
  
  override func visitCaseExpr(_ expr: CaseExpr) -> Result {
    stream.write("case ")
    visit(expr.constant)
    stream.write(":")
    visitCompoundExpr(expr.body, braced: false)
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
  
  override func visitPoundDiagnosticExpr(_ expr: PoundDiagnosticExpr) {
    stream.write("#\(expr.isError ? "error" : "warning") ")
    visit(expr.content)
  }
}
