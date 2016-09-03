//
//  metadata.cpp
//  Trill
//
//  Created by Harlan Haskins on 9/2/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

#include "metadata.h"
#include "runtime.h"

namespace trill {

typedef struct FieldMetadata {
  const char *name;
  const void *type;
} FieldMetadata;

typedef struct TypeMetadata {
  const char *name;
  const void *fields;
  uint64_t sizeInBits;
  uint64_t fieldCount;
  uint64_t pointerLevel;
} TypeMetadata;

const char *trill_getTypeName(const void *typeMeta) {
  if (!typeMeta) return "<null>";
  auto real = (TypeMetadata *)typeMeta;
  return real->name;
}

uint64_t trill_getTypeSizeInBits(const void *typeMeta) {
  if (!typeMeta) return 0;
  auto real = (TypeMetadata *)typeMeta;
  return real->sizeInBits;
}

uint64_t trill_getNumFields(const void *typeMeta) {
  if (!typeMeta) {
    return 0;
  }
  auto real = (TypeMetadata *)typeMeta;
  return real->fieldCount;
}

const void *_Nullable trill_getFieldMetadata(const void *typeMeta, uint64_t field) {
  if (!typeMeta) {
    return nullptr;
  }
  auto real = (TypeMetadata *)typeMeta;
  if (real->fieldCount <= field) {
    trill_fatalError("field index out of bounds");
  }
  return &((FieldMetadata *)real->fields)[field];
}

const char *_Nullable trill_getFieldName(const void *_Nullable fieldMeta) {
  if (!fieldMeta) return nullptr;
  auto real = (FieldMetadata *)fieldMeta;
  return real->name;
}

const void *_Nullable trill_getFieldType(const void *_Nullable fieldMeta) {
  if (!fieldMeta) return nullptr;
  auto real = (FieldMetadata *)fieldMeta;
  return real->type;
}

}
