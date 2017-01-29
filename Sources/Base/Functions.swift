//
//  FunExpr.swift
//  Trill
//

import Foundation

enum FunctionKind {
  case initializer(type: DataType)
  case deinitializer(type: DataType)
  case method(type: DataType)
  case staticMethod(type: DataType)
  case `operator`(op: BuiltinOperator)
  case `subscript`(type: DataType)
  case property(type: DataType)
  case variable
  case free
}

struct Argument {
  let label: Identifier?
  let val: Expr
  init(val: Expr, label: Identifier? = nil) {
    self.val = val
    self.label = label
  }
}

class FuncCallExpr: Expr {
  let lhs: Expr
  let args: [Argument]
  var decl: FuncDecl? = nil
  init(lhs: Expr, args: [Argument], sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.args = args
    super.init(sourceRange: sourceRange)
  }
  
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    if let decl = decl {
      superAttrs["decl"] = decl.formattedName
    }
    return superAttrs
  }
}

class FuncDecl: Decl { // func <id>(<id>: <type-id>) -> <type-id> { <expr>* }
  let args: [ParamDecl]
  let name: Identifier
  let body: CompoundStmt?
  let returnType: TypeRefExpr
  let hasVarArgs: Bool
  let kind: FunctionKind
  init(name: Identifier, returnType: TypeRefExpr,
       args: [ParamDecl],
       kind: FunctionKind = .free,
       body: CompoundStmt? = nil,
       modifiers: [DeclModifier] = [],
       hasVarArgs: Bool = false,
       sourceRange: SourceRange? = nil) {
    self.args = args
    self.body = body
    self.kind = kind
    self.name = name
    self.returnType = returnType
    self.hasVarArgs = hasVarArgs
    super.init(type: .function(args: args.map { $0.type }, returnType: returnType.type!),
               modifiers: modifiers,
               sourceRange: sourceRange)
  }
  var isInitializer: Bool {
    if case .initializer = kind { return true }
    return false
  }
  var isDeinitializer: Bool {
    if case .deinitializer = kind { return true }
    return false
  }
  var parentType: DataType? {
    switch kind {
    case .initializer(let type), .method(let type),
         .deinitializer(let type), .subscript(let type),
         .property(let type), .staticMethod(let type):
      return type
    case .operator, .free, .variable:
      return nil
    }
  }
  var hasImplicitSelf: Bool {
    guard let first = self.args.first else { return false }
    return first.isImplicitSelf
  }
  var formattedParameterList: String {
    var s = "("
    for (idx, arg) in args.enumerated() where !arg.isImplicitSelf {
      var names = [String]()
      if let extern = arg.externalName {
        names.append(extern.name)
      } else {
        names.append("_")
      }
      if names.first != arg.name.name {
        names.append(arg.name.name)
      }
      s += names.joined(separator: " ")
      s += ": \(arg.type)"
      if idx != args.count - 1 || hasVarArgs {
        s += ", "
      }
    }
    if hasVarArgs {
      s += "_: ..."
    }
    s += ")"
    return s
  }
  var formattedName: String {
    var s = ""
    if let methodTy = parentType {
      s += "\(methodTy)."
    }
    s += "\(name)"
    s += formattedParameterList
    if returnType != .void {
      s += " -> "
      s += "\(returnType.type!)"
    }
    return s
  }

  func addingImplicitSelf(_ type: DataType) -> FuncDecl {
    var args = self.args
    let typeName = Identifier(name: "\(type)")
    let typeRef = TypeRefExpr(type: type, name: typeName)
    let arg = ParamDecl(name: "self", type: typeRef)
    arg.isImplicitSelf = true
    arg.mutable = has(attribute: .mutating)
    args.insert(arg, at: 0)
    return FuncDecl(name: name,
                    returnType: returnType,
                    args: args,
                    kind: kind,
                    body: body,
                    modifiers: Array(modifiers),
                    hasVarArgs: hasVarArgs,
                    sourceRange: sourceRange)
  }
  
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["signature"] = formattedName
    superAttrs["name"] = name.name
    superAttrs["kind"] = "\(kind)"
    return superAttrs
  }
}

class ParamDecl: VarAssignDecl {
  var isImplicitSelf = false
  let externalName: Identifier?
  init(name: Identifier,
       type: TypeRefExpr?,
       externalName: Identifier? = nil,
       rhs: Expr? = nil,
       sourceRange: SourceRange? = nil) {
    self.externalName = externalName
    super.init(name: name, typeRef: type, kind: .global, rhs: rhs, mutable: false, sourceRange: sourceRange)
  }
}

class SubscriptDecl: FuncDecl {
  init(returnType: TypeRefExpr, args: [ParamDecl], parentType: DataType, body: CompoundStmt?, modifiers: [DeclModifier], sourceRange: SourceRange?) {
    super.init(name: Identifier(name: "subscript"),
               returnType: returnType,
               args: args,
               kind: .subscript(type: parentType),
               body: body,
               modifiers: modifiers,
               hasVarArgs: false,
               sourceRange: sourceRange)
  }
  
  // HACK
  override func addingImplicitSelf(_ type: DataType) -> SubscriptDecl {
    var args = self.args
    let typeName = Identifier(name: "\(type)")
    let typeRef = TypeRefExpr(type: type, name: typeName)
    let arg = ParamDecl(name: "self", type: typeRef)
    arg.isImplicitSelf = true
    arg.mutable = has(attribute: .mutating)
    args.insert(arg, at: 0)
    return SubscriptDecl(returnType: returnType,
                         args: args,
                         parentType: type,
                         body: body,
                         modifiers: Array(modifiers),
                         sourceRange: sourceRange)
  }
}

class ClosureExpr: Expr {
  let args: [ParamDecl]
  let returnType: TypeRefExpr
  let body: CompoundStmt
  
  private(set) var captures = Set<ASTNode>()
  
  init(args: [ParamDecl], returnType: TypeRefExpr,
       body: CompoundStmt, sourceRange: SourceRange? = nil) {
    self.args = args
    self.returnType = returnType
    self.body = body
    super.init(sourceRange: sourceRange)
  }
  
  func add(capture: ASTNode) {
    captures.insert(capture)
  }
}
