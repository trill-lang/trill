//
//  ASTDumper.swift
//  Trill
//

import Foundation

class ASTDumper<StreamType: ColoredStream>: ASTTransformer {
  typealias Result = Void
  
  var indentLevel = 0
  let sourceFiles: Set<String>
  
  let showImports: Bool
  
  var stream: StreamType
  init(stream: inout StreamType, context: ASTContext, files: [SourceFile], showImports: Bool = false) {
    self.stream = stream
    self.sourceFiles = Set(files.map { $0.path.basename })
    self.showImports = showImports
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
    guard let loc = node.startLoc, let file = loc.file else { return }
    let component = URL(fileURLWithPath: file).lastPathComponent
    if !showImports {
      guard sourceFiles.contains(component) else { return }
      if let decl = node as? Decl, decl.has(attribute: .implicit) {
        return
      }
    }
    if indentLevel != 0 {
      stream.write("\n")
    }
    stream.write(String(repeating: " ", count: indentLevel))
    let nodeName = "\(type(of: node))".snakeCase()
    stream.write("(")
    stream.write("\(nodeName) ", with: [.bold, .magenta])
    stream.write(component, with: [.cyan])
    stream.write(":")
    stream.write("\(loc.line)", with: [.cyan])
    stream.write(":")
    stream.write("\(loc.column)", with: [.cyan])
    stream.write(" ")
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
  override func visitParamDecl(_ decl: ParamDecl) -> Result {
    printNode(decl) {
      super.visitParamDecl(decl)
    }
  }
  override func visitTypeAliasDecl(_ decl: TypeAliasDecl) -> Result {
    printNode(decl) {
      super.visitTypeAliasDecl(decl)
    }
  }
  
  override func visitFuncDecl(_ decl: FuncDecl) -> Result {
    printNode(decl) {
      for param in decl.genericParams {
        self.printNode(param)
      }
      super.visitFuncDecl(decl)
    }
  }
  
  override func visitProtocolDecl(_ decl: ProtocolDecl) {
    printNode(decl) {
      super.visitProtocolDecl(decl)
    }
  }
  
  override func visitClosureExpr(_ expr: ClosureExpr) -> Result {
    printNode(expr) {
      super.visitClosureExpr(expr)
    }
  }
  override func visitReturnStmt(_ stmt: ReturnStmt) -> Result {
    printNode(stmt) {
      super.visitReturnStmt(stmt)
    }
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
      for param in expr.genericParams {
        self.printNode(param)
      }
      super.visitFuncCallExpr(expr)
    }
  }
  override func visitTypeDecl(_ decl: TypeDecl) -> Result {
    printNode(decl) {
      for param in decl.genericParams {
        self.printNode(param)
      }
      super.visitTypeDecl(decl)
    }
  }
  override func visitPropertyDecl(_ decl: PropertyDecl) -> Void {
    printNode(decl) {
      super.visitPropertyDecl(decl)
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
  override func visitDeclStmt(_ stmt: DeclStmt) -> () {
    printNode(stmt) {
      super.visitDeclStmt(stmt)
    }
  }
  override func visitExprStmt(_ stmt: ExprStmt) {
    printNode(stmt) {
      super.visitExprStmt(stmt)
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
  override func visitPropertyRefExpr(_ expr: PropertyRefExpr) -> Result {
    printNode(expr) {
      super.visitPropertyRefExpr(expr)
    }
  }
  override func visitNilExpr(_ expr: NilExpr) {
    printNode(expr) {
      super.visitNilExpr(expr)
    }
  }
  override func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) {
    printNode(expr) {
      super.visitPoundFunctionExpr(expr)
    }
  }
  override func visitArrayExpr(_ expr: ArrayExpr) {
    printNode(expr) {
      super.visitArrayExpr(expr)
    }
  }
  override func visitSizeofExpr(_ expr: SizeofExpr) {
    printNode(expr) {
      super.visitSizeofExpr(expr)
    }
  }
  override func visitOperatorDecl(_ decl: OperatorDecl) {
    printNode(decl) {
      super.visitOperatorDecl(decl)
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
    printNode(stmt) {
      super.visitPoundDiagnosticStmt(stmt)
    }
  }
}
