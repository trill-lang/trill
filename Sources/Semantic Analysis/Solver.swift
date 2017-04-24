//
//  CSGen.swift
//  Trill
//
//  Created by Robert Widmann on 3/14/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

final class Solver {
  typealias ConstraintSystem = [Constraint]
  typealias Solution = [String: DataType]

  let context: ASTContext

  init(context: ASTContext) {
    self.context = context
  }

  enum ConstraintKind {
    case equal(DataType, DataType)
    case conforms(DataType, DataType)
  }

  struct Constraint {
    let kind: ConstraintKind
    let location: StaticString
    let node: ASTNode?

    func withKind(_ kind: ConstraintKind) -> Constraint {
      return Constraint(kind: kind, location: location, node: node)
    }
  }

  func solveSystem(_ cs: ConstraintSystem) -> Solution? {
    var sub: Solution = [:]
    for c in cs {
      guard let soln = self.solveSingle(c) else { return nil }
      sub.unionInPlace(soln)
    }
    return sub
  }

  // Unify
  func solveSingle(_ c: Constraint) -> Solution? {
    switch c.kind {
    case let .conforms(_t1, _t2):
      // Canonicalize types before checking.
      let t1 = context.canonicalType(_t1)
      let t2 = context.canonicalType(_t2)

      guard
        let typeDecl = context.decl(for: t1),
        let protocolDecl = context.protocolDecl(for: t2) else {
        return nil
      }

      guard context.conformsToProtocol(typeDecl, protocolDecl) else {
        return nil
      }

      return solveSingle(c.withKind(.equal(t1, .any)))

    case let .equal(_t1, _t2):

      // Canonicalize types before checking.
      let t1 = context.canonicalType(_t1)
      let t2 = context.canonicalType(_t2)

      // If the two types are already equal there's nothing to be done.
      if t1 == t2 {
        return [:]
      }

      switch (t1, t2) {
      case let (t, .metaVariable(m)):
        // Perform the occurs check
        if t.contains(m) {
          fatalError("Infinite type")
        }
        // Unify the metavariable with the concrete type.
        return [m: _t1]
      case let (.metaVariable(m), t):
        // Perform the occurs check
        if t.contains(m) {
          fatalError("Infinite type")
        }
        // Unify the metavariable with the concrete type.
        return [m: _t2]
      case let (t, .typeVariable(m)):
        // Perform the occurs check
        if t.contains(m) {
          fatalError("Infinite type")
        }
        // Unify the type variable with the concrete type.
        return [m: _t1]
      case let (.typeVariable(m), t):
        // Perform the occurs check
        if t.contains(m) {
          fatalError("Infinite type")
        }
        // Unify the type variable with the concrete type.
        return [m: _t2]
      case let (.function(args1, returnType1, hasVarArgs1), .function(args2, returnType2, hasVarArgs2)):

        guard args1.count == args2.count || hasVarArgs1 || hasVarArgs2 else {
          break
        }

        var system = zip(args1, args2).map(ConstraintKind.equal)
        system.insert(.equal(returnType1, returnType2), at: 0)

        return solveSystem(system.map(c.withKind))
      case (.pointer(_), .pointer(_)):
        // Pointers may unify with any other kind of pointer.
        return [:]
      case (.bool, .int):
        // Boolean values may coerce to integer values (but not vice-versa).
        return [:]
      case (_, .any), (.any, _):
        // Anything can unify to an existential
        return [:]
      default:
        break
      }
      context.diag.error("cannot convert value of type \(t1) to \(t2)",
                         loc: c.node?.startLoc,
                         highlights: [
                           c.node?.sourceRange
                         ])
      return [:]
    }
  }

  final class Generator: ASTTransformer {
    var goal: DataType = .error
    var env: [Identifier: DataType] = [:]
    var constraints: [Constraint] = []

    func reset(with env: [Identifier: DataType]) {
      self.goal = .error
      self.env = env
      self.constraints = []
    }

