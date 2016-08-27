//
//  runtime.h
//  Trill
//

#ifndef runtime_h
#define runtime_h

#include <stdio.h>

#define TRILL_NORETURN __attribute__((noreturn))

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
  
#endif /* runtime_h */
