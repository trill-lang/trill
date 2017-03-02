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

struct TypeMetadata;

struct FieldMetadata {
    const char *name;
    const TypeMetadata *typeMetadata;
    const size_t offset;
};

struct TypeMetadata {
    const char *name;
    const FieldMetadata *fields;
    uint8_t isReferenceType;
    uint64_t sizeInBits;
    uint64_t fieldCount;
    uint64_t pointerLevel;
};

struct ProtocolMetadata {
    const char *name;
    const char **methodNames;
    const size_t methodCount;
};

struct AnyBox {
  const TypeMetadata *typeMetadata;
};

struct GenericBox {
    const TypeMetadata *typeMetadata;
    const void **witnessTable;
};

#endif /* metadata_private_h */
