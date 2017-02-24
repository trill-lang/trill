/// File courtesy of Cocoa With Love,
/// https://www.cocoawithlove.com/blog/package-manager-fetch.html

import Foundation

/// Launch a process and run to completion, returning the standard out on success.
func launch(_ command: String, _ args: [String], directory: String? = nil) -> String? {
   let proc = Process()
   proc.launchPath = command
   proc.arguments = args
   _ = directory.map { proc.currentDirectoryPath = $0 }
   let pipe = Pipe()
   proc.standardOutput = pipe
   proc.launch()
   let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                       encoding: .utf8)!
   proc.waitUntilExit()
   return proc.terminationStatus != 0 ? nil : result
}

let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] ?? "."

// STEP 1: use `swift package fetch` to get all dependencies
print(launch("/usr/bin/swift", ["package", "fetch"], directory: srcRoot)!)

// Create a symlink only if it is not already present and pointing to the destination
let symlinksPath = "\(srcRoot)/.build/trill_symlinks"
func createSymlink(srcRoot: String, name: String, destination: String) throws {
   let location = "\(symlinksPath)/\(name)"
   let link = "../../\(destination)"
   if (try? FileManager.default.destinationOfSymbolicLink(atPath: location)) != link {
      _ = try? FileManager.default.removeItem(atPath: location)
      try FileManager.default.createSymbolicLink(atPath: location, withDestinationPath:
         link)
      print("Created symbolic link: \(location) -> \(link)")
   }
}

// Recursively parse the dependency graph JSON, creating symlinks in our own location
func createSymlinks(srcRoot: String, description: Dictionary<String, Any>, topLevelPath:
   String) throws {
   guard let dependencies = description["dependencies"] as? [Dictionary<String, Any>]
      else { return }
   for dependency in dependencies {
      let path = dependency["path"] as! String
      let relativePath = path.substring(from: path.range(of: topLevelPath)!.upperBound)
      let name = dependency["name"] as! String
      try createSymlink(srcRoot: srcRoot, name: name, destination: relativePath)
      try createSymlinks(srcRoot: srcRoot, description: dependency, topLevelPath:
         topLevelPath)
   }
}

// STEP 2: create symlinks from our stable locations to the fetched locations
let descriptionString = launch("/usr/bin/swift", ["package", "show-dependencies",
   "--format", "json"], directory: srcRoot)!
let descriptionData = descriptionString.data(using: .utf8)!
let description = try JSONSerialization.jsonObject(with: descriptionData, options: [])
   as! Dictionary<String, Any>
let topLevelPath = (description["path"] as! String) + "/"
do {
   try FileManager.default.createDirectory(atPath: symlinksPath,
      withIntermediateDirectories: true, attributes: nil)
   try createSymlinks(srcRoot: srcRoot, description: description, topLevelPath:
      topLevelPath)
   print("Complete.")
} catch {
   print(error)
}
