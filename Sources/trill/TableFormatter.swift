///
/// TableFormatter.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import Foundation

struct Column {
  let title: String
  var rows = [String]()
  init(title: String) {
    self.title = title
  }
  var width: Int {
    var longest = self.title.count
    for row in self.rows where row.count > longest {
      longest = row.count
    }
    return longest
  }
}

class TableFormatter<StreamType: TextOutputStream> {
  let columns: [Column]
  
  init(columns:  [Column]) {
    self.columns = columns
  }

  func write(to stream: inout StreamType) {
    let widths = columns.map { $0.width }
    stream.write("┏")
    for (idx, width) in widths.enumerated() {
      stream.write(String(repeating: "━", count: width + 2))
      if idx == widths.endIndex - 1 {
        stream.write("┓\n")
      } else {
        stream.write("┳")
      }
    }
    for (column, width) in zip(columns, widths) {
      stream.write("┃ \(column.title.padded(to: width)) ")
    }
    stream.write("┃\n")
    for (index, width) in widths.enumerated() {
      let separator = index == widths.startIndex ? "┣" : "╋"
      stream.write(separator)
      stream.write(String(repeating: "━", count: width + 2))
    }
    stream.write("┫\n")
    for row in 0..<columns[0].rows.count {
      for (column, width) in zip(columns, widths) {
        stream.write("┃ \(column.rows[row].padded(to: width)) ")
      }
      stream.write("┃\n")
    }
    stream.write("┗")
    for (idx, width) in widths.enumerated() {
      stream.write(String(repeating: "━", count: width + 2))
      stream.write(idx == widths.endIndex - 1 ? "┛\n" : "┻")
    }
  }
}

extension String {
  func padded(to length: Int, with padding: String = " ") -> String {
    let padded = String(repeating: padding, count: length - self.count)
    return self + padded
  }
}
