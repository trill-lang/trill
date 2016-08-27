# Trill

Trill is a simple, type-safe, compiled programming language. Partially inspired by Swift, Trill has most simple language features one would expect (functions, structures, pointers) and some more high-level language features, like types with methods, garbage collected types, overloading,  tuples/multiple returns, and closures.

## Why did you make this?

Really, it's an exercise to learn compiler design, code generation to LLVM,
and how to make a language that's actually fun to write.

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


## Backends

Trill has two backends, one for LLVM IR, and one for JavaScript. The JavaScript backend does not accurately represent the semantics of Trill, and really only exists to provide very simple interpreting of Trill programs inside the iOS app.

### LLVM IR
The main backend for Trill is LLVM. It uses LLVM and Clang’s C APIs to call into LLVM’s code generation and clang importing features from within Swift. It currently makes a best effort to import all supported declarations from the C standard library headers as `foreign` declarations, ready for use in Trill.

### iOS App
This repo also contains an iOS app that will perform semantic syntax highlighting, error reporting, and timing information for Trill. It will also convert Trill to JavaScript and execute it live on the device.

When using Trill in a JavaScript context, you can forward-declare certain types and methods that exist within the JavaScript standard library and use them from Trill as you would from JavaScript. Trill will ensure that your types are matched up, then emit the equivalent dynamic JavaScript.

```swift
foreign type Date {
  foreign func unixTimestamp() -> Int
  func getTime() -> Int {
    return self.unixTimestamp() / 1_000
  }
}
    
func main() {
  println(Date().getTime())
}
```

## Building and Using

Trill currently is only supported on macOS.

To build and create Trill programs, you need to open the Xcode project and
build the `trill` scheme.
Then, you'll need to symlink the trill runtime and headers:

```bash
ln -s /path/to/Trill_DerivedData/libtrillRuntime.a /usr/local/lib/libtrillRuntime.a
mkdir /usr/local/include/trill
ln -s /path/to/Trill/Sources/Runtime/*.h /usr/local/include/trill/.
```

## Outstanding issues

- The LLVM JIT doesn't currently work when linking the trill runtime. I'm trying to fix this with little luck.
  - You'll need to compile trill programs using the Makefile in the `examples/` directory.
- Closures are entirely unsupported in the LLVM backend. Closures are very much still in progress.
- There are no generics. I’m still speccing out the generics system, but I’m thinking it’ll be fairly similar to C++’s [Concepts](https://en.wikipedia.org/wiki/Concepts_(C%2B%2B)) proposal — everything verified before being explicitly instantiated.
- There are no `enum` s, like in Swift. `enum`s from C are currently imported as global constants
- There is no standard library that exists alongside libc. You pretty much just get whatever you get with C, which includes all the pitfalls of manual pointers
  - Ideally I have a standard library that vends common types like `Array` , `String` , `Dictionary` , `Set` , etc.
- The LLVM codegen is definitely not optimal, and certainly not correct.
- Many more issues


## Should I use Trill in production?

**Absolutely not.** Trill is still in very early development, and is much more of a toy than anything serious. Everything is subject to change without any notice at all.

# Author

Harlan Haskins ([@harlanhaskins](https://github.com/harlanhaskins))


# License

Trill is released under the terms of the MIT license, a copy of which is included in this repository.

