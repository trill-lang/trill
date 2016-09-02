//
//  runtime.h
//  Trill
//

#ifndef runtime_h
#define runtime_h

#include <stdio.h>
#include <stdint.h>
#include "defines.h"

// TRILL_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
namespace trill {
extern "C" {
#endif

void trill_init();
  
void *_Nonnull trill_alloc(size_t size);

void trill_fatalError(const char *_Nonnull message) TRILL_NORETURN;
  
void trill_registerDeinitializer(void *_Nonnull object, void (*_Nonnull deinitializer)(void *_Nonnull));

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

// TRILL_ASSUME_NONNULL_END
  
#endif /* runtime_h */
