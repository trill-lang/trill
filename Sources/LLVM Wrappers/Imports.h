//
//  Imports.h
//  Trill
//

#ifndef Imports_h
#define Imports_h

#define _DEBUG
#define _GNU_SOURCE
#define __STDC_CONSTANT_MACROS
#define __STDC_FORMAT_MACROS
#define __STDC_LIMIT_MACROS
#undef DEBUG
#include <llvm-c/Analysis.h>
#include <llvm-c/Core.h>
#include <llvm-c/ExecutionEngine.h>
#include <llvm-c/Transforms/Scalar.h>
#include <llvm-c/Transforms/IPO.h>
#include <clang-c/Platform.h>
#include "trill.h"

#ifdef I // are you kidding me?
#undef I
#endif

#import <clang-c/Index.h>

#endif /* Imports_h */
