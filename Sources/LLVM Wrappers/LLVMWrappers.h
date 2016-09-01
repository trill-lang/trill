//
//  LLVMWrappers.h
//  Trill
//

#ifndef LLVMWrappers_h
#define LLVMWrappers_h

#include <stdio.h>
#include "Imports.h"

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
} RawOptions;

_Nullable LLVMExecutionEngineRef LLVMCreateOrcMCJITReplacement(LLVMModuleRef module, LLVMTargetMachineRef targetRef);
void LLVMLinkInOrcMCJITReplacement(void);
const char *LLVMGetJITError();
int clang_isNoReturn(CXCursor cursor);
int clang_linkExecutableFromObject(const char *targetTriple, const char *filename);
char *_Nullable LLVMAddArchive(LLVMExecutionEngineRef ref, const char *filename);
RawOptions ParseArguments(int argc, char *_Nullable *_Nullable argv);
void DestroyRawOptions(RawOptions options);

#ifdef __cplusplus
}
#endif

_Pragma("clang assume_nonnull end")

#endif /* LLVMWrappers_hpp */
