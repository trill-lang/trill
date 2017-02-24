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
                        body: CompoundStmt(stmts: []))
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
    writeCompoundBody(stmt)
    write("}")
  }
  
  func writeCompoundBody(_ stmt: CompoundStmt) {
    withIndent {
      withScope(stmt) {
        for e in stmt.stmts {
          write("")
          visit(e)
          if (!(e is IfStmt || e is ForStmt || e is WhileStmt || e is SwitchStmt)) {
            stream.write(";")
          }
          stream.write("\n")
        }
      }
    }

  }
  
  override func visitClosureExpr(_ expr: ClosureExpr) -> Result {
    stream.write("function (")
    stream.write(expr.args.map { $0.name.name }.joined(separator: ", "))
    stream.write(")")
    visitCompoundStmt(expr.body)
  }
  
  override func visitExtensionDecl(_ expr: ExtensionDecl) {
    for method in expr.methods + expr.staticMethods {
      visitFuncDecl(method)
    }
  }
  
  override func visitFuncDecl(_ expr: FuncDecl) {
    if expr.has(attribute: .foreign) { return }
    let names = expr.args.map { $0.name.name }
    write("function \(Mangler.mangle(expr))(\(names.joined(separator: ", "))) ")
    if expr is InitializerDecl {
      stream.write("{\n")
      if expr.has(attribute: .implicit) {
        withIndent {
          write("return {\n")
          withIndent {
            for arg in names {
              write("\(arg): \(arg),\n")
            }
          }
          write("};\n")
        }
      } else {
        withIndent {
          write("var self = {};\n")
        }
        if let body = expr.body {
          writeCompoundBody(body)
        }
        withIndent {
          write("return self;\n")
        }
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
    let emit: () -> Void = {
      if case .as = expr.op {
        self.visit(expr.lhs)
        return
      }
      
      if let decl = expr.decl,
        !decl.has(attribute: .foreign),
        !decl.has(attribute: .implicit) {
        self.stream.write(Mangler.mangle(decl))
        self.stream.write("(")
        self.visit(expr.lhs)
        self.stream.write(", ")
        self.visit(expr.rhs)
        self.stream.write(")")
        return
      }
      
      self.visit(expr.lhs)
      self.stream.write(" \(expr.op.rawValue) ")
      self.visit(expr.rhs)
    }

    if case .assign = expr.op,
      let propRef = expr.lhs as? PropertyRefExpr,
      let decl = propRef.decl as? PropertyDecl,
      let setter = decl.setter {
      let call = FuncCallExpr(lhs: expr.lhs, args: [Argument(val: expr.rhs)])
      call.decl = setter
      visitFuncCallExpr(call)
      return
    }
    
    if expr.op.isAssign {
      emit()
    } else {
      withParens(emit)
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
      var newExprs = def.stmts
      newExprs.append(BreakStmt())
      visitCompoundStmt(CompoundStmt(stmts: newExprs))
      stream.write("\n")
    }
    stream.write("}")
  }
  
  override func visitCaseStmt(_ expr: CaseStmt) -> Result {
    let text: String
    if let varExpr = expr.constant as? VarExpr {
      text = varExpr.name.name
    } else if let constant = expr.constant as? ConstantExpr {
      text = constant.text
    } else {
      fatalError("invalid case expr?")
    }
    write("case \(text): ")
    var newExprs = expr.body.stmts
    newExprs.append(BreakStmt())
    visitCompoundStmt(CompoundStmt(stmts: newExprs))
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
    let isInitializer = decl is InitializerDecl
    let isMethod = decl is MethodDecl
    let isForeign = decl.has(attribute: .foreign)
    if isInitializer {
      stream.write("new ")
    }
    if let initDecl = decl as? InitializerDecl, isForeign {
      stream.write("\(initDecl.parentType)")
    } else if isMethod && isForeign && !isInitializer {
      visit(expr.lhs)
    } else if let lhs = expr.lhs as? ClosureExpr {
      withParens {
        visit(lhs)
      }
    } else if let lhs = expr.lhs as? VarExpr,
           case .local? = (lhs.decl as? VarAssignDecl)?.kind {
      stream.write(lhs.name.name)
    } else {
      let mangled = Mangler.mangle(decl)
      stream.write("\(mangled)")
    }
    stream.write("(")
    if let property = expr.lhs as? PropertyRefExpr, !isForeign {
      visit(property.lhs)
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
  
  override func visitPropertyRefExpr(_ expr: PropertyRefExpr) {
    if let prop = expr.decl as? PropertyDecl,
       let getter = prop.getter {
      let call = FuncCallExpr(lhs: expr, args: [])
      call.decl = getter
      return visitFuncCallExpr(call)
    }
    if expr.lhs is VarExpr {
      visit(expr.lhs)
    } else {
      withParens {
        visit(expr.lhs)
      }
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
    if currentType != nil && currentFunction == nil { return }
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
