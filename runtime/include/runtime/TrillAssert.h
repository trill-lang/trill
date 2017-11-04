///
/// TrillAssert.h
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

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

void trill_assertionFailure(const char *NONNULL message,
                            const char *NONNULL file,
                            const int line,
                            const char *NONNULL function) TRILL_NORETURN;

#ifdef __cplusplus
}
}
#endif

#endif /* trill_assert_h */
