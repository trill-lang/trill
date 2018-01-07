// swift-tools-version:4.0
import PackageDescription

let package = Package(name: "trill",
  products: [
    .executable(name: "trill", targets: ["trill"]),
    .executable(name: "trill-demangle", targets: ["trill-demangle"]),
    .library(name: "trillRuntime", type: .static, targets: ["trillRuntime"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.1.0"),
    .package(url: "https://github.com/llvm-swift/ClangSwift.git", .branch("master")),
    .package(url: "https://github.com/llvm-swift/cllvm.git", from: "0.0.3"),
    .package(url: "https://github.com/llvm-swift/Lite.git", from: "0.0.3"),
    .package(url: "https://github.com/llvm-swift/LLVMSwift.git", .branch("master")),
    .package(url: "https://github.com/llvm-swift/Symbolic.git", from: "0.0.1"),
  ],
  targets: [
    .target(name: "AST", dependencies: [
      "Source", "Diagnostics"
    ]),
    .target(name: "ClangImporter", dependencies: [
      "AST", "Clang", "LLVMWrappers", "Parse", "Runtime"
    ]),
    .target(name: "Driver", dependencies: ["AST"]),
    .target(name: "Diagnostics", dependencies: ["Source"]),
    .target(name: "IRGen", dependencies: [
      "AST", "LLVM", "LLVMWrappers", "Options", "Runtime"
    ]),
    .target(name: "LLVMWrappers"),
    .target(name: "Options", dependencies: ["Utility"]),
    .target(name: "Parse", dependencies: ["AST"]),
    .target(name: "Sema", dependencies: ["AST"]),
    .target(name: "Source"),
    .target(name: "Runtime"),
    .target(name: "trillRuntime", path: "runtime"),
    .target(name: "trill-demangle", dependencies: ["trillRuntime"], path: "tools/trill-demangle"),
    .target(name: "trill", dependencies: [
      "AST", "ClangImporter", "Diagnostics", "Driver",
      "IRGen", "LLVMWrappers", "Options", "Parse", "Sema", "Source",
      "trillRuntime"
    ]),
    .target(name: "lite", dependencies: [
      "Diagnostics", "LiteSupport", "Symbolic", "Utility"
    ]),
  ])
