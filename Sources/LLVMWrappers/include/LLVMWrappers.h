///
/// LLVMWrappers.h
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

#ifndef LLVMWrappers_h
#define LLVMWrappers_h

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

_Pragma("clang assume_nonnull begin")

void *_Nullable LLVMCreateOrcMCJITReplacement(void *module, void *targetRef);
void LLVMLinkInOrcMCJITReplacement(void);
int clang_isNoReturn(void *cursor);
int clang_linkExecutableFromObject(const char *targetTriple,
  const char *filename, const char *runtimeLibraryDir,
  const char *_Nullable *_Nonnull linkerFlags, size_t linkerFlagsCount,
  const char *_Nullable *_Nonnull ccFlags, size_t ccFlagsCount);
char *_Nullable LLVMAddArchive(void *ref, const char *filename);

_Pragma("clang assume_nonnull end")

#ifdef __cplusplus
}
#endif

#endif /* LLVMWrappers_hpp */
