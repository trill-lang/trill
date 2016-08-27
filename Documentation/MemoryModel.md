# Trill Memory Model

Trill has two notions of types: `value` types and `indirect` types.
`indirect` types are declared with the `indirect type` keyword pair, and are always allocated on the heap. The difference between the two must be entirely transparent to the developer. Even though an indirect type is a pointer, it will not allow pointer arithmetic and will not need to be explicitly dereferenced.

## Functions
Function arguments always represent the canonical storage of the types that they take. If an argument is an `indirect` type, it will always come into the function as a pointer and be given a stack variable that is of `reference` storage.  

### Stack Variables
- All functions copy all arguments into stack variables that can be mutated.
  - Implicit `self` does not get a stack variable. Instead, it is treated
    as its own pointer, and is not allowed to be overwritten.

### Variable References
All `VarExprs` will be resolved to a variable binding that includes the following information:
- The LLVM reference to that variable
- The storage kind of the underlying variable

Variable bindings always yield pointers, and the underlying representation is determined by the storage kind.
For almost all references, this distinction does not matter. It only matters in the case of field lookups, where the pointer will need to be loaded first before performing arithmetic to access fields.

## Storage Kinds

The storage kind of a variable binding refers to the semantics of the underlying object.

#### `value`
The underlying value is a value type, and must be copied into functions that accept the value.

#### `reference`
The underlying value is always a pointer to an indirect type, and must be passed as a single pointer to functions that accept it. This pointer must be allocated on the heap.

All bindings of indirect types are considered 'reference' bindings, but values that have been captured in closures are also considered reference bindings.
