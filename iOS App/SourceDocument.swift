//
//  SourceDocument.swift
//  Trill
//

import UIKit

enum DocumentError: Error {
  case invalidSource
  case invalidContents
}

class SourceDocument: UIDocument {
  override var fileType: String? {
    return "tr"
  }
  
  var sourceText = "" {
    didSet {
      undoManager.registerUndo(withTarget: self,
                               selector: #selector(getter: SourceDocument.sourceText),
                               object: oldValue)
    }
  }

  
  
  override func contents(forType typeName: String) throws -> Any {
    guard let data = sourceText.data(using: .utf8) else {
      throw DocumentError.invalidSource
    }
    return data
  }
  
  override func load(fromContents contents: Any, ofType typeName: String?) throws {
    guard
      let data = contents as? Data,
      let string = String(data: data, encoding: .utf8) else {
        throw DocumentError.invalidContents
    }
    sourceText = string
  }
  
  var filename: String {
    return fileURL.lastPathComponent
  }
}
