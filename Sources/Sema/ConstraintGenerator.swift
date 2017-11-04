///
/// ConstraintGenerator.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import Foundation

final class ConstraintGenerator: ASTTransformer {
  var goal: DataType = .error
  var env = ConstraintEnvironment()
  var system = ConstraintSystem()

  func reset(with env: ConstraintEnvironment) {
    self.goal = .error
    self.env = env
    self.system = ConstraintSystem()
  }

  func bind(_ name: Identifier, to type: DataType) {
    env[name] = type
  }

  // MARK: Monotypes

  override func visitVarExpr(_ expr: VarExpr) {
    if expr.isSelf {
      self.goal = expr.type
      return
    }

    if let stdlib = context.stdlib, expr.isTypeVar {
      self.goal = stdlib.mirror.type
      return
    }

    if let t = env[expr.name] ?? context.global(named: expr.name)?.type {
      self.goal = t
      return
    }

    if let decl = expr.decl {
      self.goal = decl.type
      return
    }
  }

  override func visitSizeofExpr(_ expr: SizeofExpr) {
    self.goal = expr.type
  }

  override func visitStringInterpolationExpr(_ expr: StringInterpolationExpr) {
    self.goal = expr.type
  }

  override func visitPropertyRefExpr(_ expr: PropertyRefExpr) {
    // Don't visit the left-hand side if it's a type var, because you're
    // actually trying to access a static property of the type, not an instance
    // property/method on the metatype mirror.
    if let v = expr.lhs as? VarExpr,
       let typeDecl = expr.typeDecl,
       v.isTypeVar {
      goal = typeDecl.type
    } else {
      visit(expr.lhs)
    }

    system.constrainEqual(goal, expr.typeDecl!.type, node: expr)

    let tau = env.freshTypeVariable()
    system.constrainEqual(expr.decl!, tau)

    self.goal = tau
  }

  override func visitVarAssignDecl(_ decl: VarAssignDecl) {
    let goalType: DataType

    // let <ident>: <Type> = <expr>
    if let e = decl.rhs {
      if let typeRef = decl.typeRef {
        goalType = typeRef.type
      } else {
        goalType = e.type
      }

      visit(e)

      // Bind the given type to the goal type the initializer generated.
      system.constrainEqual(goal, goalType, node: e)
    } else {
      // let <ident>: <Type>
      // Take the type binding as fact and move on.
      goalType = decl.type
      bind(decl.name, to: goalType)
    }

    self.goal = goalType
  }

  override func visitFuncDecl(_ expr: FuncDecl) {
    if let body = expr.body {
      let oldEnv = self.env
      for p in expr.args {
        // Bind the type of the parameters.
        bind(p.name, to: p.type)
      }

      // Walk into the function body
      self.visit(body)
      self.env = oldEnv
    }
    self.goal = expr.type
  }

  override func visitFuncCallExpr(_ expr: FuncCallExpr) {
    visit(expr.lhs)
    let lhsGoal = self.goal
    var goals = [DataType]()
    if let method = expr.decl as? MethodDecl, !method.has(attribute: .static) {
      goals.append(method.parentType)
    }
    for arg in expr.args {
      visit(arg.val)
      goals.append(self.goal)
    }
    let tau = env.freshTypeVariable()
    system.constrainEqual(lhsGoal,
                          .function(args: goals,
                                    returnType: tau,
                                    hasVarArgs: expr.decl!.hasVarArgs),
                          node: expr.lhs)
    goal = tau
  }

  override func visitIsExpr(_ expr: IsExpr) {
    let tau = env.freshTypeVariable()

    visit(expr.rhs)
    system.constrainEqual(goal, tau)

    system.constrainEqual(expr, .bool)
    goal = .bool
  }

  override func visitCoercionExpr(_ expr: CoercionExpr) {
    let tau = env.freshTypeVariable()

    visit(expr.rhs)
    system.constrainEqual(goal, tau)

    system.constrainEqual(expr, tau)
    goal = tau
  }

