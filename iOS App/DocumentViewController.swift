//
//  DocumentViewController.swift
//  Trill
//

import UIKit

class DocumentViewController: UITableViewController {
  static let documentsDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory,
                                                                      .userDomainMask,
                                                                      true)[0]
  var documents = [SourceDocument]()
  let fileManager = FileManager.default
  let filePath = URL(fileURLWithPath: DocumentViewController.documentsDirectory)
  
  func document(title: String) -> SourceDocument {
    var url = filePath.appendingPathComponent(title)
    if url.pathExtension != "tr" {
      url.deletePathExtension()
      url.appendPathExtension("tr")
    }
    return SourceDocument(fileURL: url)
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    attempt(loadDocuments)
  }
  
  func attempt(_ f: () throws -> Void) {
    do {
      try f()
    } catch let error as NSError {
      show(error: error)
    } catch { print(error) }
  }
  
  func loadDocuments() throws {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(atPath: filePath.path) else { return }
    for item in enumerator {
      guard let url = item as? String else { continue }
      let path = filePath.appendingPathComponent(url)
      documents.append(SourceDocument(fileURL: path))
    }
  }

  @IBAction func newDocument(_ sender: UIBarButtonItem) {
    let controller = UIAlertController(title: "New Document", message: "Enter a title", preferredStyle: .alert)
    controller.addTextField {
      $0.placeholder = "file.tr"
    }
    controller.addAction(UIAlertAction(title: "Add", style: .default) { [weak controller] _ in
      guard let title = controller?.textFields?.first?.text else { return }
      var doc: SourceDocument? = nil
      self.attempt {
        doc = self.document(title: title)
      }
      guard let document = doc else { return }
      self.documents.append(document)
      self.reloadTable()
    })
    controller.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(controller, animated: true)
  }
  
  override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
    return true
  }
  
  func show(error: NSError) {
    let alert = UIAlertController(title: error.localizedDescription, message: error.localizedFailureReason ?? "", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Okay", style: .default))
    present(alert, animated: true)
  }
  
  override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
    switch editingStyle {
    case .delete:
      let doc = documents[indexPath.row]
      attempt {
        try fileManager.removeItem(at: doc.fileURL)
        documents.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .bottom)
      }
    default:
      break
    }
  }
  
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Document", for: indexPath)
    let document = documents[indexPath.row]
    cell.textLabel?.text = document.filename
    return cell
  }
  
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return documents.count
  }
  
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    let document = documents[indexPath.row]
    let completionHandler: (String) -> (Bool) -> Void = { message in
      { success in
        if success {
          self.performSegue(withIdentifier: "Show Document", sender: document)
        } else {
          self.showError("Failed to \(message) '\(document.filename)'")
        }
      }
    }
    let path = document.fileURL.path
    if fileManager.fileExists(atPath: path) {
      document.open(completionHandler: completionHandler("open"))
    } else {
      document.save(to: document.fileURL,
                    for: .forCreating,
                    completionHandler: completionHandler("create"))
    }
  }
  
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    guard let id = segue.identifier else { return }
    switch id {
    case "Show Document":
      let dest = segue.destination as! ViewController
      dest.document = sender as! SourceDocument
      dest.title = dest.document.filename
    default:
      fatalError("unknown segue identifier \(id)")
    }
  }
  
  func reloadTable() {
    self.tableView.reloadData()
  }
}

extension UIViewController {
  func showError(_ message: String) {
    let controller = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
    controller.addAction(UIAlertAction(title: "Okay", style: .default))
    present(controller, animated: true)
  }
}
