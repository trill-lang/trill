//
//  SourceFile.swift
//  Trill
//
//  Created by Harlan Haskins on 8/29/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

import Foundation

enum SourceFileType {
  case input(url: URL, contents: String)
  case file(URL)
  case stdin
  
  var basename: String {
    switch self {
    case .file(let url), .input(let url, _):
      return url.lastPathComponent
    case .stdin:
      return filename
    }
  }
  
  var filename: String {
    switch self {
    case .file(let url), .input(let url, _):
      return url.path
    case .stdin:
      return "<stdin>"
    }
  }
}

struct SourceFile {
  let path: SourceFileType
  let context: ASTContext
  let contents: String
  let lines: [String]
  
  init(path: SourceFileType, context: ASTContext) throws {
    let fetchContents: () throws -> String = {
      switch path {
      case .stdin:
        var str = ""
        while let line = readLine() {
          str += line
        }
        return str
      case .input(_, let contents):
        return contents
      case .file(let url):
        return try String(contentsOf: url)
      }
    }
    
    self.path = path
    self.context = context
    self.contents = try fetchContents()
    self.lines = self.contents.components(separatedBy: .newlines)
  }
  
  func parse() throws {
    let lexer = Lexer(filename: path.filename, input: contents)
    let tokens = try lexer.lex()
    let parser = Parser(tokens: tokens,
                        filename: path.filename,
                        context: context)
    try parser.parseTopLevel(into: context)
  }
}
