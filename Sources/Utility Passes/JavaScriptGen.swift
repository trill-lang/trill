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
  
  func jsTypeName(_ type: DataType) -> String {
    switch type {
    case .int: return "Number"
    case .bool: return "Boolean"
    case .custom(let name): return name
    default:
      fatalError("cannot represent \(type) in javascript")
    }
  }
  
  required init(context: ASTContext) {
    fatalError("must call init(stream:context:)")
  }
  
  func emptyMain() -> FuncDeclExpr {
    return FuncDeclExpr(name: "main",
                        returnType: DataType.void.ref(),
                        args: [],
                        body: CompoundExpr(exprs: []))
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
  
  override func visitCompoundExpr(_ expr: CompoundExpr) {
    stream.write("{\n")
    withIndent {
      withScope(expr) {
        for e in expr.exprs {
          write("")
          visit(e)
          if (!(e is IfExpr || e is ForLoopExpr || e is WhileExpr)) {
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
    visitCompoundExpr(expr.body) // JavaScript...
  }
  
  override func visitExtensionExpr(_ expr: ExtensionExpr) {
    for method in expr.methods {
      visitFuncDeclExpr(method)
    }
  }
  
  override func visitFuncDeclExpr(_ expr: FuncDeclExpr) {
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
      _ = expr.body.map(visitCompoundExpr)
    }
    stream.write("\n")
  }
  
  override func visitReturnExpr(_ expr: ReturnExpr) {
    stream.write("return ")
    visit(expr.value)
  }
  
  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
    withParens {
      if case .as = expr.op {
        visit(expr.lhs)
        return
      }
      
      visit(expr.lhs)
      stream.write(" \(expr.op.rawValue) ")
      visit(expr.rhs)
    }
  }
  
  override func visitBreakExpr(_ expr: BreakExpr) {
    stream.write("break")
  }
  
  override func visitContinueExpr(_ expr: ContinueExpr) {
    stream.write("continue")
  }
  
  override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) {
    if expr.op == .star || expr.op == .ampersand {
      error(JavaScriptError.unrepresentableExpr,
            loc: expr.startLoc(),
            highlights: [
              expr.sourceRange
        ])
      return
    }
    stream.write(expr.op.rawValue)
    visit(expr.rhs);
  }
  
  override func visitVarExpr(_ expr: VarExpr) {
    if let funcDecl = expr.decl as? FuncDeclExpr {
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
          loc: expr.startLoc(),
          highlights: [
            expr.sourceRange
      ])
  }
  
  override func visitTypeDeclExpr(_ expr: TypeDeclExpr) {
    if expr.has(attribute: .foreign) { return }
    super.visitTypeDeclExpr(expr)
  }
  
  override func visitSwitchExpr(_ expr: SwitchExpr) {
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
      newExprs.append(BreakExpr())
      visitCompoundExpr(CompoundExpr(exprs: newExprs))
      stream.write("\n")
    }
    stream.write("}")
  }
  
  override func visitCaseExpr(_ expr: CaseExpr) -> Result {
    write("case \(expr.constant.text): ")
    var newExprs = expr.body.exprs
    newExprs.append(BreakExpr())
    visitCompoundExpr(CompoundExpr(exprs: newExprs))
  }
  
  override func visitIfExpr(_ expr: IfExpr) {
    for (idx, (condition, body)) in expr.blocks.enumerated() {
      if idx != 0 {
        stream.write(" else ")
      }
      stream.write("if (")
      visit(condition)
      stream.write(") ")
      visitCompoundExpr(body)
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
  
  override func visitWhileExpr(_ expr: WhileExpr) {
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
    for (i, arg) in expr.args.enumerated() {
      visit(arg.val)
      if i != expr.args.count - 1 {
        stream.write(", ")
      }
    }
    stream.write(")")
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
  
  override func visitVarAssignExpr(_ expr: VarAssignExpr) {
    if expr.has(attribute: .foreign) { return }
    stream.write("var \(expr.name)")
    if let rhs = expr.rhs {
      stream.write(" = ")
      visit(rhs)
    }
    if currentScope == nil {
      stream.write(";\n")
    }
  }
  
  override func visitForLoopExpr(_ expr: ForLoopExpr) {
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
    visitCompoundExpr(expr.body)
  }
}
