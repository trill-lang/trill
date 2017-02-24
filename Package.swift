import PackageDescription

let package = Package(name: "trill",
  dependencies: [
    .Package(url: "https://github.com/trill-lang/cllvm.git", majorVersion: 0),
    .Package(url: "https://github.com/trill-lang/LLVMSwift.git", majorVersion: 0),
  ]
)
