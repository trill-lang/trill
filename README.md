# Trill

[![CircleCI](https://circleci.com/gh/trill-lang/trill.svg?style=svg)](https://circleci.com/gh/trill-lang/trill)

Trill is a simple, type-safe, compiled programming language. Partially inspired by Swift, Trill has most simple language features one would expect (functions, structures, pointers) and some more high-level language features, like types with methods, garbage collected types, overloading,  tuples/multiple returns, and closures.

Trill is not to be confused with [Microsoft/Trill](https://github.com/Microsoft/trill), an engine for streaming data processing.

## Example

The following program finds the `n` th Fibonacci number:

```swift
func fib(_ n: Int) -> Int {
  var previous = 0
  var current = 1
  for var i = 0; i < n; i += 1 {
    let tmp = previous
    previous = current
    current = previous + tmp
  }
  return current
}

func main() {
  printf("%d\n", fib(10)) // prints 89
}
```
See the `examples` folder for more examples of Trill’s language features.


### LLVM

The main backend for Trill is LLVM. It uses LLVM and Clang’s C APIs to call into LLVM’s code generation and clang importing features from within Swift. It currently makes a best effort to import all supported declarations from the C standard library headers as `foreign` declarations, ready for use in Trill.

## Building and Using

Trill builds on macOS and Linux using CMake. We have a convenient build script that obviates the need for using CMake directly.
Once you've got LLVM and CMake installed, you'll need to generate pkgconfig files for LLVM and Clang -- we have a tool for this in the
`utils` directory. You'll only need to run it once.

```bash
utils/build --pkgconfig
```

To install the build script dependencies:

```bash
pip install pkgconfig
pip install git+https://github.com/kronenthaler/mod-pbxproj.git
```

Then, you should be able to run our build script. Just running the build script gets you a build of `trill` in the `.build/debug` folder.

```bash
usage: build [-h] [--swift SWIFT] [-r RELEASE] [-x] [-t]

optional arguments:
  -h, --help            show this help message and exit
  --swift SWIFT         Path to custom swift executable.
  -r RELEASE, --release RELEASE
                        Build the executable in the Release configuration
  -x, --xcodeproj       Build an Xcode project for the trill compiler.
  -t, --test            Run the trill test suite.
```

## Outstanding issues

- Closures are entirely unsupported in the LLVM backend. Closures are very much still in progress.
- There are no generics. I’m working on a protocol-based generics system that uses runtime boxes with type metadata.
- There are no `enum` s, like in Swift. `enum`s from C are currently imported as global constants
- There is a very limited standard library that exists alongside libc. You pretty much just get whatever you get with C, which includes all the pitfalls of manual pointers.
  - Ideally I have a standard library that vends common types like `Array` , `String` , `Dictionary` , `Set` , etc.
- The LLVM codegen is definitely not optimal, and certainly not correct.
- There is no garbage collection / automatic reference counting, so allocated trill types will leak like crazy.
- Many more yet-unknown issues and corner-cases.


## Should I use Trill in production?

**Absolutely not.** Trill is still in very early development, and is much more of a toy than anything serious. Everything is subject to change without any notice at all.

# Authors

Harlan Haskins ([@harlanhaskins](https://github.com/harlanhaskins))
Samuel Giddins ([@segiddins](https://github.com/segiddins))
Robert Widmann ([@codafi](https://github.com/codafi))

# License

Trill is released under the terms of the MIT license, a copy of which is included in this repository.
