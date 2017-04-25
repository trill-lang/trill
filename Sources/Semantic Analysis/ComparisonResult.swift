//
//  ComparisonResult.swift
//  trill
//
//  Created by Harlan Haskins on 4/25/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

/// Describes a ordering relationship between two objects.
enum ComparisonResult {
  /// The two objects are in ascending order.
  case ascending

  /// The two objects are in descending order.
  case descending

  /// No definitive order could be determined between the two objects.
  case unordered
}
