///
/// Functions.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation
import Source

public struct Argument {
  public let label: Identifier?
  public let val: Expr
  public init(val: Expr,
              label: Identifier? = nil) {
    self.val = val
    self.label = label
  }
}

public class FuncCallExpr: Expr {
  public let lhs: Expr
  public let args: [Argument]
  public var decl: FuncDecl? = nil
  public init(lhs: Expr,
              args: [Argument],
              sourceRange: SourceRange? = nil) {
    self.lhs = lhs
    self.args = args
    super.init(sourceRange: sourceRange)
  }

  public var genericParams: [GenericParam] {
    guard let expr = lhs as? GenericContainingExpr else { return [] }
    return expr.genericParams
  }

  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    if let decl = decl {
      superAttrs["decl"] = decl.formattedName
    }
    return superAttrs
  }
}

public class FuncDecl: Decl { // func <id>(<id>: <type-id>) -> <type-id> { <expr>* }
  public let args: [ParamDecl]
  public let name: Identifier
  public let body: CompoundStmt?
  public let returnType: TypeRefExpr
  public let hasVarArgs: Bool

  /// Whether this decl is a 'placeholder' decl, that is, a decl that doesn't have
  /// any substantial body behind it and should not be mangled as such.
  public let isPlaceholder: Bool

  public let genericParams: [GenericParamDecl]
  public init(name: Identifier, returnType: TypeRefExpr,
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
    let allValid = !args.contains { $0.type == .error }
    super.init(type: .function(args: allValid ? args.map { $0.type } : [],
                               returnType: returnType.type,
                               hasVarArgs: hasVarArgs),
               modifiers: modifiers,
               sourceRange: sourceRange)
  }

  public var formattedParameterList: String {
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
  public var formattedName: String {
    var s = "\(name)"
    s += formattedParameterList
    if returnType != .void {
      s += " -> "
      s += "\(returnType.type)"
    }
    return s
  }

  public override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["signature"] = formattedName
    superAttrs["name"] = name.name
    return superAttrs
  }
}

public class MethodDecl: FuncDecl {
  public let parentType: DataType

  /// The protocols for which this method implementation satisfies a requirement
  public var satisfiedProtocols = Set<ProtocolDecl>()

  /// Whether or not this method satisfies a requirement from any protocols
  public var satisfiesProtocol: Bool { return satisfiedProtocols.isEmpty }

  public init(name: Identifier,
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

public class ProtocolMethodDecl: MethodDecl {}

public class InitializerDecl: MethodDecl {
  public init(parentType: DataType,
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

public class DeinitializerDecl: MethodDecl {
  public init(parentType: DataType,
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

public class SubscriptDecl: MethodDecl {
  public init(returnType: TypeRefExpr,
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

public class ParamDecl: VarAssignDecl {
  public var isImplicitSelf = false
  public let externalName: Identifier?
  public init(name: Identifier,
       type: TypeRefExpr?,
       externalName: Identifier? = nil,
       rhs: Expr? = nil,
       sourceRange: SourceRange? = nil) {
    self.externalName = externalName
    super.init(name: name, typeRef: type, kind: .global, rhs: rhs, mutable: false, sourceRange: sourceRange)!
  }
}

public class ClosureExpr: Expr {
  public let args: [ParamDecl]
  public var returnType: TypeRefExpr?
  public let body: CompoundStmt

  private(set) var captures = Set<ASTNode>()

  public init(args: [ParamDecl],
       returnType: TypeRefExpr?,
       body: CompoundStmt,
       sourceRange: SourceRange? = nil) {
    self.args = args
    self.returnType = returnType
    self.body = body
    super.init(sourceRange: sourceRange)
  }

  public func add(capture: ASTNode) {
    captures.insert(capture)
  }
}
