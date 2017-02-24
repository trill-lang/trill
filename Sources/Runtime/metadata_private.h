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

typedef struct FieldMetadata {
    const char *name;
    const void *type;
    size_t offset;
} FieldMetadata;

typedef struct TypeMetadata {
    const char *name;
    const void *fields;
    uint8_t isReferenceType;
    uint64_t sizeInBits;
    uint64_t fieldCount;
    uint64_t pointerLevel;
} TypeMetadata;

typedef struct ProtocolMetadata {
    const char *name;
    const char **methodNames;
    size_t methodCount;
} ProtocolMetadata;

typedef struct AnyBox {
    void *typeMetadata;
} AnyBox;

typedef struct GenericBox {
    void *typeMetadata;
    void *witnessTable;
} GenericBox;

#endif /* metadata_private_h */
