//
//  FunExpr.swift
//  Trill
//

import Foundation

enum FunctionKind {
  case initializer(type: DataType)
  case deinitializer(type: DataType)
  case method(type: DataType)
  case free
}

struct Argument: Equatable {
  let label: Identifier?
  let val: ValExpr
  init(val: ValExpr, label: Identifier? = nil) {
    self.val = val
    self.label = label
  }
}

func ==(lhs: Argument, rhs: Argument) -> Bool {
  return lhs.label == rhs.label && lhs.val.equals(rhs.val)
}

class FuncCallExpr: ValExpr {
  let lhs: ValExpr
  let args: [Argument]
  var decl: FuncDeclExpr? = nil
  init(lhs: ValExpr, args: [Argument], sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.args = args
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? FuncCallExpr else { return false }
    return lhs == expr.lhs && args == expr.args
  }
}

class FuncDeclExpr: DeclExpr { // func <id>(<id>: <type-id>) -> <type-id> { <expr>* }
  let args: [FuncArgumentAssignExpr]
  let body: CompoundExpr?
  let returnType: TypeRefExpr
  let hasVarArgs: Bool
  let kind: FunctionKind
  init(name: Identifier, returnType: TypeRefExpr,
       args: [FuncArgumentAssignExpr],
       kind: FunctionKind = .free,
       body: CompoundExpr? = nil,
       attributes: [DeclAttribute] = [],
       hasVarArgs: Bool = false,
       sourceRange: SourceRange? = nil) {
    self.args = args
    self.body = body
    self.kind = kind
    self.returnType = returnType
    self.hasVarArgs = hasVarArgs
    super.init(name: name,
               type: .function(args: args.map { $0.type }, returnType: returnType.type!),
               attributes: attributes,
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
    case .initializer(let type), .method(let type), .deinitializer(let type):
      return type
    case .free:
      return nil
    }
  }
  var hasImplicitSelf: Bool {
    guard let first = self.args.first else { return false }
    return first.isImplicitSelf
  }
  var formattedName: String {
    var s = ""
    if let methodTy = parentType {
      s += "\(methodTy)."
    }
    s += "\(name)("
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
    if returnType != .void {
      s += " -> "
      s += "\(returnType.type!)"
    }
    return s
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? FuncDeclExpr else { return false }
    return name == expr.name && returnType == expr.returnType
        && args == expr.args && body == expr.body
  }
  
  func addingImplicitSelf(_ type: DataType) -> FuncDeclExpr {
    var args = self.args
    let typeName = Identifier(name: "\(type)")
    let typeRef = TypeRefExpr(type: type, name: typeName)
    let arg = FuncArgumentAssignExpr(name: "self", type: typeRef)
    arg.isImplicitSelf = true
    arg.mutable = has(attribute: .mutating)
    args.insert(arg, at: 0)
    return FuncDeclExpr(name: name,
                        returnType: returnType,
                        args: args,
                        kind: kind,
                        body: body,
                        attributes: Array(attributes),
                        hasVarArgs: hasVarArgs,
                        sourceRange: sourceRange)
  }
}

class FuncArgumentAssignExpr: VarAssignExpr {
  var isImplicitSelf = false
  let externalName: Identifier?
  init(name: Identifier,
       type: TypeRefExpr?,
       externalName: Identifier? = nil,
       rhs: ValExpr? = nil,
       sourceRange: SourceRange? = nil) {
    self.externalName = externalName
    super.init(name: name, typeRef: type, rhs: rhs, mutable: false, sourceRange: sourceRange)
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? FuncArgumentAssignExpr else { return false }
    return name == expr.name && externalName == expr.externalName && rhs == expr.rhs
  }
}

class ClosureExpr: ValExpr {
  let args: [FuncArgumentAssignExpr]
  let returnType: TypeRefExpr
  let body: CompoundExpr
  
  private(set) var captures = Set<Expr>()
  
  init(args: [FuncArgumentAssignExpr], returnType: TypeRefExpr,
       body: CompoundExpr, sourceRange: SourceRange? = nil) {
    self.args = args
    self.returnType = returnType
    self.body = body
    super.init(sourceRange: sourceRange)
  }
  
  func add(capture: Expr) {
    captures.insert(capture)
  }
}

class ReturnExpr: Expr { // return <expr>;
  let value: ValExpr
  init(value: ValExpr, sourceRange: SourceRange? = nil) {
    self.value = value
    super.init(sourceRange: sourceRange)
  }
  override func equals(_ expr: Expr) -> Bool {
    guard let expr = expr as? ReturnExpr else { return false }
    return value == expr.value
  }
}
