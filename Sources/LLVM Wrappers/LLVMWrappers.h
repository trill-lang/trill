//
//  LLVMWrappers.h
//  Trill
//

#ifndef LLVMWrappers_h
#define LLVMWrappers_h

#include <stdbool.h>
#include <stdio.h>

#define _DEBUG
#define _GNU_SOURCE
#define __STDC_CONSTANT_MACROS
#define __STDC_FORMAT_MACROS
#define __STDC_LIMIT_MACROS
#undef DEBUG
#include "trill.h"
#include <clang-c/Platform.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/BitWriter.h>
#include <llvm-c/Core.h>
#include <llvm-c/ExecutionEngine.h>
#include <llvm-c/Object.h>
#include <llvm-c/Transforms/IPO.h>
#include <llvm-c/Transforms/Scalar.h>

#ifdef I // are you kidding me?
#undef I
#endif

#import <clang-c/Index.h>

#ifdef __cplusplus
extern "C" {
#endif

TRILL_ASSUME_NONNULL_BEGIN

typedef enum RawOutputFormat {
  Binary, Object, ASM, LLVM, Bitcode,
  AST, JavaScript,
} RawOutputFormat;

typedef enum RawMode {
  Emit, RunJIT,
  OnlyDiagnostics
} RawMode;

typedef enum OptimizationLevel {
  O0, O1, O2, O3
} OptimizationLevel;
  
typedef struct RawOptions {
  OptimizationLevel optimizationLevel;
  bool importC;
  bool emitTiming;
  bool parseOnly;
  bool isStdin;
  bool jsonDiagnostics;
  bool showImports;
  bool stdlib;
  RawMode mode;
  RawOutputFormat outputFormat;
  char *_Nullable target;
  char *_Nullable outputFilename;
  char *_Nullable *_Nonnull filenames;
  size_t filenameCount;
  char *_Nullable *_Nonnull linkerFlags;
  size_t linkerFlagCount;
  char *_Nullable *_Nonnull ccFlags;
  size_t ccFlagCount;
  char *_Nullable *_Nonnull jitFlags;
  size_t jitFlagCount;
} RawOptions;
_Nullable LLVMExecutionEngineRef LLVMCreateOrcMCJITReplacement(LLVMModuleRef module,
                                                               LLVMTargetMachineRef targetRef);
void LLVMLinkInOrcMCJITReplacement(void);
int clang_isNoReturn(CXCursor cursor);
int clang_linkExecutableFromObject(const char *targetTriple,
                                   const char *filename,
                                   const char *runtimeFrameworkPath,
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

TRILL_ASSUME_NONNULL_END

#endif /* LLVMWrappers_hpp */
