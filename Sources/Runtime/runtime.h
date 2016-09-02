//
//  runtime.h
//  Trill
//

#ifndef runtime_h
#define runtime_h

#include <stdio.h>
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

#ifdef __cplusplus
}
}
#endif

// TRILL_ASSUME_NONNULL_END
  
#endif /* runtime_h */
