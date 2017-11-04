///
/// Metadata.cpp
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

#include <iostream>
#include <string>

#include "runtime/Runtime.h"
#include "runtime/Metadata.h"
#include "runtime/private/Metadata.h"

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

void trill_reportCastError(const TypeMetadata *anyMetadata,
                           const TypeMetadata *typeMetadata) {
  std::string failureDesc = "checked cast failed: cannot convert ";
  failureDesc += trill_getTypeName(anyMetadata);
  failureDesc += " to ";
  failureDesc += trill_getTypeName(typeMetadata);
  trill_fatalError(failureDesc.c_str());
}

const FieldMetadata *TypeMetadata::fieldMetadata(uint64_t index) const {
  if (fieldCount <= index) {
    std::stringstream msg;
    std::string name(this->name);
    msg << "field index " << index << " out of bounds for type " << name
    << " with " << fieldCount << " fields";
    trill_fatalError(msg.str().c_str());
  }
  return &fields[index];
}

void TypeMetadata::debugPrint(std::string indent) const {
  std::string typeName = name;
  std::cout << "TypeMetadata {" << std::endl;
  std::cout << indent << "  const char *name = \"" << typeName << "\"" << std::endl;
  std::cout << indent << "  const void *fields = [" << std::endl;
  for (size_t i = 0; i < fieldCount; i++) {
    auto field = fields[i];
    std::string typeName = field.typeMetadata->name;
    std::string fieldName = field.name;
    std::cout << indent << "  " << fieldName << ": "
    << typeName << std::endl;
  }
  std::cout << indent << "  ]" << std::endl;
  std::cout << indent << "  bool isReferenceType = " << !!isReferenceType << std::endl;
  std::cout << indent << "  size_t sizeInBits = " << sizeInBits << std::endl;
  std::cout << indent << "  size_t fieldCount = " << fieldCount << std::endl;
  std::cout << indent << "  size_t pointerLevel = " << pointerLevel << std::endl;
  std::cout << indent << "}" << std::endl;
}

AnyBox *AnyBox::create(const trill::TypeMetadata *metadata) {
  auto fullSize = sizeof(AnyBox) + metadata->sizeInBits;
  auto anyBoxPtr = trill_alloc(fullSize);
  auto ptr = reinterpret_cast<AnyBox *>(anyBoxPtr);
  ptr->typeMetadata = metadata;
  return ptr;
}

AnyBox *AnyBox::copy() {
  if (typeMetadata->isReferenceType) { return this; }
  auto newAny = AnyBox::create(typeMetadata);
  memcpy(newAny->value(), value(), typeMetadata->sizeInBits);
  return newAny;
}

void AnyBox::updateField(uint64_t fieldNum, trill::AnyBox *newValue) {
  auto newType = newValue->typeMetadata;
  auto fieldMeta = fieldMetadata(fieldNum);
  if (fieldMeta->typeMetadata != newType) {
    trill_reportCastError(fieldMeta->typeMetadata, newValue->typeMetadata);
  }
  memcpy(fieldValuePtr(fieldNum), newValue->value(), newType->sizeInBits);
}

void *AnyBox::fieldValuePtr(uint64_t fieldNum) {
  auto origPtr = value();
  auto fieldMeta = fieldMetadata(fieldNum);
  if (typeMetadata->isReferenceType) {
    origPtr = *reinterpret_cast<void **>(origPtr);
    trill_assert(origPtr != nullptr);
  }
  return reinterpret_cast<void *>(
           reinterpret_cast<intptr_t>(origPtr) + fieldMeta->offset);
}

AnyBox *AnyBox::extractField(uint64_t fieldNum) {
  auto fieldMeta = fieldMetadata(fieldNum);
  auto fieldTypeMeta = fieldMeta->typeMetadata;
  auto newAny = AnyBox::create(fieldTypeMeta);
  memcpy(newAny->value(), fieldValuePtr(fieldNum),
         fieldTypeMeta->sizeInBits);
  return newAny;
}

bool AnyBox::isNil() {
  auto pointerLevel = typeMetadata->pointerLevel;
  if (pointerLevel > 0) { return false; }
  auto anyValuePointer = reinterpret_cast<uintptr_t *>(value());
  if (*anyValuePointer == 0) {
    return true;
  }
  return false;
}

void AnyBox::debugPrint(std::string indent) {
  std::cout << "AnyBox {" << std::endl;
  std::cout << "  void *typeMetadata = ";
  if (typeMetadata) {
    typeMetadata->debugPrint("  ");
    auto value = this->value();
    std::string typeName = typeMetadata->name;
    if (typeName == "Int") {
      std::cout << "  int64_t value = " <<
      *reinterpret_cast<int64_t *>(value) << std::endl;
    } else if (typeName == "Bool") {
      std::cout << "  bool value = " <<
      (*reinterpret_cast<bool *>(value) ? "true" : "false") << std::endl;
    } else if (strncmp(typeMetadata->name, "*", 1) == 0) {
      std::cout << value << std::endl;
    }
  }
  std::cout << "}" << std::endl;
}

}
