//
//  RuntimeTests.swift
//  RuntimeTests
//
//  Created by Harlan Haskins on 7/16/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

import XCTest

@_silgen_name("trill_init")
func trill_init()

class RuntimeTests: XCTestCase {
  override func setUp() {
    trill_init()
  }
  func test_trill_alloc() {
    for _ in 0..<1000 {
      _ = trill_alloc(MemoryLayout<Int>.size)
    }
  }
  func test_stacktrace() {
    "".withCString { s in
      trill_fatalError(s)
    }
  }
}
