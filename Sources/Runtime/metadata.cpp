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

#define TYPE_PUN(ptr, ty) *((ty *)(ptr))

namespace trill {

const char *trill_getTypeName(const void *typeMeta) {
  trill_assert(typeMeta != nullptr);
  auto real = (TypeMetadata *)typeMeta;
  return real->name;
}

uint64_t trill_getTypeSizeInBits(const void *typeMeta) {
  trill_assert(typeMeta != nullptr);
  auto real = (TypeMetadata *)typeMeta;
  return real->sizeInBits;
}

uint8_t trill_isReferenceType(const void *typeMeta) {
  trill_assert(typeMeta != nullptr);
  auto real = (TypeMetadata *)typeMeta;
  return real->isReferenceType;
}

uint64_t trill_getNumFields(const void *typeMeta) {
  trill_assert(typeMeta != nullptr);
  auto real = (TypeMetadata *)typeMeta;
  return real->fieldCount;
}

const void *_Nullable trill_getFieldMetadata(const void *typeMeta, uint64_t field) {
  trill_assert(typeMeta != nullptr);
  auto real = (TypeMetadata *)typeMeta;
  if (real->fieldCount <= field) {
    trill_fatalError("field index out of bounds");
  }
  return &((FieldMetadata *)real->fields)[field];
}

const char *_Nullable trill_getFieldName(const void *_Nullable fieldMeta) {
  trill_assert(fieldMeta != nullptr);
  auto real = (FieldMetadata *)fieldMeta;
  return real->name;
}

const void *_Nullable trill_getFieldType(const void *_Nullable fieldMeta) {
  trill_assert(fieldMeta != nullptr);
  auto real = (FieldMetadata *)fieldMeta;
  return real->type;
}

size_t trill_getFieldOffset(const void *_Nullable fieldMeta) {
  trill_assert(fieldMeta != nullptr);
  return ((FieldMetadata *)fieldMeta)->offset;
}

TRILL_ANY trill_allocateAny(void *typeMetadata_) {
  trill_assert(typeMetadata_ != nullptr);
  TypeMetadata *typeMetadata = (TypeMetadata *)typeMetadata_;
  size_t fullSize = sizeof(AnyBox) + typeMetadata->sizeInBits;
  AnyBox *ptr = (AnyBox *)trill_alloc(fullSize);
  ptr->typeMetadata = typeMetadata;
  return {ptr};
}

TRILL_ANY trill_copyAny(TRILL_ANY any) {
  AnyBox *ptr = (AnyBox *)any._any;
  trill_assert(ptr != nullptr);
  auto typeMetadata = reinterpret_cast<TypeMetadata*>(ptr->typeMetadata);
  if (typeMetadata->isReferenceType) { return any; }
  uint64_t size = typeMetadata->sizeInBits;
  AnyBox *header = (AnyBox *)trill_alloc(sizeof(AnyBox) + size);
  memcpy(header, ptr, sizeof(AnyBox) + size);
  return {header};
}

static FieldMetadata *trill_getAnyFieldMetadata(AnyBox *any, uint64_t fieldNum) {
  auto meta = (TypeMetadata *)any->typeMetadata;
  trill_assert(meta != nullptr);
  trill_assert(fieldNum < meta->fieldCount);
  auto fieldMeta = (FieldMetadata *)trill_getFieldMetadata(meta, fieldNum);
  trill_assert(fieldMeta != nullptr);
  return fieldMeta;
}

void trill_reportCastError(TypeMetadata *anyMetadata, TypeMetadata *typeMetadata) {
  std::string failureDesc = "checked cast failed: cannot convert ";
  failureDesc += trill_getTypeName(anyMetadata);
  failureDesc += " to ";
  failureDesc += trill_getTypeName(typeMetadata);
  trill_fatalError(failureDesc.c_str());
}

void *trill_getAnyFieldValuePtr(TRILL_ANY any_, uint64_t fieldNum) {
  auto any = (AnyBox *)any_._any;
  trill_assert(any != nullptr);
  auto origPtr = trill_getAnyValuePtr(any_);
  trill_assert(origPtr != nullptr);
  auto typeMeta = reinterpret_cast<TypeMetadata*>(trill_getAnyTypeMetadata(any_));
  auto fieldMeta = trill_getAnyFieldMetadata(any, fieldNum);
  if (typeMeta->isReferenceType) {
    origPtr = *reinterpret_cast<void**>(origPtr);
    trill_assert(origPtr != nullptr);
  }
  return (void *)((intptr_t)origPtr + fieldMeta->offset);
}

TRILL_ANY trill_extractAnyField(TRILL_ANY any_, uint64_t fieldNum) {
  auto any = (AnyBox *)any_._any;
  trill_assert(any != nullptr);
  auto fieldMeta = trill_getAnyFieldMetadata(any, fieldNum);
  auto fieldTypeMeta = (TypeMetadata *)fieldMeta->type;
  auto newAny = trill_allocateAny(fieldTypeMeta);
  auto fieldPtr = trill_getAnyValuePtr(newAny);
  auto anyFieldValuePointer = trill_getAnyFieldValuePtr(any_, fieldNum);
  memcpy(fieldPtr, anyFieldValuePointer, fieldTypeMeta->sizeInBits);
  return newAny;
}

void trill_updateAny(TRILL_ANY any_, uint64_t fieldNum, TRILL_ANY newAny_) {
  auto any = (AnyBox *)any_._any;
  auto newAny = (AnyBox *)newAny_._any;
  trill_assert(any != nullptr);
  trill_assert(newAny != nullptr);
  auto newType = (TypeMetadata *)newAny->typeMetadata;
  trill_assert(newType);
  auto fieldMeta = trill_getAnyFieldMetadata(any, fieldNum);
  if (fieldMeta->type != newType) {
    trill_reportCastError((TypeMetadata *)fieldMeta->type, (TypeMetadata *)newAny->typeMetadata);
  }
  auto fieldPtr = trill_getAnyFieldValuePtr({any}, fieldNum);
  auto newPtr = trill_getAnyValuePtr({newAny});
  memcpy(fieldPtr, newPtr, newType->sizeInBits);
}

void *trill_getAnyValuePtr(TRILL_ANY anyValue) {
  return (void *)((intptr_t)anyValue._any + sizeof(AnyBox));
}

void *_Nonnull trill_getAnyTypeMetadata(TRILL_ANY anyValue) {
  trill_assert(anyValue._any != nullptr);
  return ((AnyBox *)anyValue._any)->typeMetadata;
}

void trill_debugPrintFields(const void *fields, uint64_t count, std::string indent = "") {
  for (size_t i = 0; i < count; i++) {
    FieldMetadata field = ((FieldMetadata *)fields)[i];
    std::cout << indent << "  " << field.name << ": "
              << trill_getTypeName(field.type) << std::endl;
  }
}

void trill_debugPrintTypeMetadata(const void *ptr_, std::string indent = "") {
  if (!ptr_) {
    std::cout << "<null>" << std::endl;
    return;
  }
  TypeMetadata *ptr = (TypeMetadata *)ptr_;
  std::string typeName = ptr->name;
  std::cout << "TypeMetadata {" << std::endl;
  std::cout << indent << "  const char *name = \"" << typeName << "\"" << std::endl;
  std::cout << indent << "  const void *fields = [" << std::endl;
  trill_debugPrintFields(ptr->fields, ptr->fieldCount, indent + "  ");
  std::cout << indent << "  ]" << std::endl;
  std::cout << indent << "  bool isReferenceType = " << !!ptr->isReferenceType << std::endl;
  std::cout << indent << "  size_t sizeInBits = " << ptr->sizeInBits << std::endl;
  std::cout << indent << "  size_t fieldCount = " << ptr->fieldCount << std::endl;
  std::cout << indent << "  size_t pointerLevel = " << ptr->pointerLevel << std::endl;
  std::cout << indent << "}" << std::endl;
}

void trill_debugPrintAny(TRILL_ANY ptr_) {
  if (!ptr_._any) {
    std::cout << "<null>" << std::endl;
    return;
  }
  AnyBox *ptr = (AnyBox *)ptr_._any;
  std::cout << "AnyBox {" << std::endl;
  std::cout << "  void *typeMetadata = ";
  trill_debugPrintTypeMetadata(ptr->typeMetadata, "  ");
  if (ptr->typeMetadata) {
    auto value = trill_getAnyValuePtr({ptr});
    TypeMetadata *meta = (TypeMetadata *)ptr->typeMetadata;
    std::string typeName = meta->name;
    if (typeName == "Int") {
      std::cout << "  int64_t value = " << TYPE_PUN(value, int64_t) << std::endl;
    } else if (typeName == "Bool") {
      std::cout << "  bool value = " << (TYPE_PUN(value, bool) ? "true" : "false") << std::endl;
    } else if (strncmp(meta->name, "*", 1) == 0) {
      std::cout << value << std::endl;
    }
  }
  std::cout << "}" << std::endl;
}

void trill_dumpProtocol(ProtocolMetadata *proto) {
    trill_assert(proto != nullptr);
    std::cout << proto->name << " {" << std::endl;
    for (size_t i = 0; i < proto->methodCount; ++i) {
        std::cout << "  " << proto->methodNames[i] << std::endl;
    }
    std::cout << "}" << std::endl;
}
  
uint8_t trill_checkTypes(TRILL_ANY anyValue_, void *typeMetadata_) {
  AnyBox *anyValue = (AnyBox *)anyValue_._any;
  TypeMetadata *typeMetadata = (TypeMetadata *)typeMetadata_;
  trill_assert(anyValue != nullptr);
  TypeMetadata *anyMetadata = (TypeMetadata *)anyValue->typeMetadata;
  return anyMetadata == typeMetadata;
}

void *trill_checkedCast(TRILL_ANY anyValue_, void *typeMetadata_) {
  AnyBox *anyValue = (AnyBox *)anyValue_._any;
  TypeMetadata *typeMetadata = (TypeMetadata *)typeMetadata_;
  trill_assert(anyValue != nullptr);
  TypeMetadata *anyMetadata = (TypeMetadata *)anyValue->typeMetadata;
  if (anyMetadata != typeMetadata) {
    trill_reportCastError(anyMetadata, typeMetadata);
  }
  return trill_getAnyValuePtr(anyValue_);
}

uint8_t trill_anyIsNil(TRILL_ANY any_) {
  auto any = reinterpret_cast<AnyBox*>(any_._any);
  trill_assert(any != nullptr);
  auto metadata = reinterpret_cast<TypeMetadata*>(any->typeMetadata);
  auto pointerLevel = metadata->pointerLevel;
  if (pointerLevel > 0) { return 0; }
  auto anyValuePointer = reinterpret_cast<uintptr_t*>(trill_getAnyValuePtr(any_));
  if (*anyValuePointer == 0) {
    return 1;
  }
  return 0;
}

}
