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
  func run(in context: ASTContext) {
    for name in ["print", "println"] {
      let anyRef = DataType.any.ref()
      let decl = FuncDecl(name: Identifier(name: name),
                          returnType: DataType.void.ref(),
                          args: [FuncArgumentAssignDecl(name: "", type: anyRef)],
                          modifiers: [.foreign])
      context.add(decl)
    }
    context.add(OperatorDecl(.plus, .any, .string, .string))
    context.add(OperatorDecl(.plus, .string, .any, .string))
  }
  var title: String {
    return "Populating JavaScript Decls"
  }
  let context: ASTContext
  init(context: ASTContext) { self.context = context }
}

let colorScheme = TextAttributes(font: Font(name: "Menlo", size: 14.0)!,
                                 boldFont: Font(name: "Menlo-Bold", size: 14.0)!,
                                 keyword: Color(red: 178.0/255.0, green: 24.0/255.0, blue: 137.0/255.0, alpha: 1.0),
                                 literal: Color(red: 120.0/255.0, green: 109.0/255.0, blue: 196.0/255.0, alpha: 1.0),
                                 normal: Color.white,
                                 comment: Color(red: 65.0/255.0, green: 182.0/255.0, blue: 69.0/255.0, alpha: 1.0),
                                 string: Color(red: 219.0/255.0, green: 44.0/255.0, blue: 56.0/255.0, alpha: 1.0),
                                 internalName: Color(red: 131.0/255.0, green: 192.0/255.0, blue: 87.0/255.0, alpha: 1.0),
                                 externalName: Color(red: 0.0/255.0, green: 160.0/255.0, blue: 190.0/255.0, alpha: 1.0))

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
    
    NotificationCenter.default.addObserver(self, selector: #selector(keyboardWasShown), name: .UIKeyboardDidShow, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillBeHidden), name: .UIKeyboardWillHide, object: nil)
    
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
    let filename = self.document.fileURL.path
    let sourceFile = try! SourceFile(path: .input(url: document.fileURL,
                                                  contents: document.sourceText),
                                     context: context)
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
    
    let block: (String) -> () = { str in
      DispatchQueue.main.async {
        dest.textView.text = dest.textView.text + str
      }
    }
    
    var stream = BlockStream(block: block)
    
    let consumer = AttributedStringConsumer(file: sourceFile, palette: colorScheme)
    diagnosticEngine.register(consumer)
    
    dest.consumer = consumer
    
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
      var runner = JavaScriptRunner(output: block, context: context)
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

