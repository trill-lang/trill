//
//  Utilities.swift
//  Trill
//

import Foundation

func format(time: Double) -> String {
  var time = time
  let unit: String
  let formatter = NumberFormatter()
  formatter.maximumFractionDigits = 3
  if time > 1.0 {
    unit = "s"
  } else if time > 0.001 {
    unit = "ms"
    time *= 1_000
  } else if time > 0.000_001 {
    unit = "µs"
    time *= 1_000_000
  } else {
    unit = "ns"
    time *= 1_000_000_000
  }
  return formatter.string(from: NSNumber(value: time))! + unit
}
