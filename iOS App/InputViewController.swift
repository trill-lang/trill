//
//  ViewController.swift
//  Trill iOS
//

import UIKit

class BlockStream: TextOutputStream {
  var block: (String) -> ()
  init(block: @escaping (String) -> ()) {
    self.block = block
  }
  
  func write(_ string: String) {
    self.block(string)
  }
}

enum Action {
  case showAST, showJS, run
}

struct PopulateJSDecls: Pass {
  static func stdlibContext() -> StdLibASTContext {
    let diag = DiagnosticEngine()
    let trFiles = Bundle.main.paths(forResourcesOfType: "tr", inDirectory: nil)
    let context = StdLibASTContext(diagnosticEngine: diag)
    context.allowForeignOverloads = true
    for file in trFiles {
      do {
        let contents = try String(contentsOfFile: file)
        var lexer = Lexer(filename: file, input: contents)
        let toks = try lexer.lex()
        let parser = Parser(tokens: toks, filename: file, context: context)
        try parser.parseTopLevel(into: context)
      } catch {
        diag.error(error)
      }
    }
    return context
  }

  func run(in context: ASTContext) {
    let stdlib = PopulateJSDecls.stdlibContext()
    context.merge(context: stdlib)
    context.stdlib = stdlib
  }

  var title: String {
    return "Populating JavaScript Decls"
  }

  let context: ASTContext
  init(context: ASTContext) { self.context = context }
}