    func byBinding(_ n: Identifier, _ t: DataType, _ f: () -> ()) {
      let oldEnv = self.env
      self.env[n] = t
      f()
      self.env = oldEnv
    }

    // MARK: Monotypes

    override func visitVarExpr(_ expr: VarExpr) {
      if expr.isSelf {
        self.goal = expr.type
        return
      }

      if let t = self.env[expr.name] ?? self.context.global(named: expr.name)?.type {
        self.goal = t
        return
      }
      
//      let functions = self.context.functions(named: expr.name)
//      guard !functions.isEmpty else {
//        fatalError()
//      }
//
//      // If we can avoid overload resolution, avoid it
//      if functions.count == 1 {
//        self.goal = functions[0].type!
//      } else {
//        self.goal = DataType.function(args: [ DataType.freshTypeVariable ], returnType: DataType.freshTypeVariable, hasVarArgs: false)
//      }
      self.goal = expr.decl!.type
    }

    override func visitSizeofExpr(_ expr: SizeofExpr) {
      self.goal = expr.type
    }

    override func visitPropertyRefExpr(_ expr: PropertyRefExpr) {
      visit(expr.lhs)
      let lhsGoal = self.goal
      constrainEqual(expr.typeDecl!, lhsGoal)

      let tau = DataType.freshMetaVariable
      constrainEqual(expr.decl!, tau)

      self.goal = tau
    }

    override func visitVarAssignDecl(_ expr: VarAssignDecl) {
      let goalType: DataType
      // let <ident>: <Type> = <expr>
      if let e = expr.rhs {
        goalType = e.type
        byBinding(expr.name, goalType, {
          visit(e)
        })
        // Bind the given type to the goal type the initializer generated.
        constrainEqual(goalType, self.goal, node: e)
      }
      // let <ident> = <expr>
      else if let e = expr.rhs {
        // Generate 
        let tau = DataType.freshMetaVariable
        byBinding(expr.name, tau, {
          visit(e)
        })
        if let phi = Solver(context: context).solveSystem(self.constraints) {
          goalType = tau.substitute(phi)
        } else {
          goalType = tau
        }
      } else {
        // let <ident>: <Type>
        // Take the type binding as fact and move on.
        goalType = expr.type
        self.env[expr.name] = goalType
      }

      self.goal = goalType
    }

