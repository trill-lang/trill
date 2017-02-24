//
//  FunExpr.swift
//  Trill
//

import Foundation

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

  var genericParams: [GenericParam] {
    guard let expr = lhs as? GenericContainingExpr else { return [] }
    return expr.genericParams
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

  /// Whether this decl is a 'placeholder' decl, that is, a decl that doesn't have
  /// any substantial body behind it and should not be mangled as such.
  let isPlaceholder: Bool

  let genericParams: [GenericParamDecl]
  init(name: Identifier, returnType: TypeRefExpr,
       args: [ParamDecl],
       genericParams: [GenericParamDecl] = [],
       body: CompoundStmt? = nil,
       modifiers: [DeclModifier] = [],
       isPlaceholder: Bool = false,
       hasVarArgs: Bool = false,
       sourceRange: SourceRange? = nil) {
    self.args = args
    self.body = body
    self.name = name
    self.genericParams = genericParams
    self.returnType = returnType
    self.hasVarArgs = hasVarArgs
    self.isPlaceholder = isPlaceholder
    super.init(type: .function(args: args.map { $0.type }, returnType: returnType.type!),
               modifiers: modifiers,
               sourceRange: sourceRange)
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
    var s = "\(name)"
    s += formattedParameterList
    if returnType != .void {
      s += " -> "
      s += "\(returnType.type!)"
    }
    return s
  }
  
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["signature"] = formattedName
    superAttrs["name"] = name.name
    return superAttrs
  }
}

class MethodDecl: FuncDecl {
  let parentType: DataType

  /// The protocols for which this method implementation satisfies a requirement
  var satisfiedProtocols = Set<ProtocolDecl>()

  /// Whether or not this method satisfies a requirement from any protocols
  var satisfiesProtocol: Bool { return satisfiedProtocols.isEmpty }

  init(name: Identifier,
       parentType: DataType,
       args: [ParamDecl],
       genericParams: [GenericParamDecl],
       returnType: TypeRefExpr,
       body: CompoundStmt?,
       modifiers: [DeclModifier],
       hasVarArgs: Bool = false,
       sourceRange: SourceRange? = nil) {
    self.parentType = parentType
    var fullArgs = args
    if !modifiers.contains(.static) {
      let selfParam = ParamDecl(name: "self",
                                type: parentType.ref(),
                                externalName: nil, rhs: nil,
                                sourceRange: nil)
      selfParam.isImplicitSelf = true
      selfParam.mutable = modifiers.contains(.mutating)
      fullArgs.insert(selfParam, at: 0)
    }
    super.init(name: name,
               returnType: returnType,
               args: fullArgs,
               genericParams: genericParams,
               body: body,
               modifiers: modifiers,
               hasVarArgs: hasVarArgs,
               sourceRange: sourceRange)
  }
}

class ProtocolMethodDecl: MethodDecl {}

class InitializerDecl: MethodDecl {
  init(parentType: DataType,
       args: [ParamDecl],
       genericParams: [GenericParamDecl],
       returnType: TypeRefExpr,
       body: CompoundStmt?,
       modifiers: [DeclModifier],
       hasVarArgs: Bool = false,
       sourceRange: SourceRange? = nil) {

    var newModifiers = Set(modifiers)
    newModifiers.insert(.static)
    super.init(name: "init",
               parentType: parentType,
               args: args,
               genericParams: genericParams,
               returnType: returnType,
               body: body,
               modifiers: Array(newModifiers),
               hasVarArgs: hasVarArgs,
               sourceRange: sourceRange)
  }
}

class DeinitializerDecl: MethodDecl {
  init(parentType: DataType,
       body: CompoundStmt?,
       sourceRange: SourceRange? = nil) {
    super.init(name: "deinit",
               parentType: parentType,
               args: [],
               genericParams: [],
               returnType: DataType.void.ref(),
               body: body,
               modifiers: [],
               sourceRange: sourceRange)
  }
}

class SubscriptDecl: MethodDecl {
  init(returnType: TypeRefExpr,
       args: [ParamDecl],
       genericParams: [GenericParamDecl],
       parentType: DataType,
       body: CompoundStmt?,
       modifiers: [DeclModifier],
       sourceRange: SourceRange? = nil) {
    super.init(name: Identifier(name: "subscript"),
               parentType: parentType,
               args: args,
               genericParams: genericParams,
               returnType: returnType,
               body: body,
               modifiers: modifiers,
               hasVarArgs: false,
               sourceRange: sourceRange)
  }
}

class ParamDecl: VarAssignDecl {
  var isImplicitSelf = false
  let externalName: Identifier?
  init(name: Identifier,
       type: TypeRefExpr,
       externalName: Identifier? = nil,
       rhs: Expr? = nil,
       sourceRange: SourceRange? = nil) {
    self.externalName = externalName
    super.init(name: name, typeRef: type, kind: .global, rhs: rhs, mutable: false, sourceRange: sourceRange)!
  }
}

class ClosureExpr: Expr {
  let args: [ParamDecl]
  let genericParams: [GenericParamDecl]
  let returnType: TypeRefExpr
  let body: CompoundStmt
  
  private(set) var captures = Set<ASTNode>()

  init(args: [ParamDecl],
       genericParams: [GenericParamDecl],
       returnType: TypeRefExpr,
       body: CompoundStmt,
       sourceRange: SourceRange? = nil) {
    self.genericParams = genericParams
    self.args = args
    self.returnType = returnType
    self.body = body
    super.init(sourceRange: sourceRange)
  }
  
  func add(capture: ASTNode) {
    captures.insert(capture)
  }
}
