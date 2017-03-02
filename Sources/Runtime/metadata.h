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
namespace trill {
extern "C" {
#endif

typedef struct TRILL_ANY {
  void * _Nonnull _any;
} TRILL_ANY;

void *_Nonnull trill_checkedCast(TRILL_ANY anyValue, void *_Nonnull type);
TRILL_ANY trill_allocateAny(void *_Nonnull type);
void *_Nonnull trill_getAnyTypeMetadata(TRILL_ANY anyValue);
void *_Nullable trill_getAnyValuePtr(TRILL_ANY anyValue);
TRILL_ANY trill_copyAny(TRILL_ANY any);
uint8_t trill_checkTypes(TRILL_ANY anyValue_, void *_Nonnull typeMetadata_);
void trill_debugPrintAny(TRILL_ANY ptr);
const char *_Nonnull trill_getTypeName(const void *_Nullable typeMeta);
uint64_t trill_getTypeSizeInBits(const void *_Nullable typeMeta);
const void *_Nullable trill_getFieldMetadata(const void *_Nullable typeMeta, uint64_t field);
uint64_t trill_getNumFields(const void *_Nullable typeMeta);
const char *_Nullable trill_getFieldName(const void *_Nullable fieldMeta);
const void *_Nullable trill_getFieldType(const void *_Nullable fieldMeta);
size_t trill_getFieldOffset(const void *_Nullable fieldMeta);
uint8_t trill_isReferenceType(const void *_Nullable typeMeta);
TRILL_ANY trill_extractAnyField(TRILL_ANY any_, uint64_t fieldNum);
void trill_updateAny(TRILL_ANY any_, uint64_t fieldNum, TRILL_ANY newAny_);
uint8_t trill_anyIsNil(TRILL_ANY any_);

#ifdef __cplusplus
}
}
#endif

#endif /* metadata_h */
