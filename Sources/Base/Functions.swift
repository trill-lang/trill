//
//  FunExpr.swift
//  Trill
//

import Foundation

enum FunctionKind {
  case initializer(type: DataType)
  case deinitializer(type: DataType)
  case method(type: DataType)
  case `operator`(op: BuiltinOperator)
  case `subscript`(type: DataType)
  case property(type: DataType)
  case free
}

struct Argument: Equatable {
  let label: Identifier?
  let val: Expr
  init(val: Expr, label: Identifier? = nil) {
    self.val = val
    self.label = label
  }
}

func ==(lhs: Argument, rhs: Argument) -> Bool {
  return lhs.label == rhs.label && lhs.val.equals(rhs.val)
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
  override func equals(_ node: ASTNode) -> Bool {
    guard let node = node as? FuncCallExpr else { return false }
    return lhs == node.lhs && args == node.args
  }
}

class FuncDecl: Decl { // func <id>(<id>: <type-id>) -> <type-id> { <expr>* }
  let args: [FuncArgumentAssignDecl]
  let name: Identifier
  let body: CompoundStmt?
  let returnType: TypeRefExpr
  let hasVarArgs: Bool
  let kind: FunctionKind
  init(name: Identifier, returnType: TypeRefExpr,
       args: [FuncArgumentAssignDecl],
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
         .property(let type):
      return type
    case .operator, .free:
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
  override func equals(_ node: ASTNode) -> Bool {
    guard let node = node as? FuncDecl else { return false }
    return name == node.name && returnType == node.returnType
        && args == node.args && body == node.body
  }
  
  func addingImplicitSelf(_ type: DataType) -> FuncDecl {
    var args = self.args
    let typeName = Identifier(name: "\(type)")
    let typeRef = TypeRefExpr(type: type, name: typeName)
    let arg = FuncArgumentAssignDecl(name: "self", type: typeRef)
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
}

class FuncArgumentAssignDecl: VarAssignDecl {
  var isImplicitSelf = false
  let externalName: Identifier?
  init(name: Identifier,
       type: TypeRefExpr?,
       externalName: Identifier? = nil,
       rhs: Expr? = nil,
       sourceRange: SourceRange? = nil) {
    self.externalName = externalName
    super.init(name: name, typeRef: type, rhs: rhs, mutable: false, sourceRange: sourceRange)
  }
  override func equals(_ node: ASTNode) -> Bool {
    guard let node = node as? FuncArgumentAssignDecl else { return false }
    return name == node.name && externalName == node.externalName && rhs == node.rhs
  }
}

class SubscriptDecl: FuncDecl {
  init(returnType: TypeRefExpr, args: [FuncArgumentAssignDecl], parentType: DataType, body: CompoundStmt?, modifiers: [DeclModifier], sourceRange: SourceRange?) {
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
    let arg = FuncArgumentAssignDecl(name: "self", type: typeRef)
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
  let args: [FuncArgumentAssignDecl]
  let returnType: TypeRefExpr
  let body: CompoundStmt
  
  private(set) var captures = Set<ASTNode>()
  
  init(args: [FuncArgumentAssignDecl], returnType: TypeRefExpr,
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
