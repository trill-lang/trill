//
//  TimingViewController.swift
//  Trill
//

import UIKit

class TimingViewController: UITableViewController {
  
  var timings: [(String, Double)]!
  
  // MARK: - Table view data source
  
  override func numberOfSections(in tableView: UITableView) -> Int {
    return 1
  }
  
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return timings.count
  }
  
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "TimingCell", for: indexPath)
    cell.textLabel?.text = timings[indexPath.row].0
    cell.detailTextLabel?.text = format(time: timings[indexPath.row].1)
    return cell
  }
}
