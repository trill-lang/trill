///
/// Runtime.h
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

#ifndef runtime_h
#define runtime_h

#include <stdint.h>
#include <stdio.h>

#include "runtime/Defines.h"
#include "runtime/TrillAssert.h"

// TRILL_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
namespace trill {
extern "C" {
#endif

void trill_init();

void trill_once(uint64_t *NONNULL predicate, void (*NONNULL initializer)(void));
    
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
