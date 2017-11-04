//
//  CHelpers.swift
//  Source
//
//  Created by Harlan Haskins on 7/20/17.
//

import Foundation

extension Collection where Iterator.Element == String, IndexDistance == Int {
  public func withCArrayOfCStrings<Result>(
    _ f: (UnsafeMutablePointer<UnsafePointer<Int8>?>) throws -> Result) rethrows -> Result {
    let ptr = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>.allocate(capacity: self.count)
    defer  { freeList(ptr, count: self.count) }
    for (idx, str) in enumerated() {
      str.withCString { cStr in
        ptr[idx] = strdup(cStr)
      }
    }
    return try ptr.withMemoryRebound(to: Optional<UnsafePointer<Int8>>.self,
                                     capacity: self.count, f)
  }
}

public func freeList<T>(_ ptr: UnsafeMutablePointer<UnsafeMutablePointer<T>?>,
                        count: Int) {
  for i in 0..<count {
    free(ptr[i])
  }
  free(ptr)
}
