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

const char *_Nonnull trill_getTypeName(const void *_Nullable typeMeta);
uint64_t trill_getTypeSizeInBits(const void *_Nullable typeMeta);
const void *_Nullable trill_getFieldMetadata(const void *_Nullable typeMeta, uint64_t field);
uint64_t trill_getNumFields(const void *_Nullable typeMeta);
const char *_Nullable trill_getFieldName(const void *_Nullable fieldMeta);
const void *_Nullable trill_getFieldType(const void *_Nullable fieldMeta);
  
#ifdef __cplusplus
}
}
#endif

#endif /* metadata_h */
