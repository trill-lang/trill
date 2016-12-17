//
//  metadata.h
//  Trill
//
//  Created by Harlan Haskins on 9/2/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

#ifndef metadata_h
#define metadata_h

#include <stdio.h>
#include <stdint.h>
#include "defines.h"

#ifdef __cplusplus
namespace trill {
extern "C" {
#endif

void *_Nonnull trill_checkedCast(void *_Nullable anyValue, void *_Nonnull type);
void *_Nonnull trill_allocateAny(void *_Nonnull type);
void *_Nonnull trill_getAnyTypeMetadata(void *_Nonnull anyValue);
void *_Nonnull trill_getAnyValuePtr(void *_Nullable anyValue);
void *_Nonnull trill_copyAny(void *_Nonnull any);
uint8_t trill_checkTypes(void *_Nullable anyValue_, void *_Nonnull typeMetadata_);
void trill_debugPrintAny(void *_Nullable ptr);
const char *_Nonnull trill_getTypeName(const void *_Nullable typeMeta);
uint64_t trill_getTypeSizeInBits(const void *_Nullable typeMeta);
const void *_Nullable trill_getFieldMetadata(const void *_Nullable typeMeta, uint64_t field);
uint64_t trill_getNumFields(const void *_Nullable typeMeta);
const char *_Nullable trill_getFieldName(const void *_Nullable fieldMeta);
const void *_Nullable trill_getFieldType(const void *_Nullable fieldMeta);
size_t trill_getFieldOffset(const void *_Nullable fieldMeta);
uint8_t trill_isReferenceType(const void *_Nullable typeMeta);
void *_Nonnull trill_extractAnyField(void *_Nonnull any_, uint64_t fieldNum);
void trill_updateAny(void *_Nonnull any_, uint64_t fieldNum, void *_Nonnull newAny_);

#ifdef __cplusplus
}
}
#endif

#endif /* metadata_h */
