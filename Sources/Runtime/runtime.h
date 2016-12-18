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
    
#define trill_assert(x) if (!(x)) trill_fatalError(": assertion failed: "#x)

void trill_init();

void trill_printStackTrace();
  
void *_Nonnull trill_alloc(size_t size);

void trill_fatalError(const char *_Nonnull message) TRILL_NORETURN;
  
void trill_registerDeinitializer(void *_Nonnull object, void (*_Nonnull deinitializer)(void *_Nonnull));

#ifdef __cplusplus
}
}
#endif

// TRILL_ASSUME_NONNULL_END
  
#endif /* runtime_h */
