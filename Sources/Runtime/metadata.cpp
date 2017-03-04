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
  if (real->fieldCount <= field) {
    trill_fatalError("field index out of bounds");
  }
  return &(real->fields[field]);
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
  auto fullSize = sizeof(AnyBox) + typeMetadata->sizeInBits;
  auto ptr = reinterpret_cast<AnyBox *>(trill_alloc(fullSize));
  ptr->typeMetadata = typeMetadata;
  return {ptr};
}

TRILL_ANY trill_copyAny(TRILL_ANY any) {
  auto ptr = any.any();
  trill_assert(ptr != nullptr);
  auto typeMetadata = ptr->typeMetadata;
  if (typeMetadata->isReferenceType) { return any; }
  auto newAny = trill_allocateAny(typeMetadata);
  auto valuePtr = trill_getAnyValuePtr(any);
  auto newValuePtr = trill_getAnyValuePtr(newAny);
  memcpy(newValuePtr, valuePtr, typeMetadata->sizeInBits);
  return newAny;
}

static const FieldMetadata *trill_getAnyFieldMetadata(AnyBox *any,
                                                      uint64_t fieldNum) {
  auto meta = any->typeMetadata;
  trill_assert(meta != nullptr);
  trill_assert(fieldNum < meta->fieldCount);
  auto fieldMeta = trill_getFieldMetadata(meta, fieldNum);
  trill_assert(fieldMeta != nullptr);
  return reinterpret_cast<const FieldMetadata *>(fieldMeta);
}

void trill_reportCastError(const TypeMetadata *anyMetadata, const TypeMetadata *typeMetadata) {
  std::string failureDesc = "checked cast failed: cannot convert ";
  failureDesc += trill_getTypeName(anyMetadata);
  failureDesc += " to ";
  failureDesc += trill_getTypeName(typeMetadata);
  trill_fatalError(failureDesc.c_str());
}

void *trill_getAnyFieldValuePtr(TRILL_ANY any_, uint64_t fieldNum) {
  auto any = any_.any();
  trill_assert(any != nullptr);
  auto origPtr = trill_getAnyValuePtr(any_);
  trill_assert(origPtr != nullptr);
  auto typeMeta = any->typeMetadata;
  auto fieldMeta = trill_getAnyFieldMetadata(any, fieldNum);
  if (typeMeta->isReferenceType) {
    origPtr = *reinterpret_cast<void **>(origPtr);
    trill_assert(origPtr != nullptr);
  }
  return reinterpret_cast<void *>(
          reinterpret_cast<intptr_t>(origPtr) + fieldMeta->offset);
}

TRILL_ANY trill_extractAnyField(TRILL_ANY any_, uint64_t fieldNum) {
  auto any = any_.any();
  trill_assert(any != nullptr);
  auto fieldMeta = trill_getAnyFieldMetadata(any, fieldNum);
  auto fieldTypeMeta = fieldMeta->typeMetadata;
  auto newAny = trill_allocateAny(fieldTypeMeta);
  auto fieldPtr = trill_getAnyValuePtr(newAny);
  auto anyFieldValuePointer = trill_getAnyFieldValuePtr(any_, fieldNum);
  memcpy(fieldPtr, anyFieldValuePointer, fieldTypeMeta->sizeInBits);
  return newAny;
}

void trill_updateAny(TRILL_ANY any_, uint64_t fieldNum, TRILL_ANY newAny_) {
  auto any = any_.any();
  auto newAny = newAny_.any();
  trill_assert(any != nullptr);
  trill_assert(newAny != nullptr);
  auto newType = newAny->typeMetadata;
  trill_assert(newType);
  auto fieldMeta = trill_getAnyFieldMetadata(any, fieldNum);
  if (fieldMeta->typeMetadata != newType) {
    trill_reportCastError(fieldMeta->typeMetadata, newAny->typeMetadata);
  }
  auto fieldPtr = trill_getAnyFieldValuePtr({any}, fieldNum);
  auto newPtr = trill_getAnyValuePtr({newAny});
  memcpy(fieldPtr, newPtr, newType->sizeInBits);
}

void *_Nonnull trill_getAnyValuePtr(TRILL_ANY anyValue) {
  return reinterpret_cast<void *>(
           reinterpret_cast<intptr_t>(anyValue._any) + sizeof(AnyBox));
}

const void *_Nonnull trill_getAnyTypeMetadata(TRILL_ANY anyValue) {
  trill_assert(anyValue._any != nullptr);
  return anyValue.any()->typeMetadata;
}

void trill_debugPrintFields(const FieldMetadata *fields,
                            uint64_t count,
                            std::string indent = "") {
  for (size_t i = 0; i < count; i++) {
    auto field = fields[i];
    std::string typeName = field.typeMetadata->name;
    std::string fieldName = field.name;
    std::cout << indent << "  " << fieldName << ": "
              << typeName << std::endl;
  }
}

void trill_debugPrintTypeMetadata(const void *ptr_, std::string indent = "") {
  if (!ptr_) {
    std::cout << "<null>" << std::endl;
    return;
  }
  auto ptr = reinterpret_cast<const TypeMetadata *>(ptr_);
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
  auto ptr = ptr_.any();
  std::cout << "AnyBox {" << std::endl;
  std::cout << "  void *typeMetadata = ";
  trill_debugPrintTypeMetadata(ptr->typeMetadata, "  ");
  if (ptr->typeMetadata) {
    auto value = trill_getAnyValuePtr({ptr});
    auto meta = ptr->typeMetadata;
    std::string typeName = meta->name;
    if (typeName == "Int") {
      std::cout << "  int64_t value = " <<
        *reinterpret_cast<int64_t *>(value) << std::endl;
    } else if (typeName == "Bool") {
      std::cout << "  bool value = " <<
        (*reinterpret_cast<bool *>(value) ? "true" : "false") << std::endl;
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
  
uint8_t trill_checkTypes(TRILL_ANY anyValue_, const void *typeMetadata_) {
  auto any = anyValue_.any();
  auto typeMetadata = reinterpret_cast<const TypeMetadata *>(typeMetadata_);
  trill_assert(any != nullptr);
  auto anyMetadata = any->typeMetadata;
  return anyMetadata == typeMetadata;
}

const void *trill_checkedCast(TRILL_ANY anyValue_, const void *typeMetadata_) {
  auto any = anyValue_.any();
  auto typeMetadata = reinterpret_cast<const TypeMetadata *>(typeMetadata_);
  trill_assert(any != nullptr);
  auto anyMetadata = any->typeMetadata;
  if (anyMetadata != typeMetadata) {
    trill_reportCastError(anyMetadata, typeMetadata);
  }
  return trill_getAnyValuePtr(anyValue_);
}

uint8_t trill_anyIsNil(TRILL_ANY any_) {
  auto any = any_.any();
  trill_assert(any != nullptr);
  auto metadata = any->typeMetadata;
  auto pointerLevel = metadata->pointerLevel;
  if (pointerLevel > 0) { return 0; }
  auto anyValuePointer = reinterpret_cast<uintptr_t *>(trill_getAnyValuePtr(any_));
  if (*anyValuePointer == 0) {
    return 1;
  }
  return 0;
}

}
