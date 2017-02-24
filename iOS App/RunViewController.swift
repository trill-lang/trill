//
//  RunViewController.swift
//  Trill
//

import Foundation
import UIKit

class RunViewController: UIViewController {
  var input = ""
  @IBOutlet weak var textView: UITextView!
  
  weak var driver: Driver!
  var hasRun: Bool = false
  
  override func viewDidLoad() {
    super.viewDidLoad()
    textView.textContainerInset = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
  }
  
  override func viewWillAppear(_ animated: Bool) {
    if hasRun { return }
    hasRun = true
    DispatchQueue.global(qos: .default).async {
      self.driver.run(in: self.driver.context)
      var stream = AttributedStringStream(palette: colorScheme)
      self.driver.context.diag.register(
        StreamConsumer(context: self.driver.context,
                       stream: &stream))
      self.driver.context.diag.consumeDiagnostics()
      if self.driver.context.diag.hasErrors {
        DispatchQueue.main.async {
          self.textView.attributedText = stream.storage
        }
      }
    }
  }
  
  @IBAction func dismiss(_ sender: AnyObject) {
    self.dismiss(animated: true, completion: nil)
  }
  
  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }
  
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    if let timing = segue.destination as? TimingViewController {
      timing.timings = self.driver.timings
    }
  }
}
