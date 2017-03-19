//
//  metadata.h
//  Trill
//
//  Created by Harlan Haskins on 9/2/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

#ifndef metadata_h
#define metadata_h

#include "defines.h"
#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
#include "trill_assert.h"

namespace trill {
struct AnyBox;
extern "C" {
#endif


/**
 \c TRILL_ANY is a special type understood by the Trill compiler as the
 representation of an \c Any value.
 */
typedef struct TRILL_ANY {
  void * _Nonnull _any;
#ifdef __cplusplus
  inline AnyBox *_Nonnull any() {
    trill_assert(_any != nullptr && "passed a null value for Any");
    return reinterpret_cast<AnyBox *>(_any);
  }
  inline AnyBox *_Nonnull operator->() noexcept { return any(); }
  inline operator AnyBox*_Nonnull() { return any(); }
#endif
} TRILL_ANY;

/**
 Gets the formatted name of a given Trill type metadata object.

 @param typeMeta The type metadata.
 @return The name inside the type metadata. This is the same name
         that would appear in source code.
 */
const char *_Nonnull trill_getTypeName(const void *_Nonnull typeMeta);

/**
 Gets the pointer level of a given type metadata object.

 @param typeMeta The type metadata.
 @return The pointer level of this metadata.
 */
uint64_t trill_getTypePointerLevel(const void *_Nonnull typeMeta);

/**
 Gets the size of type metadata in bits. This takes into account the specific
 LLVM sizing properties of the underlying type.

 @param typeMeta The type metadata.
 @return The size of the type, in bits, suitable for pointer arithmetic.
 */
uint64_t trill_getTypeSizeInBits(const void *_Nonnull typeMeta);


/**
 Determines whether or not this metadata represents a reference type, i.e.
 a type spelled `indirect type` in Trill.

 @param typeMeta The type metadata.
 @return A non-zero value if the metadata is a reference type, and 0
         otherwise.
 */
uint8_t trill_isReferenceType(const void *_Nonnull typeMeta);


/**
 Gets the number of fields from type metadata. Primitive types will have no
 fields, while record types (structs and tuples) will have fields.

 @param typeMeta The type metadata.
 @return The number of fields in this type.
 */
uint64_t trill_getTypeFieldCount(const void *_Nonnull typeMeta);


/**
 Gets the \c FieldMetadata associated with the provided field index into the
 provided \c TypeMetadata.
 
 @note This function will abort if the field index is out of bounds. Ensure
       the field you pass in is in-bounds by calling \c trill_getTypeFieldCount and
       comparing the result.

 @param typeMeta The type metadata.
 @param field The index of the field you wish to inspect.
 */
const void *_Nonnull trill_getFieldMetadata(const void *_Nonnull typeMeta,
                                             uint64_t field);


/**
 Gets the name of the provided \c FieldMetadata.

 @param fieldMeta The field metadata.
 @return A constant C string with the field's name as declared in the source.
 */
const char *_Nonnull trill_getFieldName(const void *_Nonnull fieldMeta);


/**
 Gets the \c TypeMetadata of the provided \c FieldMetadata.

 @param fieldMeta The field metadata.
 @return The metadata of the field's type.
 */
const void *_Nonnull trill_getFieldType(const void *_Nonnull fieldMeta);


/**
 Gets the offset of a field (in bytes) from the start of a type.

 @param fieldMeta The field metadata.
 @return The offset in bytes of a field in a composite type.
 */
size_t trill_getFieldOffset(const void *_Nullable fieldMeta);


/**
 Creates an \c Any representation with the provided type metadata.
 An \c Any in Trill is a variable-sized, heap-allocated box that holds:

 - Type metadata for the underlying object, and
 - A payload that is the size specified in the metadata.
 
 @note This value is uninitialized, and the payload will be empty. You
       must initialize the payload with a value by casting and storing
       the value into the pointer returned by \c trill_getAnyValuePtr.

 @param typeMeta The type metadata for the underlying value.
 @return A new \c Any box that is uninitialized.
 */
TRILL_ANY trill_allocateAny(const void *_Nonnull typeMeta);


/**
 Copies an \c Any if the underlying value's semantics mean it should be copied.
 If the underlying value is a reference type, then the provided \c Any is just
 returned unmodified.

 @param any The \c Any you wish to copy.
 @return A new \c Any containing the contents of the old \c Any, if the
         underlying value is has value semantics. Otherwise, the provided
         \c Any.
 */
TRILL_ANY trill_copyAny(TRILL_ANY any);

/**
 Gets a pointer to a field inside the \c Any structure. Specifically, this
 is a pointer inside the payload that will, when stored, update the value
 inside the payload.

 @note This function will abort if the field index is out of bounds. Ensure
       the field you pass in is in-bounds by calling \c trill_getTypeFieldCount and
       comparing the result.

 @param any The \c Any you're inspecting.
 @param fieldNum The field index you're accessing.
 @return A pointer into the payload that points to the value of the
         provided field.
 */
void *_Nonnull trill_getAnyFieldValuePtr(TRILL_ANY any, uint64_t fieldNum);


/**
 Extracts a field from this payload and wraps it in its own \c Any container.
 

 @note This function will abort if the field index is out of bounds. Ensure
       the field you pass in is in-bounds by calling \c trill_getTypeFieldCount and
       comparing the result.

 @param any The composite type from which you're extracting a field.
 @param fieldNum The field index.
 @return A new \c Any with a payload that comes from the field's contents.
 */
TRILL_ANY trill_extractAnyField(TRILL_ANY any, uint64_t fieldNum);


/**
 Updates a field with the value inside the provided \c Any.

 @param any The \c Any for the composite type whose field you are replacing.
 @param fieldNum The index of the field to be replaced.
 @param newany The \c Any for the underlying field.
 */
void trill_updateAny(TRILL_ANY any, uint64_t fieldNum, TRILL_ANY newany);


/**
 Gets a pointer to the payload that can be cast and stored.
 
 @note This will perform no casting or type checking for you, and should only
       be used opaquely or if you are absolutely sure of the underlying type.

 @param anyValue The \c Any whose payload you want to use.
 @return A pointer to the payload that can be cast and then loaded from.
 */
void *_Nonnull trill_getAnyValuePtr(TRILL_ANY anyValue);


/**
 Gets the \c TypeMetadata underlying an \c Any box.

 @param anyValue The \c Any box.
 @return The underlying type metadata.
 */
const void *_Nonnull trill_getAnyTypeMetadata(TRILL_ANY anyValue);


/**
 Checks if the underlying metadata of an \c Any matches the metadata provided.

 @param anyValue The \c Any whose type you're checking.
 @param typeMetadata_ The \c TypeMetadata you're checking.
 @return A non-zero value if the type metadata underlying the \c Any box
         is pointer-equal to the provided \c TypeMetadata. Otherwise, 0.
 */
uint8_t trill_checkTypes(TRILL_ANY anyValue,
                         const void *_Nonnull typeMetadata_);


/**
 Checks if the underlying metadata of an \c Any box matches the provided
 metadata, and returns a pointer to the underlying payload if they do.
 
 @note If the \c Any value does not match the provided metadata, then this
       function causes a fatal error with a descriptive message and then
       aborts with a stack trace.

 @param anyValue The \c Any you're trying to cast.
 @param typeMetadata_ The \c TypeMetadata you're checking the \c Any against.
 @return A pointer to the payload that is safe to cast based on the type
         metadata.
 */
const void *_Nonnull trill_checkedCast(TRILL_ANY anyValue,
                                       const void *_Nonnull typeMetadata_);


/**
 Determines if the value underlying an \c Any is \c nil. If the type underlying
 the \c Any is not a pointer or indirect type, then this will always return
 \c false. However, if the underlying value is a pointer or indirect type, then
 this function will read the payload and see if the value in the payload is
 \c NULL.

 @param any The \c Any you're checking.
 @return A non-zero value if the underlying payload should be interpreted as a
         \c nil value.
 */
uint8_t trill_anyIsNil(TRILL_ANY any);


#ifdef __cplusplus
}
}
#endif

#endif /* metadata_h */
