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

void *_Nonnull trill_allocateAny(void *typeMetadata_) {
  trill_assert(typeMetadata_ != nullptr);
  TypeMetadata *typeMetadata = (TypeMetadata *)typeMetadata_;
  size_t fullSize = sizeof(AnyBox) + typeMetadata->sizeInBits;
  AnyBox *ptr = (AnyBox *)trill_alloc(fullSize);
  ptr->typeMetadata = typeMetadata;
  return ptr;
}

void *_Nonnull trill_copyAny(void *any) {
  trill_assert(any != nullptr);
  AnyBox *ptr = (AnyBox *)any;
  uint64_t size = ((TypeMetadata *)ptr->typeMetadata)->sizeInBits;
  AnyBox *header = (AnyBox *)trill_alloc(sizeof(AnyBox) + size);
  memcpy(header, any, sizeof(AnyBox) + size);
  return header;
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

void *_Nonnull trill_getAnyFieldValuePtr(void *any_, uint64_t fieldNum) {
  trill_assert(any_ != nullptr);
  auto any = (AnyBox *)any_;
  auto origPtr = trill_getAnyValuePtr(any);
  auto fieldMeta = trill_getAnyFieldMetadata(any, fieldNum);
  return (void *)((intptr_t)origPtr + fieldMeta->offset);
}
  
void *_Nonnull trill_extractAnyField(void *any_, uint64_t fieldNum) {
  trill_assert(any_ != nullptr);
  auto any = (AnyBox *)any_;
  auto fieldMeta = trill_getAnyFieldMetadata(any, fieldNum);
  auto fieldTypeMeta = (TypeMetadata *)fieldMeta->type;
  auto newAny = (AnyBox *)trill_allocateAny(fieldTypeMeta);
  auto fieldPtr = trill_getAnyValuePtr(newAny);
  memcpy(fieldPtr, trill_getAnyFieldValuePtr(any, fieldNum), fieldTypeMeta->sizeInBits);
  return newAny;
}
  
void trill_updateAny(void *any_, uint64_t fieldNum, void *newAny_) {
  auto any = (AnyBox *)any_;
  auto newAny = (AnyBox *)newAny_;
  trill_assert(any != nullptr);
  trill_assert(newAny != nullptr);
  auto newType = (TypeMetadata *)newAny->typeMetadata;
  trill_assert(newType);
  auto fieldMeta = trill_getAnyFieldMetadata(any, fieldNum);
  if (fieldMeta->type != newType) {
    trill_reportCastError((TypeMetadata *)fieldMeta->type, (TypeMetadata *)newAny->typeMetadata);
  }
  auto fieldPtr = trill_getAnyFieldValuePtr(any, fieldNum);
  auto newPtr = trill_getAnyValuePtr(newAny);
  memcpy(fieldPtr, newPtr, newType->sizeInBits);
}

void *_Nonnull trill_getAnyValuePtr(void *_Nullable anyValue) {
  return (void *)((intptr_t)anyValue + sizeof(AnyBox));
}

void *_Nonnull trill_getAnyTypeMetadata(void *_Nonnull anyValue) {
  trill_assert(anyValue != nullptr);
  return ((AnyBox *)anyValue)->typeMetadata;
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
  std::cout << "TypeMetadata {" << std::endl;
  std::cout << indent << "  const char *name = \"" << ptr->name << "\"" << std::endl;
  std::cout << indent << "  const void *fields = [" << std::endl;
  trill_debugPrintFields(ptr->fields, ptr->fieldCount, indent + "  ");
  std::cout << indent << "  ]" << std::endl;
  std::cout << indent << "  bool isReferenceType = " << !!ptr->isReferenceType << std::endl;
  std::cout << indent << "  size_t sizeInBits = " << ptr->sizeInBits << std::endl;
  std::cout << indent << "  size_t fieldCount = " << ptr->fieldCount << std::endl;
  std::cout << indent << "  size_t pointerLevel = " << ptr->pointerLevel << std::endl;
  std::cout << indent << "}" << std::endl;
}
  
void trill_debugPrintAny(void *ptr_) {
  if (!ptr_) {
    std::cout << "<null>" << std::endl;
    return;
  }
  AnyBox *ptr = (AnyBox *)ptr_;
  std::cout << "AnyBox {" << std::endl;
  std::cout << "  void *typeMetadata = ";
  trill_debugPrintTypeMetadata(ptr->typeMetadata, "  ");
  if (ptr->typeMetadata) {
    void *valuePtr = trill_getAnyValuePtr(ptr_);
    TypeMetadata *meta = (TypeMetadata *)ptr->typeMetadata;
    std::string typeName = meta->name;
    if (typeName == "Int") {
      std::cout << "  int64_t value = " << TYPE_PUN(valuePtr, int64_t) << std::endl;
    } else if (typeName == "Bool") {
      std::cout << "  bool value = " << (TYPE_PUN(valuePtr, bool) ? "true" : "false") << std::endl;
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
  
uint8_t trill_checkTypes(void *anyValue_, void *typeMetadata_) {
  AnyBox *anyValue = (AnyBox *)anyValue_;
  TypeMetadata *typeMetadata = (TypeMetadata *)typeMetadata_;
  trill_assert(anyValue != nullptr);
  TypeMetadata *anyMetadata = (TypeMetadata *)anyValue->typeMetadata;
  return anyMetadata == typeMetadata;
}
  
void *trill_checkedCast(void *anyValue_, void *typeMetadata_) {
  AnyBox *anyValue = (AnyBox *)anyValue_;
  TypeMetadata *typeMetadata = (TypeMetadata *)typeMetadata_;
  trill_assert(anyValue != nullptr);
  TypeMetadata *anyMetadata = (TypeMetadata *)anyValue->typeMetadata;
  if (anyMetadata != typeMetadata) {
    trill_reportCastError(anyMetadata, typeMetadata);
  }
  return trill_getAnyValuePtr(anyValue_);
}
  
}
