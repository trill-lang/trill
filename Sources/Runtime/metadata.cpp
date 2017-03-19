//
//  metadata.cpp
//  Trill
//
//  Created by Harlan Haskins on 9/2/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

#include "metadata_private.h"
#include "runtime.h"
#include <iostream>
#include <string>

namespace trill {

const char *trill_getTypeName(const void *typeMeta) {
  trill_assert(typeMeta != nullptr);
  return reinterpret_cast<const TypeMetadata *>(typeMeta)->name;
}

uint64_t trill_getTypeSizeInBits(const void *typeMeta) {
  trill_assert(typeMeta != nullptr);
  return reinterpret_cast<const TypeMetadata *>(typeMeta)->sizeInBits;
}

uint64_t trill_getTypePointerLevel(const void *_Nonnull typeMeta) {
  trill_assert(typeMeta != nullptr);
  return reinterpret_cast<const TypeMetadata *>(typeMeta)->pointerLevel;
}

uint8_t trill_isReferenceType(const void *typeMeta) {
  trill_assert(typeMeta != nullptr);
  return reinterpret_cast<const TypeMetadata *>(typeMeta)->isReferenceType;
}

uint64_t trill_getTypeFieldCount(const void *typeMeta) {
  trill_assert(typeMeta != nullptr);
  return reinterpret_cast<const TypeMetadata *>(typeMeta)->fieldCount;
}

const void *_Nullable trill_getFieldMetadata(const void *typeMeta, uint64_t field) {
  trill_assert(typeMeta != nullptr);
  auto real = reinterpret_cast<const TypeMetadata *>(typeMeta);
  return real->fieldMetadata(field);
}

const char *_Nonnull trill_getFieldName(const void *_Nonnull fieldMeta) {
  trill_assert(fieldMeta != nullptr);
  return reinterpret_cast<const FieldMetadata *>(fieldMeta)->name;
}

const void *_Nonnull trill_getFieldType(const void *_Nonnull fieldMeta) {
  trill_assert(fieldMeta != nullptr);
  return reinterpret_cast<const FieldMetadata *>(fieldMeta)->typeMetadata;
}

size_t trill_getFieldOffset(const void *_Nullable fieldMeta) {
  trill_assert(fieldMeta != nullptr);
  return reinterpret_cast<const FieldMetadata *>(fieldMeta)->offset;
}

TRILL_ANY trill_allocateAny(const void *typeMeta) {
  trill_assert(typeMeta != nullptr);
  auto typeMetadata = reinterpret_cast<const TypeMetadata *>(typeMeta);
  return { AnyBox::create(typeMetadata) };
}

TRILL_ANY trill_copyAny(TRILL_ANY any) {
  return { any->copy() };
}

void *trill_getAnyFieldValuePtr(TRILL_ANY any, uint64_t fieldNum) {
  return any->fieldValuePtr(fieldNum);
}

TRILL_ANY trill_extractAnyField(TRILL_ANY any, uint64_t fieldNum) {
  return { any->extractField(fieldNum) };
}

void trill_updateAny(TRILL_ANY any, uint64_t fieldNum, TRILL_ANY newAny) {
  any->updateField(fieldNum, newAny);
}

void *_Nonnull trill_getAnyValuePtr(TRILL_ANY any) {
  return any->value();
}

const void *_Nonnull trill_getAnyTypeMetadata(TRILL_ANY any) {
  return any->typeMetadata;
}
  
void trill_dumpProtocol(ProtocolMetadata *proto) {
    trill_assert(proto != nullptr);
    std::cout << proto->name << " {" << std::endl;
    for (size_t i = 0; i < proto->methodCount; ++i) {
        std::cout << "  " << proto->methodNames[i] << std::endl;
    }
    std::cout << "}" << std::endl;
}
  
uint8_t trill_checkTypes(TRILL_ANY any, const void *typeMetadata_) {
  auto typeMetadata = reinterpret_cast<const TypeMetadata *>(typeMetadata_);
  return any->typeMetadata == typeMetadata;
}

const void *trill_checkedCast(TRILL_ANY any, const void *typeMetadata_) {
  auto anyMetadata = any->typeMetadata;
  auto typeMetadata = reinterpret_cast<const TypeMetadata *>(typeMetadata_);
  if (!trill_checkTypes(any, typeMetadata_)) {
    trill_reportCastError(anyMetadata, typeMetadata);
  }
  return any->value();
}

uint8_t trill_anyIsNil(TRILL_ANY any) {
  return any->isNil() ? 1 : 0;
}

}
