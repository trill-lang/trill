//
//  Type.swift
//  Trill
//

import Foundation

enum FloatingPointType {
  case float, double, float80
}

enum DataType: CustomStringConvertible, Hashable {
  case int(width: Int, signed: Bool)
  case floating(type: FloatingPointType)
  case bool
  case void
  case custom(name: String)
  case any
  indirect case function(args: [DataType], returnType: DataType)
  indirect case pointer(type: DataType)
  indirect case array(field: DataType, length: Int?)
  indirect case tuple(fields: [DataType])
  
  static let int64 = DataType.int(width: 64, signed: true)
  static let int32 = DataType.int(width: 32, signed: true)
  static let int16 = DataType.int(width: 16, signed: true)
  static let int8 = DataType.int(width: 8, signed: true)
  static let uint64 = DataType.int(width: 64, signed: false)
  static let uint32 = DataType.int(width: 32, signed: false)
  static let uint16 = DataType.int(width: 16, signed: false)
  static let uint8 = DataType.int(width: 8, signed: false)
  static let float = DataType.floating(type: .float)
  static let double = DataType.floating(type: .double)
  static let float80 = DataType.floating(type: .float80)
  static func incompleteArray(field: DataType) -> DataType {
    return .array(field: field, length: nil)
  }
  static let string = DataType.pointer(type: .int8)
  
  init(name: String) {
    switch name {
    case "Int8": self = .int8
    case "Int16": self = .int16
    case "Int32": self = .int32
    case "Int": self = .int64
    case "UInt8": self = .uint8
    case "UInt16": self = .uint16
    case "UInt32": self = .uint32
    case "UInt": self = .uint64
    case "Bool": self = .bool
    case "Void": self = .void
    case "Float": self = .float
    case "Double": self = .double
    case "Float80": self = .float80
    case "Any": self = .any
    default: self = .custom(name: name)
    }
  }
  
  var rootType: DataType {
    switch self {
    case .array(let field, _):
      return field
    case .pointer(let type):
      return type.rootType
    default:
      return self
    }
  }
  
  var description: String {
    switch self {
    case .int(width: 64, let signed):
      return "\(signed ? "" : "U")Int"
    case .int(let width, let signed):
      return "\(signed ? "" : "U")Int\(width)"
    case .bool: return "Bool"
    case .void: return "Void"
    case .array(let field, let length):
      var s = "[\(field)"
      if let length = length {
        s += "; \(length)"
      }
      return s + "]"
    case .custom(let name): return name
    case .pointer(let type):
      return "*\(type)"
    case .floating(let type):
      switch type {
      case .float:
        return "Float"
      case .double:
        return "Double"
      case .float80:
        return "Float80"
      }
    case .tuple(let fields):
      return "(\(fields.map { $0.description }.joined(separator: ", ")))"
    case .function(let args, let ret):
      let args = args.map { $0.description }.joined(separator: ", ")
      return "(\(args)) -> \(ret)"
    case .any: return "Any"
    }
  }
  
  var hashValue: Int {
    return self.description.hashValue ^ 0x09ad3f14
  }
  
  var isPointer: Bool {
    if case .pointer = self { return true }
    return false
  }
  
  func pointerLevel() -> Int {
    guard case .pointer(let t) = self else { return 0 }
    return t.pointerLevel() + 1
  }
  
  func canCoerceTo(_ type: DataType) -> Bool {
    if self == type { return true }
    switch (self, type) {
    case (.int, .int): return true
    case (.int, .floating): return true
    case (.floating, .int): return true
    case (.int, .pointer): return true
    case (.pointer, .int): return true
    case (.pointer, .pointer): return true
    default: return false
    }
  }
}

