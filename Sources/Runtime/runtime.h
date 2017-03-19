//
//  runtime.h
//  Trill
//

#ifndef runtime_h
#define runtime_h

#include "defines.h"
#include "trill_assert.h"
#include <stdint.h>
#include <stdio.h>

// TRILL_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
namespace trill {
extern "C" {
#endif

void trill_init();

void trill_once(uint64_t *NONNULL predicate, void (*NONNULL initializer)());
    
void trill_printStackTrace();
  
void *NONNULL trill_alloc(size_t size);

void trill_fatalError(const char *NONNULL message) TRILL_NORETURN;
  
void trill_registerDeinitializer(void *NONNULL object, void (*NONNULL deinitializer)(void *NONNULL));

#ifdef __cplusplus
}
}
#endif

// TRILL_ASSUME_NONNULL_END
  
#endif /* runtime_h */