let colorScheme = TextAttributes(font: Font(name: "Menlo", size: 14.0)!,
                                 boldFont: Font(name: "Menlo-Bold", size: 14.0)!,
                                 keyword: TextStyle(bold: false, color: #colorLiteral(red: 0.8717985749, green: 0.1707525551, blue: 0.6193057895, alpha: 1)),
                                 literal: TextStyle(bold: false, color: #colorLiteral(red: 0.4705882353, green: 0.4274509804, blue: 0.768627451, alpha: 1)),
                                 normal: TextStyle(bold: false, color: #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)),
                                 comment: TextStyle(bold: false, color: #colorLiteral(red: 0.3207378387, green: 0.7909296155, blue: 0.3154229522, alpha: 1)),
                                 string: TextStyle(bold: false, color: #colorLiteral(red: 0.8840605617, green: 0.2192999125, blue: 0.2169525027, alpha: 1)),
                                 internalName: TextStyle(bold: true, color: #colorLiteral(red: 0.09483132511, green: 0.7192143798, blue: 0.7049412131, alpha: 1)),
                                 externalName: TextStyle(bold: false, color: #colorLiteral(red: 0.1427748409, green: 0.5633252992, blue: 0.55766396, alpha: 1)))


//let colorScheme = TextAttributes(font: Font(name: "Menlo", size: 14.0)!,
//                                 boldFont: Font(name: "Menlo-Bold", size: 14.0)!,
//                                 keyword: #colorLiteral(red: 0.6980392157, green: 0.09411764706, blue: 0.537254902, alpha: 1),
//                                 literal: #colorLiteral(red: 0.4705882353, green: 0.4274509804, blue: 0.768627451, alpha: 1),
//                                 normal: #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
//                                 comment: #colorLiteral(red: 0.2549019608, green: 0.7137254902, blue: 0.2705882353, alpha: 1),
//                                 string: #colorLiteral(red: 0.8588235294, green: 0.1725490196, blue: 0.2196078431, alpha: 1),
//                                 internalName: #colorLiteral(red: 0.5137254902, green: 0.7529411765, blue: 0.3411764706, alpha: 1),
//                                 externalName: #colorLiteral(red: 0, green: 0.6274509804, blue: 0.7450980392, alpha: 1))

class ViewController: UIViewController, UITextViewDelegate {
  var diagnosticEngine = DiagnosticEngine()
  var driver: Driver!
  var storage: LexerTextStorage!
  @IBOutlet var textView: UITextView!
  var document: SourceDocument!
  var context: ASTContext!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    textView.delegate = self
    textView.font = colorScheme.font
    textView.textContainerInset = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
    
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(keyboardWasShown),
                                           name: .UIKeyboardDidShow,
                                           object: nil)
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(keyboardWillBeHidden),
                                           name: .UIKeyboardWillHide,
                                           object: nil)
    
    storage = LexerTextStorage(attributes: colorScheme,
                               filename: document.fileURL.path)
    textView.text = document.sourceText
    storage.addLayoutManager(textView.layoutManager)
    storage.append(NSAttributedString(string: document.sourceText))
  }
  
  
  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  @IBAction func run() {
    execute(action: .run)
  }
  
  @IBAction func showJS() {
    execute(action: .showJS)
  }
  
  @IBAction func showAST() {
    execute(action: .showAST)
  }
  
  func keyboardWasShown(aNotification:NSNotification) {
    let info = aNotification.userInfo
    let infoNSValue = info![UIKeyboardFrameBeginUserInfoKey] as! NSValue
    let kbSize = infoNSValue.cgRectValue.size
    let inset = UIEdgeInsets(top: 0, left: 0, bottom: kbSize.height, right: 0)
    textView.contentInset = inset
    textView.scrollIndicatorInsets = inset
  }
  
  func keyboardWillBeHidden(aNotification:NSNotification) {
    textView.contentInset = .zero
    textView.scrollIndicatorInsets = .zero
  }
  
  func execute(action: Action) {
    self.performSegue(withIdentifier: "Show Results", sender: action)
  }
  
  func textViewDidChange(_ textView: UITextView) {
    document.sourceText = storage.string
  }
  
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    guard
      let nav = segue.destination as? UINavigationController,
      let sender = sender as? Action,
      let dest = nav.topViewController as? RunViewController else { return }
    
    diagnosticEngine = DiagnosticEngine()
    context = ASTContext(diagnosticEngine: diagnosticEngine)
    context.allowForeignOverloads = true
    let filename = self.document.fileURL.path
    let sourceFile = try! SourceFile(path: .input(url: document.fileURL,
                                                  contents: document.sourceText),
                                     context: context)
    context.add(sourceFile)
    driver = Driver(context: context)
    let text = storage.string
    driver.add("Lexer and Parser") { context in
      var lexer = Lexer(filename: filename, input: text)
      do {
        let tokens = try lexer.lex()
        let parser = Parser(tokens: tokens,
                            filename: filename,
                            context: self.context)
        try parser.parseTopLevel(into: context)
      } catch let error as Diagnostic {
        self.diagnosticEngine.add(error)
      } catch {
        self.diagnosticEngine.error("\(error)")
      }
    }
    driver.add(pass: PopulateJSDecls.self)
    driver.add(pass: Sema.self)
    driver.add(pass: TypeChecker.self)
    
    let appendText: (String) -> () = { str in
      DispatchQueue.main.async {
        dest.textView.text = dest.textView.text + str
      }
    }
    
    var stream = BlockStream(block: appendText)
    
    switch sender {
    case .showJS:
      driver.add("JavaScript Generation") { context in
        return JavaScriptGen(stream: &stream, context: context).run(in: context)
      }
    case .showAST:
      driver.add("Dumping the AST") { context in
        var attrStream = AttributedStringStream(palette: colorScheme)
        ASTDumper(stream: &attrStream,
                  context: context,
                  files: [sourceFile]).run(in: context)
        DispatchQueue.main.async {
            dest.textView.attributedText = attrStream.storage
        }
      }
    case .run:
      var runner = JavaScriptRunner(output: appendText, context: context)
      runner.objCReceiver = self.textView
      driver.add("Generating JavaScript") { context in
        JavaScriptGen(stream: &runner, context: context).run(in: context)
      }
      driver.add("Running JavaScript") { context in
        runner.run()
      }
    }
    dest.driver = driver
  }
  
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    document.close { success in
      if !success {
        self.showError("Failed to save \(self.document.filename)")
      }
    }
  }
  
}