func ==(lhs: DataType, rhs: DataType) -> Bool {
  switch (lhs, rhs) {
  case (.int(let width, let signed), .int(let otherWidth, let otherSigned)):
    return width == otherWidth && signed == otherSigned
  case (.bool, .bool): return true
  case (.void, .void): return true
  case (.custom(let lhsName), .custom(let rhsName)):
    return lhsName == rhsName
  case (.pointer(let lhsType), .pointer(let rhsType)):
    return lhsType == rhsType
  case (.floating(let double), .floating(let rhsDouble)):
    return double == rhsDouble
  case (.any, .any): return true
  case (.array(let field, _), .array(let field2, _)):
    return field == field2
  case (.function(let args, let ret), .function(let args2, let ret2)):
    return args == args2 && ret == ret2
  case (.tuple(let fields), .tuple(let fields2)):
    return fields == fields2
  default: return false
  }
}

class Decl: ASTNode {
  var type: DataType
  let modifiers: Set<DeclModifier>
  func has(attribute: DeclModifier) -> Bool {
    return modifiers.contains(attribute)
  }
  init(type: DataType, modifiers: [DeclModifier], sourceRange: SourceRange?) {
    self.modifiers = Set(modifiers)
    self.type = type
    super.init(sourceRange: sourceRange)
  }
  
  override func attributes() -> [String : Any] {
    var attrs = super.attributes()
    attrs["type"] = "\(type)"
    if !modifiers.isEmpty {
      attrs["modifiers"] = modifiers.map { "\($0)" }.sorted().joined(separator: ", ")
    }
    return attrs
  }
}

class TypeDecl: Decl {
  private(set) var genericParams: [GenericParamDecl]
  private(set) var properties: [PropertyDecl]
  private(set) var methods = [MethodDecl]()
  private(set) var staticMethods = [MethodDecl]()
  private(set) var subscripts = [SubscriptDecl]()
  private(set) var initializers = [InitializerDecl]()
  private var propertyDict = [String: DataType]()
  private var methodDict = [String: [MethodDecl]]()
  private var staticMethodDict = [String: [MethodDecl]]()
  var conformances: [TypeRefExpr]
  
  let name: Identifier
  let deinitializer: DeinitializerDecl?
  
  func indexOfProperty(named name: Identifier) -> Int? {
    return properties.lazy
                     .filter { !$0.isComputed }
                     .index { $0.name == name }
  }
  
  func addInitializer(_ decl: InitializerDecl) {
    self.initializers.append(decl)
  }
  
  func addMethod(_ decl: MethodDecl, named name: String) {
    self.methods.append(decl)
    var methods = methodDict[name] ?? []
    methods.append(decl)
    methodDict[name] = methods
  }
  
  func addStaticMethod(_ decl: MethodDecl, named name: String) {
    self.staticMethods.append(decl)
    var methods = staticMethodDict[name] ?? []
    methods.append(decl)
    staticMethodDict[name] = methods
  }
  
  func addSubscript(_ decl: SubscriptDecl) {
    self.subscripts.append(decl)
  }
  
  func addProperty(_ property: PropertyDecl) {
    properties.append(property)
    propertyDict[property.name.name] = property.type
  }
  
  func methods(named name: String) -> [MethodDecl] {
    return methodDict[name] ?? []
  }
  
  func staticMethods(named name: String) -> [MethodDecl] {
    return staticMethodDict[name] ?? []
  }
  
  func property(named name: String) -> VarAssignDecl? {
    for property in properties where property.name.name == name {
      return property
    }
    return nil
  }
  
  func typeOf(_ field: String) -> DataType? {
    return propertyDict[field]
  }
  
  func createRef() -> TypeRefExpr {
    return TypeRefExpr(type: self.type, name: self.name)
  }

  func methodsSatisfyingRequirements(of proto: ProtocolDecl) -> [MethodDecl] {
    return methods.filter { $0.satisfiedProtocols.contains(proto) }
  }
  
  static func synthesizeInitializer(properties: [PropertyDecl],
                                    genericParams: [GenericParamDecl],
                                    type: DataType) -> InitializerDecl {
    let initProperties = properties.lazy
                                   .filter { !$0.isComputed }
                                   .map { ParamDecl(name: $0.name,
                                                    type: $0.typeRef!,
                                                    externalName: $0.name) }
    return InitializerDecl(parentType: type,
                           args: Array(initProperties),
                           genericParams: genericParams,
                           returnType: type.ref(),
                           body: CompoundStmt(stmts: []),
                           modifiers: [.implicit])
  }
  
