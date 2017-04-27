//
//  Counter.swift
//  trill
//
//  Created by Harlan Haskins on 4/25/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

/// A structure that counts the number of times a certain element has been
/// inserted into it.
struct Counter<Element>: Sequence where Element: Hashable {
  private var storage = [Element: Int]()

  /// Adds to this element's count of occurrences.
  /// - parameter element: The element you're adding to the counter.
  mutating func count(_ element: Element, times: Int = 1) {
    storage[element] = (storage[element] ?? 0) + times
  }

  /// Finds the number of times the element occurs in the counter.
  /// - parameter element: The element you're looking up.
  /// - returns: The number of times that element occurs in the counter.
  subscript(_ element: Element) -> Int {
    return storage[element] ?? 0
  }

  /// Adds all the counts from a given counter to this counter.
  mutating func addCounts(from counter: Counter<Element>) {
    for (element, count) in counter {
      self.count(element, times: count)
    }
  }

  /// Whether or not this counter has registered any values.
  var isEmpty: Bool {
    return storage.isEmpty
  }

  /// Makes an iterator for looping over these elements.
  func makeIterator() -> AnyIterator<(Element, Int)> {
    var iter = storage.makeIterator()
    return AnyIterator {
      return iter.next()
    }
  }
}
