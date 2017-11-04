///
/// Demangle.h
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

#ifndef demangle_hpp
#define demangle_hpp

#include <stdio.h>

#include "runtime/Defines.h"

#ifdef __cplusplus
#include <string>
namespace trill {
bool demangle(std::string &symbol, std::string &out);

extern "C" {
#endif
  
char *trill_demangle(const char *symbol);

#ifdef __cplusplus
}
}
#endif

#endif /* demangle_hpp */
