//
//  Identifier.swift
//  Trill
//

struct Identifier: CustomStringConvertible, ExpressibleByStringLiteral, Equatable, Hashable {
  let name: String
  let range: SourceRange?
  
  init(name: String, range: SourceRange? = nil) {
    self.name = name
    self.range = range
  }
  
  init(stringLiteral value: String) {
    name = value
    range = nil
  }
  
  init(unicodeScalarLiteral value: UnicodeScalarType) {
    name = value
    range = nil
  }
  
  init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterType) {
    name = value
    range = nil
  }
  
  var hashValue: Int {
    return name.hashValue ^ 0x23423454
  }
  
  var description: String {
    return name
  }
}

func ==(lhs: Identifier, rhs: Identifier) -> Bool {
  return lhs.name == rhs.name
}
