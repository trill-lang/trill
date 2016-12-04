//
//  JavaScriptGen.swift
//  Trill
//

import Foundation

enum JavaScriptError: Error, CustomStringConvertible {
  case unrepresentableExpr
  case unrepresentableType(type: DataType)
  var description: String {
    switch self {
    case .unrepresentableExpr:
      return "expression is not representable in JavaScript"
    case .unrepresentableType(let type):
      return "type '\(type)' is not representable in JavaScript"
    }
  }
}

class JavaScriptGen<StreamType: TextOutputStream>: ASTTransformer {
  var stream: StreamType
  var indent = 0
  
  required init(stream: inout StreamType, context: ASTContext) {
    self.stream = stream
    super.init(context: context)
  }
  
  required init(context: ASTContext) {
    fatalError("must call init(stream:context:)")
  }
  
  func emptyMain() -> FuncDecl {
    return FuncDecl(name: "main",
                        returnType: DataType.void.ref(),
                        args: [],
                        body: CompoundStmt(exprs: []))
  }
  
  override func run(in context: ASTContext) {
    super.run(in: context)
    let mainFunction = context.mainFunction ?? emptyMain()
    stream.write("\n")
    stream.write(Mangler.mangle(mainFunction))
    stream.write("()\n")
  }
  
  func write(_ text: String) {
    stream.write(String(repeating: " ", count: indent) + text)
  }
  
  func withIndent(_ f: () -> Void) {
    indent += 2
    f()
    indent -= 2
  }
  
  func withParens(_ f: () -> Void) {
    stream.write("(")
    f()
    stream.write(")")
  }
  
  override func visitCompoundStmt(_ stmt: CompoundStmt) {
    stream.write("{\n")
    withIndent {
      withScope(stmt) {
        for e in stmt.exprs {
          write("")
          visit(e)
          if (!(e is IfStmt || e is ForStmt || e is WhileStmt)) {
            stream.write(";")
          }
          stream.write("\n")
        }
      }
    }
    write("}")
  }
  
  override func visitClosureExpr(_ expr: ClosureExpr) -> Result {
    stream.write("function (")
    stream.write(expr.args.map { $0.name.name }.joined(separator: ", "))
    stream.write(")")
    visitCompoundStmt(expr.body)
  }
  
  override func visitExtensionDecl(_ expr: ExtensionDecl) {
    for method in expr.methods {
      visitFuncDecl(method)
    }
  }
  
  override func visitFuncDecl(_ expr: FuncDecl) {
    if expr.has(attribute: .foreign) { return }
    let names = expr.args.map { $0.name.name }
    write("function \(Mangler.mangle(expr))(\(names.joined(separator: ", "))) ")
    if expr.isInitializer {
      stream.write("{\n")
      withIndent {
        write("return {\n")
        withIndent {
          for arg in names {
            write("\(arg): \(arg),\n")
          }
        }
        write("}\n")
      }
      stream.write("}\n")
    } else {
      _ = expr.body.map(visitCompoundStmt)
    }
    stream.write("\n")
  }
  