  override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
    let tau = env.freshTypeVariable()

    if expr.op.isAssign {
      goal = .void
      return
    }

    let lhsGoal = expr.decl!.type
    var goals = [DataType]()
    visit(expr.lhs)
    goals.append(goal)
    visit(expr.rhs)
    goals.append(goal)

    system.constrainEqual(lhsGoal,
                          .function(args: goals, returnType: tau,
                                    hasVarArgs: false),
                          node: expr)
    goal = tau
  }

  override func visitSubscriptExpr(_ expr: SubscriptExpr) {
    visit(expr.lhs)
    var goals: [DataType] = [ self.goal ]
    expr.args.forEach { a in
      visit(a.val)
      goals.append(self.goal)
    }
    let tau = env.freshTypeVariable()
    if let decl = expr.decl {
      system.constrainEqual(decl, .function(args: goals,
                                            returnType: tau,
                                            hasVarArgs: false))
    }
    self.goal = tau
  }

  override func visitArrayExpr(_ expr: ArrayExpr) {
    guard case .array(let field, _) = expr.type else {
      fatalError("invalid array type")
    }
    for value in expr.values {
      visit(value)
      system.constrainEqual(goal, field, node: value)
    }
    goal = expr.type
  }

  override func visitTupleExpr(_ expr: TupleExpr) {
    var goals = [DataType]()
    for element in expr.values {
      visit(element)
      goals.append(self.goal)
    }
    system.constrainEqual(expr, .tuple(fields: goals))
    self.goal = expr.type
  }

  override func visitTernaryExpr(_ expr: TernaryExpr) {
    let tau = env.freshTypeVariable()

    visit(expr.condition)
    system.constrainEqual(expr.condition, .bool)

    visit(expr.trueCase)
    system.constrainEqual(expr.trueCase, tau)

    visit(expr.falseCase)
    system.constrainEqual(expr.falseCase, tau)

    system.constrainEqual(expr, tau)

    self.goal = tau
  }

  override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) {
    visit(expr.rhs)
    let rhsGoal = self.goal
    switch expr.op {
    case .ampersand:
      goal = .pointer(type: rhsGoal)
    case .bitwiseNot:
      goal = rhsGoal
    case .minus:
      goal = rhsGoal
    case .not:
      goal = .bool
      system.constrainEqual(rhsGoal, .bool, node: expr.rhs)
    case .star:
      guard case .pointer(let element) = expr.rhs.type else {
        fatalError("invalid dereference?")
      }
      goal = element
    default:
      fatalError("invalid prefix operator: \(expr.op)")
    }
    system.constrainEqual(expr, goal)
  }

  override func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) {
    visit(expr.lhs)
    let lhsGoal = self.goal

    guard case .tuple(let fields) = lhsGoal else {
      return
    }

    system.constrainEqual(expr, fields[expr.field])
    self.goal = fields[expr.field]
  }

  override func visitParenExpr(_ expr: ParenExpr) {
    visit(expr.value)
    self.goal = expr.type
  }

  override func visitTypeRefExpr(_ expr: TypeRefExpr) {
    self.goal = expr.type
  }

  override func visitPoundFunctionExpr(_ expr: PoundFunctionExpr) {
    visitStringExpr(expr)
  }

  override func visitClosureExpr(_ expr: ClosureExpr) {
    // TODO: Implement this
  }

  // MARK: Literals

  override func visitNumExpr(_ expr: NumExpr) { self.goal = expr.type }
  override func visitCharExpr(_ expr: CharExpr) { self.goal = expr.type }
  override func visitFloatExpr(_ expr: FloatExpr) { self.goal = expr.type }
  override func visitBoolExpr(_ expr: BoolExpr) { self.goal = expr.type }
  override func visitVoidExpr(_ expr: VoidExpr) { self.goal = expr.type }
  override func visitNilExpr(_ expr: NilExpr) { self.goal = expr.type }
  override func visitStringExpr(_ expr: StringExpr) { self.goal = expr.type }
}