  init(name: Identifier,
       properties: [PropertyDecl],
       methods: [MethodDecl] = [],
       staticMethods: [MethodDecl] = [],
       initializers: [InitializerDecl] = [],
       subscripts: [SubscriptDecl] = [],
       modifiers: [DeclModifier] = [],
       conformances: [TypeRefExpr] = [],
       deinit: DeinitializerDecl? = nil,
       genericParams: [GenericParamDecl] = [],
       sourceRange: SourceRange? = nil) {
    self.properties = properties
    self.initializers = initializers
    let type = DataType(name: name.name)
    self.deinitializer = `deinit`
    let synthInit = TypeDecl.synthesizeInitializer(properties: properties,
                                                   genericParams: genericParams,
                                                   type: type)
    self.initializers.append(synthInit)
    self.name = name
    self.conformances = conformances
    self.genericParams = genericParams
    super.init(type: type, modifiers: modifiers, sourceRange: sourceRange)
    for method in methods {
      self.addMethod(method, named: method.name.name)
    }
    for method in staticMethods {
      self.addStaticMethod(method, named: method.name.name)
    }
    for subscriptDecl in subscripts {
      self.addSubscript(subscriptDecl)
    }
    for property in properties {
      propertyDict[property.name.name] = property.type
    }
  }

  /// Finds all properties that are not computed and actually contribute
  /// to the size of this type.
  var storedProperties: [PropertyDecl] {
    return properties.filter { !$0.isComputed }
  }
  
  var isIndirect: Bool {
    return has(attribute: .indirect)
  }
}

class DeclRefExpr<DeclType: Decl>: Expr {
  weak var decl: DeclType? = nil
  override init(sourceRange: SourceRange?) {
    super.init(sourceRange: sourceRange)
  }
}

class PropertyDecl: VarAssignDecl {
  let getter: PropertyGetterDecl?
  let setter: PropertySetterDecl?

  var isComputed: Bool {
    return getter != nil || setter != nil
  }

  init(name: Identifier, type: TypeRefExpr,
       mutable: Bool, rhs: Expr?, modifiers: [DeclModifier],
       getter: PropertyGetterDecl?, setter: PropertySetterDecl?,
       sourceRange: SourceRange? = nil) {
    self.getter = getter
    self.setter = setter

    super.init(name: name, typeRef: type,
               rhs: rhs, modifiers: modifiers,
               mutable: mutable, sourceRange: sourceRange)!
  }
}

class PropertyGetterDecl: MethodDecl {
  let propertyName: Identifier
  init(parentType: DataType, propertyName: Identifier, type: TypeRefExpr, body: CompoundStmt, sourceRange: SourceRange? = nil) {
    self.propertyName = propertyName
    super.init(name: "",
               parentType: parentType,
               args: [],
               genericParams: [],
               returnType: type,
               body: body,
               modifiers: [],
               hasVarArgs: false,
               sourceRange: sourceRange)
  }
}

class PropertySetterDecl: MethodDecl {
  let propertyName: Identifier
  init(parentType: DataType,
       propertyName: Identifier,
       type: TypeRefExpr,
       body: CompoundStmt,
       sourceRange: SourceRange? = nil) {
    self.propertyName = propertyName
    super.init(name: "",
               parentType: parentType,
               args: [ParamDecl(name: "newValue", type: type)],
               genericParams: [],
               returnType: DataType.void.ref(),
               body: body,
               modifiers: [],
               hasVarArgs: false,
               sourceRange: sourceRange)
  }
}

class TypeAliasDecl: Decl {
  let name: Identifier
  let bound: TypeRefExpr
  var decl: TypeDecl?
  init(name: Identifier, bound: TypeRefExpr, modifiers: [DeclModifier] = [], sourceRange: SourceRange? = nil) {
    self.name = name
    self.bound = bound
    super.init(type: bound.type!, modifiers: modifiers, sourceRange: sourceRange)
  }
  override func attributes() -> [String : Any] {
    var superAttrs = super.attributes()
    superAttrs["name"] = name.name
    return superAttrs
  }
}

