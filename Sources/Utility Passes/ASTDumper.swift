//
//  ASTDumper.swift
//  Trill
//

import Foundation

class ASTDumper<StreamType: TextOutputStream>: ASTTransformer {
  typealias Result = Void
  
  var indentLevel = 0
  
  var stream: ColoredStream<StreamType>
  init(stream: inout StreamType, context: ASTContext, colored: Bool) {
    self.stream = ColoredStream(&stream, colored: colored)
    super.init(context: context)
  }
  
  required init(context: ASTContext) {
    fatalError("Cannot instantiate with just context")
  }
    
  func printAttributes(_ attributes: [String: Any]) {
    var attrs = [(String, String)]()
    for key in attributes.keys.sorted() {
      guard let val = attributes[key] else { continue }
      let attr: (String, String)
      if let val = val as? String {
        attr = (key, "\"\(val.escaped())\"")
      } else {
        attr = (key, "\(val)")
      }
      attrs.append(attr)
    }
    for (index, (key, attr)) in attrs.enumerated() {
      stream.write(key, with: [.green])
      stream.write("=")
      if attr.hasPrefix("\"") {
        stream.write(attr, with: [.red])
      } else if attr == "true" || attr == "false" ||
                Int(attr) != nil || Double(attr) != nil {
        stream.write(attr, with: [.cyan])
      } else {
        stream.write(attr)
      }
      if index != attrs.endIndex - 1 {
        stream.write(" ")
      }
    }
  }
  
  func printNode(_ node: ASTNode, then: (() -> Void)? = nil) {
    if indentLevel != 0 {
      stream.write("\n")
    }
    stream.write(String(repeating: " ", count: indentLevel))
    let nodeName = "\(type(of: node))".snakeCase()
    stream.write("(")
    stream.write("\(nodeName) ", with: [.bold, .magenta])
    printAttributes(node.attributes())
    if let then = then {
      indent()
      then()
      dedent()
    }
    stream.write(")")
    if indentLevel == 0 {
      stream.write("\n")
    }
  }
  
  func indent() {
    indentLevel += 2
  }
  
  func dedent() {
    indentLevel -= 2
  }
  
  override func visitNumExpr(_ expr: NumExpr) {
    printNode(expr)
  }
  override func visitCharExpr(_ expr: CharExpr) {
    printNode(expr)
  }
  override func visitVarExpr(_ expr: VarExpr) {
    printNode(expr)
  }
  override func visitVoidExpr(_ expr: VoidExpr) {
    printNode(expr)
  }
  override func visitBoolExpr(_ expr: BoolExpr) {
    printNode(expr)
  }
  override func visitVarAssignDecl(_ decl: VarAssignDecl) {
    printNode(decl) {
      super.visitVarAssignDecl(decl)
    }
  }
  override func visitFuncArgumentAssignDecl(_ decl: FuncArgumentAssignDecl) -> Result {
    printNode(decl) {
      super.visitFuncArgumentAssignDecl(decl)
    }
  }
  override func visitTypeAliasDecl(_ decl: TypeAliasDecl) -> Result {
    guard decl.startLoc != nil else { return }
    printNode(decl) {
      super.visitTypeAliasDecl(decl)
    }
  }
  
  override func visitFuncDecl(_ decl: FuncDecl) -> Result {
    if decl.has(attribute: .foreign) { return }
    printNode(decl) {
      super.visitFuncDecl(decl)
    }
  }
  override func visitClosureExpr(_ expr: ClosureExpr) -> Result {
    printNode(expr) {
      super.visitClosureExpr(expr)
    }
  }
  override func visitReturnStmt(_ stmt: ReturnStmt) -> Result {
    printNode(stmt)
  }
  override func visitBreakStmt(_ stmt: BreakStmt) -> Result {
    printNode(stmt)
  }
  override func visitContinueStmt(_ stmt: ContinueStmt) -> Result {
    printNode(stmt)
  }
  
  override func visitStringExpr(_ expr: StringExpr) {
    printNode(expr)
  }
  
  override func visitSubscriptExpr(_ expr: SubscriptExpr) {
    printNode(expr) {
      super.visitSubscriptExpr(expr)
    }
  }
  
  override func visitTypeRefExpr(_ expr: TypeRefExpr) -> Result {
    printNode(expr) {
      super.visitTypeRefExpr(expr)
    }
  }
  
  override func visitFloatExpr(_ expr: FloatExpr) {
    printNode(expr)
  }
  
  override func visitCompoundStmt(_ stmt: CompoundStmt) -> Result {
    printNode(stmt) {
      super.visitCompoundStmt(stmt)
    }
  }
  override func visitFuncCallExpr(_ expr: FuncCallExpr) -> Result {
    printNode(expr) {
      super.visitFuncCallExpr(expr)
    }
  }
  override func visitTypeDecl(_ decl: TypeDecl) -> Result {
    if decl.has(attribute: .foreign) { return }
    printNode(decl) {
      super.visitTypeDecl(decl)
    }
  }
  override func visitExtensionDecl(_ decl: ExtensionDecl) -> Result {
    printNode(decl) {
      super.visitExtensionDecl(decl)
    }
  }
  override func visitWhileStmt(_ stmt: WhileStmt) -> Result {
    printNode(stmt) {
      super.visitWhileStmt(stmt)
    }
  }
  override func visitForStmt(_ stmt: ForStmt) -> Result {
    printNode(stmt) {
      super.visitForStmt(stmt)
    }
  }
  override func visitIfStmt(_ stmt: IfStmt) -> Result {
    printNode(stmt) {
      super.visitIfStmt(stmt)
    }
  }
  override func visitTernaryExpr(_ expr: TernaryExpr) -> Result {
    printNode(expr) {
      super.visitTernaryExpr(expr)
    }
  }
  override func visitSwitchStmt(_ stmt: SwitchStmt) -> Result {
    printNode(stmt) {
      super.visitSwitchStmt(stmt)
    }
  }
  override func visitCaseStmt(_ stmt: CaseStmt) -> Result {
    printNode(stmt) {
      super.visitCaseStmt(stmt)
    }
  }
  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) -> Result {
    printNode(expr) {
      super.visitInfixOperatorExpr(expr)
    }
  }
  override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) -> Result {
    printNode(expr) {
      super.visitPrefixOperatorExpr(expr)
    }
  }
  override func visitFieldLookupExpr(_ expr: FieldLookupExpr) -> Result {
    printNode(expr) {
      super.visitFieldLookupExpr(expr)
    }
  }
  override func visitTupleExpr(_ expr: TupleExpr) {
    printNode(expr) {
      super.visitTupleExpr(expr)
    }
  }
  override func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) {
    printNode(expr) {
      super.visitTupleFieldLookupExpr(expr)
    }
  }
  override func visitParenExpr(_ expr: ParenExpr) -> Result {
    printNode(expr) {
      super.visitParenExpr(expr)
    }
  }
  override func visitPoundDiagnosticStmt(_ stmt: PoundDiagnosticStmt) -> () {
    printNode(stmt)
  }
}
