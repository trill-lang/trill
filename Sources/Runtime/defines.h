//
//  defines.h
//  Trill
//
//  Created by Harlan Haskins on 9/1/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

#ifndef defines_h
#define defines_h

#if __has_feature(nullability)
#define NONNULL _Nonnull
#else
#define NONNULL
#endif

#define TRILL_ASSUME_NONNULL_BEGIN _Pragma("clang assume_nonnull begin")
#define TRILL_ASSUME_NONNULL_END _Pragma("clang assume_nonnull end")

#define TRILL_NORETURN __attribute__((noreturn))
#define TRILL_NONNULL _Nonnull

#endif /* defines_h */
