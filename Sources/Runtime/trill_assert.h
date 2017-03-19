//
//  trill_assert.h
//  Trill
//
//  Created by Samuel Giddins on 3/17/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

#ifndef trill_assert_h
#define trill_assert_h

#define trill_assert(x)                               \
    ({                                                \
      if (!(x)) {                                     \
        trill_assertionFailure(#x, __FILE__, __LINE__, __PRETTY_FUNCTION__);     \
      }                                               \
    })

#ifdef __cplusplus
namespace trill {
extern "C" {
#endif

void trill_assertionFailure(const char *NONNULL message, const char *NONNULL file, const int line, const char *NONNULL function) TRILL_NORETURN;

#ifdef __cplusplus
}
}
#endif

#endif /* trill_assert_h */
