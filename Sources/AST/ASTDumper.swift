///
/// ASTDumper.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Diagnostics
import Foundation
import Source

public class ASTDumper<StreamType: ColoredStream>: ASTTransformer {
  typealias Result = Void

  var indentLevel = 0
  let sourceFiles: Set<String>

  let showImports: Bool

  var stream: StreamType
  public init(stream: inout StreamType, context: ASTContext, files: [SourceFile], showImports: Bool = false) {
    self.stream = stream
    self.sourceFiles = Set(files.map { $0.path.basename })
    self.showImports = showImports
    super.init(context: context)
  }

  required public init(context: ASTContext) {
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
    guard let loc = node.startLoc else { return }
    let file = loc.file
    let component = file.path.basename
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

  public override func visitNumExpr(_ expr: NumExpr) {
    printNode(expr)
  }
  public override func visitCharExpr(_ expr: CharExpr) {
    printNode(expr)
  }
  public override func visitVarExpr(_ expr: VarExpr) {
    printNode(expr)
  }
  public override func visitVoidExpr(_ expr: VoidExpr) {
    printNode(expr)
  }
  public override func visitBoolExpr(_ expr: BoolExpr) {
    printNode(expr)
  }
  public override func visitVarAssignDecl(_ decl: VarAssignDecl) {
    printNode(decl) {
      super.visitVarAssignDecl(decl)
    }
  }
  public override func visitParamDecl(_ decl: ParamDecl) {
    printNode(decl) {
      super.visitParamDecl(decl)
    }
  }
  public override func visitTypeAliasDecl(_ decl: TypeAliasDecl) {
    printNode(decl) {
      super.visitTypeAliasDecl(decl)
    }
  }

  public override func visitFuncDecl(_ decl: FuncDecl) {
    printNode(decl) {
      for param in decl.genericParams {
        self.printNode(param)
      }
      super.visitFuncDecl(decl)
    }
  }

  public override func visitProtocolDecl(_ decl: ProtocolDecl) {
    printNode(decl) {
      super.visitProtocolDecl(decl)
    }
  }

  public override func visitClosureExpr(_ expr: ClosureExpr) {
    printNode(expr) {
      super.visitClosureExpr(expr)
    }
  }
  public override func visitReturnStmt(_ stmt: ReturnStmt) {
    printNode(stmt) {
      super.visitReturnStmt(stmt)
    }
  }
  public override func visitBreakStmt(_ stmt: BreakStmt) {
    printNode(stmt)
  }
  public override func visitContinueStmt(_ stmt: ContinueStmt) {
    printNode(stmt)
  }

  public override func visitStringExpr(_ expr: StringExpr) {
    printNode(expr)
  }

  public override func visitStringInterpolationExpr(_ expr: StringInterpolationExpr) {
    printNode(expr) {
      super.visitStringInterpolationExpr(expr)
    }
  }

  public override func visitSubscriptExpr(_ expr: SubscriptExpr) {
    printNode(expr) {
      super.visitSubscriptExpr(expr)
    }
  }

  public override func visitTypeRefExpr(_ expr: TypeRefExpr) {
    printNode(expr) {
      super.visitTypeRefExpr(expr)
    }
  }

  public override func visitFloatExpr(_ expr: FloatExpr) {
    printNode(expr)
  }

  public override func visitCompoundStmt(_ stmt: CompoundStmt) {
    printNode(stmt) {
      super.visitCompoundStmt(stmt)
    }
  }
  public override func visitFuncCallExpr(_ expr: FuncCallExpr) {
    printNode(expr) {
      for param in expr.genericParams {
        self.printNode(param)
      }
      super.visitFuncCallExpr(expr)
    }
  }
  public override func visitTypeDecl(_ decl: TypeDecl) {
    printNode(decl) {
      for param in decl.genericParams {
        self.printNode(param)
      }
      super.visitTypeDecl(decl)
    }
  }
  public override func visitPropertyDecl(_ decl: PropertyDecl) -> Void {
    printNode(decl) {
      super.visitPropertyDecl(decl)
    }
  }
  public override func visitExtensionDecl(_ decl: ExtensionDecl) {
    printNode(decl) {
      super.visitExtensionDecl(decl)
    }
  }
  public override func visitWhileStmt(_ stmt: WhileStmt) {
    printNode(stmt) {
      super.visitWhileStmt(stmt)
    }
  }
  public override func visitForStmt(_ stmt: ForStmt) {
    printNode(stmt) {
      super.visitForStmt(stmt)
    }
  }
  public override func visitIfStmt(_ stmt: IfStmt) {
    printNode(stmt) {
      super.visitIfStmt(stmt)
    }
  }
  public override func visitDeclStmt(_ stmt: DeclStmt) -> () {
    printNode(stmt) {
      super.visitDeclStmt(stmt)
    }
  }
  public override func visitExprStmt(_ stmt: ExprStmt) {
    printNode(stmt) {
      super.visitExprStmt(stmt)
    }
  }
  public override func visitTernaryExpr(_ expr: TernaryExpr) {
    printNode(expr) {
      super.visitTernaryExpr(expr)
    }
  }
  public override func visitSwitchStmt(_ stmt: SwitchStmt) {
    printNode(stmt) {
      super.visitSwitchStmt(stmt)
    }
  }
  public override func visitCaseStmt(_ stmt: CaseStmt) {
    printNode(stmt) {
      super.visitCaseStmt(stmt)
    }
  }
  public override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
    printNode(expr) {
      super.visitInfixOperatorExpr(expr)
    }
  }
  public override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) {
    printNode(expr) {
      super.visitPrefixOperatorExpr(expr)
    }
  }
  public override func visitPropertyRefExpr(_ expr: PropertyRefExpr) {
    printNode(expr) {
      super.visitPropertyRefExpr(expr)
    }
  }
  public override func visitNilExpr(_ expr: NilExpr) {
    printNode(expr) {
      super.visitNilExpr(expr)
    }
  }
  public override func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) {
    printNode(expr) {
      super.visitPoundFunctionExpr(expr)
    }
  }
  public override func visitArrayExpr(_ expr: ArrayExpr) {
    printNode(expr) {
      super.visitArrayExpr(expr)
    }
  }
  public override func visitSizeofExpr(_ expr: SizeofExpr) {
    printNode(expr) {
      super.visitSizeofExpr(expr)
    }
  }
  public override func visitOperatorDecl(_ decl: OperatorDecl) {
    printNode(decl) {
      super.visitOperatorDecl(decl)
    }
  }
  public override func visitTupleExpr(_ expr: TupleExpr) {
    printNode(expr) {
      super.visitTupleExpr(expr)
    }
  }
  public override func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) {
    printNode(expr) {
      super.visitTupleFieldLookupExpr(expr)
    }
  }
  public override func visitParenExpr(_ expr: ParenExpr) {
    printNode(expr) {
      super.visitParenExpr(expr)
    }
  }
  public override func visitPoundDiagnosticStmt(_ stmt: PoundDiagnosticStmt) {
    printNode(stmt) {
      super.visitPoundDiagnosticStmt(stmt)
    }
  }
  public override func visitIsExpr(_ expr: IsExpr) -> Void {
    printNode(expr) {
      super.visitIsExpr(expr)
    }
  }
  public override func visitCoercionExpr(_ expr: CoercionExpr) -> Void {
    printNode(expr) {
      super.visitCoercionExpr(expr)
    }
  }
}

extension String {
    func splitCapitals() -> [String] {
        var s = ""
        var words = [String]()
        for char in unicodeScalars {
            if isupper(Int32(char.value)) != 0 && !s.isEmpty {
                words.append(s)
                s = ""
            }
            s.append(String(char))
        }
        if !s.isEmpty {
            words.append(s)
        }
        return words
    }
    func snakeCase() -> String {
        return splitCapitals().map { $0.lowercased() }.joined(separator: "_")
    }
}