    override func visitFuncDecl(_ expr: FuncDecl) {
      if let body = expr.body {
        let oldEnv = self.env
        for p in expr.args {
          // Bind the type of the parameters.
          self.env[p.name] = p.type
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
      if let pre = expr.lhs as? PropertyRefExpr {
        goals.append(pre.lhs.type)
      }
      for arg in expr.args {
        visit(arg.val)
        goals.append(self.goal)
      }
      let tau = DataType.freshMetaVariable
      constrainEqual(lhsGoal,
                     .function(args: goals, returnType: tau, hasVarArgs: false),
                     node: expr.lhs)
      self.goal = tau
    }

    override func visitIsExpr(_ expr: IsExpr) {
      let tau = DataType.freshMetaVariable
      constrainEqual(expr, .bool)
      constrainEqual(expr.rhs, tau)
      self.goal = tau
    }

    override func visitCoercionExpr(_ expr: CoercionExpr) {
      let tau = DataType.freshMetaVariable
      constrainEqual(expr, tau)
      constrainEqual(expr.rhs, tau)
      self.goal = tau
    }

    override func visitInfixOperatorExpr(_ expr: InfixOperatorExpr) {
      let tau = DataType.freshMetaVariable
      let lhsGoal = expr.decl!.type
      var goals: [DataType] = []
      [ expr.lhs, expr.rhs ].forEach { e in
        visit(e)
        goals.append(self.goal)
      }
      constrainEqual(lhsGoal,
                     .function(args: goals, returnType: tau, hasVarArgs: false),
                     node: expr.lhs)
      self.goal = tau
    }

    override func visitSubscriptExpr(_ expr: SubscriptExpr) {
      visit(expr.lhs)
      var goals: [DataType] = [ self.goal ]
      expr.args.forEach { a in
        visit(a.val)
        goals.append(self.goal)
      }
      let tau = DataType.freshMetaVariable
      if let decl = expr.decl {
        constrainEqual(decl, .function(args: goals, returnType: tau, hasVarArgs: false))
      }
      self.goal = tau
    }

    override func visitArrayExpr(_ expr: ArrayExpr) {
      guard case .array(_, let length) = expr.type else {
        fatalError("invalid array type")
      }
      let tau = DataType.freshMetaVariable
      for value in expr.values {
        visit(value)
        constrainGoal(tau, node: value)
      }
      let goal = DataType.array(field: tau, length: length)
      constrainEqual(expr, goal)
      self.goal = goal
    }

    override func visitTupleExpr(_ expr: TupleExpr) {
      var goals = [DataType]()
      for element in expr.values {
        visit(element)
        goals.append(self.goal)
      }
      constrainEqual(expr, .tuple(fields: goals))
      self.goal = expr.type
    }

    override func visitTernaryExpr(_ expr: TernaryExpr) {
      let tau = DataType.freshMetaVariable

      visit(expr.condition)
      constrainEqual(expr.condition, .bool)

      visit(expr.trueCase)
      constrainEqual(expr.trueCase, tau)

      visit(expr.falseCase)
      constrainEqual(expr.falseCase, tau)

      constrainEqual(expr, tau)
      self.goal = tau
    }

    override func visitPrefixOperatorExpr(_ expr: PrefixOperatorExpr) {
      visit(expr.rhs)
      let rhsGoal = self.goal
      switch expr.op {
      case .ampersand:
        constrainEqual(expr, .pointer(type: rhsGoal))
      case .bitwiseNot:
        constrainEqual(expr, rhsGoal)
      case .minus:
        constrainEqual(expr, rhsGoal)
      case .not:
        constrainEqual(expr, .bool)
        constrainEqual(rhsGoal, .bool, node: expr.rhs)
      case .star:
        guard case .pointer(let element) = expr.rhs.type else {
          fatalError("invalid dereference?")
        }
        constrainEqual(expr, element)
      default:
        fatalError("invalid prefix operator: \(expr.op)")
      }
    }

    override func visitTupleFieldLookupExpr(_ expr: TupleFieldLookupExpr) {
      visit(expr.lhs)
      let lhsGoal = self.goal

      constrainEqual(expr.decl!, lhsGoal)
      let tau = DataType.freshMetaVariable

      constrainEqual(expr, tau)
      self.goal = tau
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

    func constrainEqual(_ d: Decl, _ t: DataType, caller: StaticString = #function) {
      constraints.append(Constraint(kind: .equal(d.type, t), location: caller, node: d))
    }

    func constrainEqual(_ e: Expr, _ t: DataType, caller: StaticString = #function) {
      constraints.append(Constraint(kind: .equal(e.type, t), location: caller, node: e))
    }

    func constrainEqual(_ t1: DataType, _ t2: DataType, node: ASTNode? = nil, caller: StaticString = #function) {
      constraints.append(Constraint(kind: .equal(t1, t2), location: caller, node: node))
    }

    func constrainGoal(_ t: DataType, node: ASTNode? = nil, caller: StaticString = #function) {
      constraints.append(Constraint(kind: .equal(goal, t), location: caller, node: node))
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
}

extension Dictionary {
  mutating func unionInPlace(_ with: Dictionary) {
    with.forEach { self.updateValue($1, forKey: $0) }
  }

  func union(_ other: Dictionary) -> Dictionary {
    var dictionary = other
    dictionary.unionInPlace(self)
    return dictionary
  }

  init<S: Sequence>(_ pairs: S) where S.Iterator.Element == (Key, Value) {
    self.init()
    var g = pairs.makeIterator()
    while let (k, v): (Key, Value) = g.next() {
      self[k] = v
    }
  }
}

