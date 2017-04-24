//
//  ConstraintError.swift
//  trill
//
//  Created by Harlan Haskins on 4/13/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

enum ConstraintError: Error, CustomStringConvertible {
  case ambiguousExpressionType
  case cannotConvert(DataType, to: DataType)

  var description: String {
    switch self {
    case .ambiguousExpressionType:
      return "type of expression is ambiguous without more context"
    case let .cannotConvert(t1, t2):
      return "cannot convert value of type \(t1) to \(t2)"
    }
  }
}