  override func visitReturnStmt(_ expr: ReturnStmt) {
    stream.write("return ")
    visit(expr.value)
  }
  
  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
    withParens {
      if case .as = expr.op {
        visit(expr.lhs)
        return
      }
      
      if let decl = expr.decl,
        !decl.has(attribute: .foreign),
        !decl.has(attribute: .implicit) {
        stream.write(Mangler.mangle(decl))
        stream.write("(")
        visit(expr.lhs)
        stream.write(", ")
        visit(expr.rhs)
        stream.write(")")
        return
      }
      
      visit(expr.lhs)
      stream.write(" \(expr.op.rawValue) ")
      visit(expr.rhs)
    }
  }
  
  override func visitBreakStmt(_ stmt: BreakStmt) {
    stream.write("break")
  }
  
  override func visitContinueStmt(_ stmt: ContinueStmt) {
    stream.write("continue")
  }
  
  override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) {
    if expr.op == .star || expr.op == .ampersand {
      error(JavaScriptError.unrepresentableExpr,
            loc: expr.startLoc,
            highlights: [
              expr.sourceRange
        ])
      return
    }
    stream.write(expr.op.rawValue)
    visit(expr.rhs);
  }
  
  override func visitVarExpr(_ expr: VarExpr) {
    if let funcDecl = expr.decl as? FuncDecl {
      stream.write(Mangler.mangle(funcDecl))
    } else {
      stream.write(expr.name.name)
    }
  }
  
  override func visitNumExpr(_ expr: NumExpr) {
    stream.write("\(expr.value)")
  }
  
  override func visitCharExpr(_ expr: CharExpr) {
    stream.write("\(expr.value)")
  }
  
  override func visitFloatExpr(_ expr: FloatExpr) {
    stream.write("\(expr.value)")
  }
  
  override func visitStringExpr(_ expr: StringExpr) {
    stream.write("\"\(expr.value.escaped())\"")
  }
  
  override func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) {
    visitStringExpr(expr)
  }
  
  override func visitParenExpr(_ expr: ParenExpr) -> Result {
    withParens {
      visit(expr.value)
    }
  }
  
  override func visitSizeofExpr(_ expr: SizeofExpr) -> Result {
    _ = expr.value.map(visit)
    error(JavaScriptError.unrepresentableExpr,
          loc: expr.startLoc,
          highlights: [
            expr.sourceRange
      ])
  }
  
  override func visitTypeDecl(_ expr: TypeDecl) {
    if expr.has(attribute: .foreign) { return }
    super.visitTypeDecl(expr)
  }
  
  override func visitSwitchStmt(_ expr: SwitchStmt) {
    stream.write("switch (")
    visit(expr.value)
    stream.write(") {\n")
    for c in expr.cases {
      visit(c)
    }
    stream.write("\n")
    if let def = expr.defaultBody {
      write("default: ")
      var newExprs = def.exprs
      newExprs.append(BreakStmt())
      visitCompoundStmt(CompoundStmt(exprs: newExprs))
      stream.write("\n")
    }
    stream.write("}")
  }
  
  override func visitCaseStmt(_ expr: CaseStmt) -> Result {
    write("case \(expr.constant.text): ")
    var newExprs = expr.body.exprs
    newExprs.append(BreakStmt())
    visitCompoundStmt(CompoundStmt(exprs: newExprs))
  }
  
  override func visitIfStmt(_ expr: IfStmt) {
    for (idx, (condition, body)) in expr.blocks.enumerated() {
      if idx != 0 {
        stream.write(" else ")
      }
      stream.write("if (")
      visit(condition)
      stream.write(") ")
      visitCompoundStmt(body)
    }
    if let elseBody = expr.elseBody {
      stream.write(" else ")
      visit(elseBody)
    }
  }
  
  override func visitTupleExpr(_ expr: TupleExpr) {
    stream.write("[")
    for (idx, v) in expr.values.enumerated() {
      visit(v)
      if idx < expr.values.count - 1 {
        stream.write(", ")
      }
    }
    stream.write("]")
  }
  
  override func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) {
    visit(expr.lhs)
    stream.write("[\(expr.field)]")
  }
  
  override func visitWhileStmt(_ expr: WhileStmt) {
    stream.write("while (")
    visit(expr.condition)
    stream.write(") ")
    visit(expr.body)
  }
  
  override func visitFuncCallExpr(_ expr: FuncCallExpr) {
    guard let decl = expr.decl else { fatalError("no decl?") }
    if decl.isInitializer {
      stream.write("new ")
    }
    let isMethod = decl.parentType != nil
    let isForeign = decl.has(attribute: .foreign)
    if decl.has(attribute: .implicit) || (isMethod && isForeign) || (decl.isInitializer && isForeign) {
      if expr.lhs is ClosureExpr {
        withParens {
          visit(expr.lhs)
        }
      } else {
        visit(expr.lhs)
      }
    } else {
      let mangled = Mangler.mangle(decl)
      stream.write("\(mangled)")
    }
    stream.write("(")
    if let field = expr.lhs as? FieldLookupExpr, !isForeign {
      visit(field.lhs)
      if expr.args.count > 0 {
        stream.write(", ")
      }
    }
    visitArgs(expr.args)
    stream.write(")")
  }
  
  func visitArgs(_ args: [Argument]) {
    for (i, arg) in args.enumerated() {
      visit(arg.val)
      if i != args.count - 1 {
        stream.write(", ")
      }
    }
  }
  
  override func visitFieldLookupExpr(_ expr: FieldLookupExpr) {
    withParens {
      visit(expr.lhs)
    }
    stream.write(".\(expr.name)")
  }
  
  override func visitBoolExpr(_ expr: BoolExpr) {
    stream.write(expr.value ? "true" : "false")
  }
  
  override func visitNilExpr(_ expr: NilExpr) {
    stream.write("null")
  }
  
  override func visitTernaryExpr(_ expr: TernaryExpr) {
    withParens { visit(expr.condition) }
    stream.write(" ? ")
    withParens { visit(expr.trueCase) }
    stream.write(" : ")
    withParens { visit(expr.falseCase) }
  }
  
  override func visitSubscriptExpr(_ expr: SubscriptExpr) {
    withParens {
      visit(expr.lhs)
    }
    if let decl = expr.decl, !decl.has(attribute: .foreign) {
      visitFuncCallExpr(expr)
    } else {
      stream.write("[")
      visitArgs(expr.args)
      stream.write("]")
    }
  }
  
  override func visitVarAssignDecl(_ decl: VarAssignDecl) {
    if decl.has(attribute: .foreign) { return }
    stream.write("var \(decl.name)")
    if let rhs = decl.rhs {
      stream.write(" = ")
      visit(rhs)
    }
    if currentScope == nil {
      stream.write(";\n")
    }
  }
  
  override func visitForStmt(_ expr: ForStmt) {
    // write the initializer outside the for loop.
    // the Trill scoping rules and validation let us get
    // away with this.
    _ = expr.initializer.map(visit)
    stream.write(";\n")
    write("for (; ")
    _ = expr.condition.map(visit)
    stream.write("; ")
    _ = expr.incrementer.map(visit)
    stream.write(") ")
    visitCompoundStmt(expr.body)
  }
    
  override func visitOperatorDecl(_ decl: OperatorDecl) {
    visitFuncDecl(decl)
  }
}
