import Foundation

#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

public struct RuntimeLocation {
  public let includeDir: URL
  public let header: URL
  public let libraryDir: URL
  public let library: URL
  public let stdlib: URL
}

func findObject(forAddress address: UnsafeRawPointer) -> URL? {
  var info = dl_info()
  guard dladdr(address, &info) != 0 else { return nil }
  let path = String(cString: info.dli_fname)
  return URL(fileURLWithPath: path)
}

public enum RuntimeLocationError: Error {
  case couldNotLocateBinary
  case invalidInstallDir(URL)
  case invalidIncludeDir(URL)
  case invalidHeader(URL)
  case invalidLibDir(URL)
  case invalidLibrary(URL)
  case invalidStdLibDir(URL)
}

public enum RuntimeLocator {
  public static func findRuntime(forAddress address: UnsafeRawPointer) throws -> RuntimeLocation {
    guard let url = findObject(forAddress: address) else {
      throw RuntimeLocationError.couldNotLocateBinary
    }

    // Walk up the directory tree until we find `bin`.
    var installDir = url
    while installDir.lastPathComponent != "bin" {
        installDir = installDir.deletingLastPathComponent()
    }
    // Walk one directory above `bin`
    installDir = installDir.deletingLastPathComponent()

    guard FileManager.default.fileExists(atPath: installDir.path) else {
      throw RuntimeLocationError.invalidInstallDir(installDir)
    }
    let includeDir = installDir.appendingPathComponent("include")
    guard FileManager.default.fileExists(atPath: includeDir.path) else {
      throw RuntimeLocationError.invalidIncludeDir(includeDir)
    }
    let header = includeDir.appendingPathComponent("runtime")
                           .appendingPathComponent("trill.h")
    guard FileManager.default.fileExists(atPath: header.path) else {
      throw RuntimeLocationError.invalidHeader(header)
    }
    let libraryDir = installDir.appendingPathComponent("lib")
    guard FileManager.default.fileExists(atPath: libraryDir.path) else {
        throw RuntimeLocationError.invalidLibDir(libraryDir)
    }
    let library = libraryDir.appendingPathComponent("libtrillRuntime.a")
    guard FileManager.default.fileExists(atPath: library.path) else {
        throw RuntimeLocationError.invalidLibrary(library)
    }
    let stdlib = installDir.appendingPathComponent("stdlib")
    guard FileManager.default.fileExists(atPath: stdlib.path) else {
      throw RuntimeLocationError.invalidStdLibDir(stdlib)
    }
    return RuntimeLocation(includeDir: includeDir,
                           header: header,
                           libraryDir: libraryDir,
                           library: library,
                           stdlib: stdlib)
  }
}
