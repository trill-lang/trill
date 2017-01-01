//
//  AttributedStringStream.swift
//  Trill
//
//  Created by Harlan Haskins on 1/1/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

import UIKit

class AttributedStringStream: ColoredStream {
  var storage = NSMutableAttributedString()
  let palette: TextAttributes
  init(palette: TextAttributes) {
    self.palette = palette
  }
  func write(_ string: String, with colors: [ANSIColor]) {
    var attributes = [String: Any]()
    var font = palette.font
    for color in colors {
      if color == .bold {
        font = palette.boldFont
      } else {
        let uiColor: UIColor? = {
          switch color {
          case .black: return .black
          case .red: return palette.string
          case .magenta: return palette.keyword
          case .blue: return palette.externalName
          case .green: return palette.internalName
          case .cyan: return palette.externalName
          case .white: return .white
          default: return nil
          }
        }()
        attributes[NSForegroundColorAttributeName] = uiColor
      }
    }
    if attributes[NSForegroundColorAttributeName] == nil {
      attributes[NSForegroundColorAttributeName] = UIColor.white
    }
    attributes[NSFontAttributeName] = font
    let newStr = NSAttributedString(string: string, attributes: attributes)
    storage.append(newStr)
  }
}
