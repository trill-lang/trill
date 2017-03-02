//
//  SemaError.swift
//  Trill
//
//  Created by Harlan Haskins on 10/22/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

import Foundation

enum SemaError: Error, CustomStringConvertible {
  case unknownFunction(name: Identifier)
  case unknownType(type: DataType)
  case unknownProtocol(name: Identifier)
  case callNonFunction(type: DataType?)
  case unknownProperty(typeDecl: TypeDecl, expr: PropertyRefExpr)
  case unknownVariableName(name: Identifier)
  case invalidOperands(op: BuiltinOperator, invalid: DataType)
  case cannotSubscript(type: DataType)
  case cannotCoerce(type: DataType, toType: DataType)
  case varArgsInNonForeignDecl
  case foreignFunctionWithBody(name: Identifier)
  case nonForeignFunctionWithoutBody(name: Identifier)
  case foreignVarWithRHS(name: Identifier)
  case dereferenceNonPointer(type: DataType)
  case cannotSwitch(type: DataType)
  case nonPointerNil(type: DataType)
  case notAllPathsReturn(type: DataType)
  case noViableOverload(name: Identifier, args: [Argument])
  case candidates([FuncDecl])
  case ambiguousReference(name: Identifier)
  case addressOfRValue
  case breakNotAllowed
  case continueNotAllowed
  case caseMustBeConstant
  case isCheckAlways(fails: Bool)
  case fieldOfFunctionType(type: DataType)
  case duplicateMethod(name: Identifier, type: DataType)
  case duplicateField(name: Identifier, type: DataType)
  case referenceSelfInProp(name: Identifier)
  case poundFunctionOutsideFunction
  case assignToConstant(name: Identifier?)
  case deinitOnStruct(name: Identifier)
  case incompleteTypeAccess(type: DataType, operation: String)
  case indexIntoNonTuple
  case outOfBoundsTupleField(field: Int, max: Int)
  case nonMatchingArrayType(DataType, DataType)
  case ambiguousType
  case operatorsMustHaveTwoArgs(op: BuiltinOperator)
  case cannotOverloadOperator(op: BuiltinOperator, type: String)
  case typeDoesNotConform(DataType, protocol: DataType)
  case missingImplementation(FuncDecl)
  case pointerPropertyAccess(lhs: DataType, property: Identifier)
  case tuplePropertyAccess(lhs: DataType, property: Identifier)

  var description: String {
    switch self {
    case .unknownFunction(let name):
      return "unknown function '\(name)'"
    case .unknownType(let type):
      return "unknown type '\(type)'"
    case .unknownProtocol(let name):
      return "unknown protocol '\(name)'"
    case .unknownVariableName(let name):
      return "unknown variable '\(name)'"
    case .unknownProperty(let typeDecl, let expr):
      return "unknown property '\(expr.name)' in type '\(typeDecl.type)'"
    case .invalidOperands(let op, let invalid):
      return "invalid argument for operator '\(op)' (got '\(invalid)')"
    case .cannotSubscript(let type):
      return "cannot subscript value of type '\(type)'"
    case .cannotCoerce(let type, let toType):
      return "cannot coerce '\(type)' to '\(toType)'"
    case .cannotSwitch(let type):
      return "cannot switch over values of type '\(type)'"
    case .foreignFunctionWithBody(let name):
      return "foreign function '\(name)' cannot have a body"
    case .nonForeignFunctionWithoutBody(let name):
      return "function '\(name)' must have a body"
    case .foreignVarWithRHS(let name):
      return "foreign var '\(name)' cannot have a value"
    case .varArgsInNonForeignDecl:
      return "varargs in non-foreign declarations are not yet supported"
    case .nonPointerNil(let type):
      return "cannot set non-pointer type '\(type)' to nil"
    case .dereferenceNonPointer(let type):
      return "cannot dereference a value of non-pointer type '\(type)'"
    case .addressOfRValue:
      return "cannot get address of an r-value"
    case .breakNotAllowed:
      return "'break' not allowed outside loop"
    case .continueNotAllowed:
      return "'continue' not allowed outside loop"
    case .notAllPathsReturn(let type):
      return "missing return in a function expected to return \(type)"
    case .noViableOverload(let name, let args):
      var s = "could not find a viable overload for \(name) with arguments of type ("
      s += args.map {
        var d = ""
        if let label = $0.label {
          d += "\(label): "
        }
        if let t = $0.val.type {
          d += "\(t)"
        } else {
          d += "<<error type>>"
        }
        return d
        }.joined(separator: ", ")
      s += ")"
      return s
    case .candidates(let functions):
      var s = "found candidates with these arguments: "
      s += functions.map { $0.formattedParameterList }.joined(separator: ", ")
      return s
    case .ambiguousReference(let name):
      return "ambiguous reference to '\(name)'"
    case .callNonFunction(let type):
      return "cannot call non-function type '" + (type.map { String(describing: $0) } ?? "<<error type>>") + "'"
    case .fieldOfFunctionType(let type):
      return "cannot find field on function of type \(type)"
    case .duplicateMethod(let name, let type):
      return "invalid redeclaration of method '\(name)' on type '\(type)'"
    case .duplicateField(let name, let type):
      return "invalid redeclaration of field '\(name)' on type '\(type)'"
    case .referenceSelfInProp(let name):
      return "type '\(name)' cannot have a property that references itself"
    case .poundFunctionOutsideFunction:
      return "'#function' is only valid inside function scope"
    case .deinitOnStruct(let name):
      return "cannot have a deinitializer in non-indirect type '\(name)'"
    case .assignToConstant(let name):
      let val: String
      if let n = name {
        val = "'\(n)'"
      } else {
        val = "expression"
      }
      return "cannot mutate \(val); expression is a 'let' constant"
    case .indexIntoNonTuple:
      return "cannot index into non-tuple expression"
    case .outOfBoundsTupleField(let field, let max):
      return "cannot access field \(field) in tuple with \(max) fields"
    case .incompleteTypeAccess(let type, let operation):
      return "cannot \(operation) incomplete type '\(type)'"
    case .nonMatchingArrayType(let arrayType, let elementType):
      return "element type '\(elementType)' does not match array type '\(arrayType)'"
    case .ambiguousType:
      return "type is ambiguous without more context"
    case .caseMustBeConstant:
      return "case statement expressions must be constants"
    case .isCheckAlways(let fails):
      return "'is' check always \(fails ? "fails" : "succeeds")"
    case .operatorsMustHaveTwoArgs(let op):
      return "definition for operator '\(op)' must have two arguments"
    case .cannotOverloadOperator(let op, let type):
      return "cannot overload \(type) operator '\(op)'"
    case .typeDoesNotConform(let typeName, let `protocol`):
      return "'\(typeName)' does not conform to protocol '\(`protocol`)'"
    case .missingImplementation(let decl):
      return "missing implementation for '\(decl.formattedName)'"
    case .pointerPropertyAccess(let lhs, let property):
      return "cannot access property \(property) of pointer type \(lhs)"
    case .tuplePropertyAccess(let lhs, let property):
      return "cannot access property \(property) on tuple type \(lhs)"
    }
  }
}
