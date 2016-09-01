//
//  LLVMWrappers.h
//  Trill
//

#ifndef LLVMWrappers_h
#define LLVMWrappers_h

#include <stdio.h>

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

#ifdef __cplusplus
extern "C" {
#endif

_Pragma("clang assume_nonnull begin")
  
typedef enum RawMode {
  EmitBinary, EmitObj, EmitASM, EmitLLVM,
  EmitAST, PrettyPrint, EmitJavaScript, JIT
} RawMode;

typedef enum OptimizationLevel {
  O0, O1, O2, O3
} OptimizationLevel;
  
typedef struct RawOptions {
  OptimizationLevel optimizationLevel;
  bool importC;
  bool emitTiming;
  bool isStdin;
  RawMode mode;
  char *_Nullable target;
  char *_Nullable outputFilename;
  char *_Nullable *_Nonnull filenames;
  size_t filenameCount;
  char *_Nullable *_Nonnull linkerFlags;
  size_t linkerFlagCount;
  char *_Nullable *_Nonnull ccFlags;
  size_t ccFlagCount;
} RawOptions;

_Nullable LLVMExecutionEngineRef LLVMCreateOrcMCJITReplacement(LLVMModuleRef module, LLVMTargetMachineRef targetRef);
void LLVMLinkInOrcMCJITReplacement(void);
const char *LLVMGetJITError();
int clang_isNoReturn(CXCursor cursor);
int clang_linkExecutableFromObject(const char *targetTriple,
                                   const char *filename,
                                   char *_Nullable *_Nonnull linkerFlags,
                                   size_t linkerFlagsCount,
                                   char *_Nullable *_Nonnull ccFlags,
                                   size_t ccFlagsCount);
char *_Nullable LLVMAddArchive(LLVMExecutionEngineRef ref, const char *filename);
RawOptions ParseArguments(int argc, char *_Nullable *_Nullable argv);
void DestroyRawOptions(RawOptions options);

#ifdef __cplusplus
}
#endif

_Pragma("clang assume_nonnull end")

#endif /* LLVMWrappers_hpp */