class TypeRefExpr: DeclRefExpr<TypeDecl> {
  let name: Identifier
  init(type: DataType, name: Identifier, sourceRange: SourceRange? = nil) {
    self.name = name
    super.init(sourceRange: sourceRange ?? name.range)
    self.type = type
  }
}

extension DataType {
  func ref(range: SourceRange? = nil) -> TypeRefExpr {
    return TypeRefExpr(type: self, name: Identifier(name: "\(self)", range: range), sourceRange: range)
  }
}

class FuncTypeRefExpr: TypeRefExpr {
  let argNames: [TypeRefExpr]
  let retName: TypeRefExpr
  init(argNames: [TypeRefExpr], retName: TypeRefExpr, sourceRange: SourceRange? = nil) {
    self.argNames = argNames
    self.retName = retName
    let argTypes = argNames.map { $0.type! }
    let argStrings = argNames.map { $0.name.name }
    var fullName = "(" + argStrings.joined(separator: ", ") + ")"
    if retName != .void {
      fullName += " -> " + retName.name.name
    }
    let fullId = Identifier(name: fullName, range: sourceRange)
    super.init(type: .function(args: argTypes, returnType: retName.type!), name: fullId, sourceRange: sourceRange)
  }
}

class PointerTypeRefExpr: TypeRefExpr {
  let pointed: TypeRefExpr
  init(pointedTo: TypeRefExpr, level: Int, sourceRange: SourceRange? = nil) {
    self.pointed = pointedTo
    let fullName = String(repeating: "*", count: level) + pointedTo.name.name
    let fullId = Identifier(name: fullName, range: sourceRange)
    var type = pointedTo.type!
    for _ in 0..<level {
      type = .pointer(type: type)
    }
    super.init(type: type, name: fullId, sourceRange: sourceRange)
  }
}

class GenericTypeRefExpr: TypeRefExpr {
  let unspecializedType: TypeRefExpr
  let args: [GenericParam]

  init(unspecializedType: TypeRefExpr, args: [GenericParam], sourceRange: SourceRange? = nil) {
    self.unspecializedType = unspecializedType
    self.args = args
    let commaSepArgs = args.map { $0.typeName.name.name }
                           .joined(separator: ", ")
    let fullName = Identifier(name: "\(unspecializedType.name)<\(commaSepArgs)>",
                              range: sourceRange)
    super.init(type: unspecializedType.type!,
               name: fullName,
               sourceRange: sourceRange)
  }
}

class ArrayTypeRefExpr: TypeRefExpr {
  let element: TypeRefExpr
  init(element: TypeRefExpr, length: Int? = nil, sourceRange: SourceRange? = nil) {
    self.element = element
    let fullId = Identifier(name: "[\(element.name.name)]",
                            range: sourceRange)
    super.init(type: .array(field: element.type!, length: length),
               name: fullId,
               sourceRange: sourceRange)
  }
}

class TupleTypeRefExpr: TypeRefExpr {
  let fieldNames: [TypeRefExpr]
  init(fieldNames: [TypeRefExpr], sourceRange: SourceRange? = nil) {
    self.fieldNames = fieldNames
    let argTypes = fieldNames.map { $0.type! }
    let fullName = "(\(fieldNames.map { $0.name.name }.joined(separator: ", ")))"
    super.init(type: .tuple(fields: argTypes),
               name: Identifier(name: fullName, range: sourceRange),
               sourceRange: sourceRange)
  }
}

func ==(lhs: TypeRefExpr, rhs: DataType) -> Bool {
  return lhs.type == rhs
}
func !=(lhs: TypeRefExpr, rhs: DataType) -> Bool {
  return lhs.type != rhs
}
func ==(lhs: DataType, rhs: TypeRefExpr) -> Bool {
  return lhs == rhs.type
}
func !=(lhs: DataType, rhs: TypeRefExpr) -> Bool {
  return lhs != rhs.type
}
