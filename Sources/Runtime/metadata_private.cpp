//
//  metadata_private.cpp
//  trill
//
//  Created by Harlan Haskins on 3/8/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

#include "metadata.h"
#include "metadata_private.h"
#include <iostream>

namespace trill {

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

void AnyBox::updateField(uint64_t fieldNum, Any newValue) {
  auto newType = newValue->typeMetadata;
  auto fieldMeta = fieldMetadata(fieldNum);
  if (fieldMeta->typeMetadata != newType) {
    trill_reportCastError(fieldMeta->typeMetadata, newValue->typeMetadata);
  }
  memcpy(fieldValuePtr(fieldNum), newValue->value(), newType->sizeInBytes());
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

Any AnyBox::extractField(uint64_t fieldNum) {
  auto fieldMeta = fieldMetadata(fieldNum);
  auto fieldTypeMeta = fieldMeta->typeMetadata;
  Any newAny;
  newAny.typeMetadata = fieldTypeMeta;
  memcpy(newAny.payload, fieldValuePtr(fieldNum),
         fieldTypeMeta->sizeInBytes());
  return newAny;
}

bool AnyBox::isNil() {
  trill_assert(typeMetadata != nullptr);
  if (typeMetadata->pointerLevel > 0) { return false; }
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
