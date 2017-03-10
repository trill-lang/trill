//
//  metadata_private.h
//  Trill
//
//  Created by Harlan Haskins on 11/29/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

#ifndef metadata_private_h
#define metadata_private_h

#include "metadata.h"
#include "trill.h"
#include <sstream>
#include <string>

namespace trill {

struct TypeMetadata;


/**
 Stores the metadata necessary for accessing a field of a structure at runtime.
 */
struct FieldMetadata {
  /**
   The name of the field
   */
  const char *name;

  /**
   A pointer to the metadata for the field's declared type
   */
  const TypeMetadata *typeMetadata;

  /**
   The offset from the object that this field lives, in bytes.
   */
  const size_t offset;
};

/**
 Stores the metadata necessary for erasing types at runtime.
 */
struct TypeMetadata {
  /**
   The declared name of the type.
   */
  const char *name;

  /**
   Metadata of all the stored fields of this type.
   */
  const FieldMetadata *fields;

  /**
   A pointer to this type's deinitializer function, or \c nullptr if the type
   doesn't have a deinitializer.
   */
  void (*deinit)(void *);

  /**
   Whether this type is a reference type (spelled as \c indirect \c type).
   */
  uint8_t isReferenceType;

  /**
   The size of this type, in bits.
   */
  uint64_t sizeInBits;

  /**
   The number of fields this type contains.
   */
  uint64_t fieldCount;

  /**
   How many levels of pointer this type represents.
   For example, \c *Void has pointerLevel 1, while \c ***Int8 has pointerLevel 3
   */
  uint64_t pointerLevel;

  /**
   Prints a debug representation of this metadata.
   */
  void debugPrint(std::string indent = "") const;

  /**
   Gets the metadata associated with a particular field.
   @note If the requested field is larger than the number of fields in this
         type, this function throws a fatal error.
   */
  const FieldMetadata *fieldMetadata(uint64_t index) const;
};

/**
 Stores the metadata associated with a protocol.
 */
struct ProtocolMetadata {
  /**
   The protocol's name.
   */
  const char *name;

  /**
   The formatted names of all methods in the protocol.
   */
  const char **methodNames;

  /**
   The number of methods in the protocol.
   */
  const size_t methodCount;
};

/**
 An \c AnyBox is a heap-allocated box that contains:
   - A pointer to the type metadata for an underlying value
   - A variably-sized payload
 */
struct AnyBox {
  /**
   The type metadata for the underlying value inside this box.
   */
  const TypeMetadata *typeMetadata;

  /**
   Creates an AnyBox that will eventually store a value that is the same type
   as the provided metadata.
   */
  static AnyBox *create(const TypeMetadata *metadata);

  /**
   Copies the value in an \c Any into a new \c Any object.
   */
  AnyBox *copy();

  /**
   Updates the value at a certain field index with the value inside the provided
   \c Any
   */
  void updateField(uint64_t fieldNum, AnyBox *newValue);

  /**
   Gets a pointer to the underlying value inside this \c Any.
   */
  void *value() {
    return reinterpret_cast<void *>(
             reinterpret_cast<uintptr_t>(this) + sizeof(AnyBox));
  }

  /**
   Gets a pointer to the start of a given field inside this \c Any.
   */
  void *fieldValuePtr(uint64_t fieldNum);

  /**
   Extracts the value at a given field in this \c Any into a new \c Any.
   */
  AnyBox *extractField(uint64_t fieldNum);

  /**
   Gets the \c FieldMetadata for a field in this \c Any
   */
  const FieldMetadata *fieldMetadata(uint64_t fieldNum) {
    return typeMetadata->fieldMetadata(fieldNum);
  }

  /**
   Tells whether this \c Any is wrapping a value that can be considered \c nil.
   */
  bool isNil();

  /**
   Prints a debug visualization of this \c AnyBox.
   */
  void debugPrint(std::string indent);
};

/**
 Raises a \c fatalError describing a cast failure
 */
void trill_reportCastError(const TypeMetadata *anyMetadata,
                           const TypeMetadata *typeMetadata);

struct GenericBox {
  const TypeMetadata *typeMetadata;
  const void **witnessTable;
};

}
#endif /* metadata_private_h */
