//
//  Either.swift
//  trill
//
//  Created by Harlan Haskins on 4/28/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import Foundation

/// Represents one of two possibilities.
enum Either<Left, Right> {
  case left(Left)
  case right(Right)
}
