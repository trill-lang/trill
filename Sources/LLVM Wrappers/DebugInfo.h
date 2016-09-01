//
//  DebugInfo.h
//  Trill
//
//  Created by Harlan Haskins on 8/31/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

#ifndef DebugInfo_h
#define DebugInfo_h

#include <stdio.h>
#include "Imports.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RawSourceLocation {
  int line;
  int column;
  char *file;
} RawSourceLocation;

typedef struct { int _dummy; } *DebugInfoBuilderRef;

DebugInfoBuilderRef LLVMCreateDebugInfoBuilder(LLVMModuleRef moduleRef);
void DestroyDebugInfoBuilder(DebugInfoBuilderRef builderRef);
void LLVMCreateTypeDebugInfo(DebugInfoBuilderRef builderRef,
                             LLVMTypeRef typeRef, RawSourceLocation loc);
void LLVMCreateFunctionDebugInfo(DebugInfoBuilderRef builderRef,
                                 LLVMValueRef functionRef,
                                 const char *prettyName,
                                 RawSourceLocation loc);
#ifdef __cplusplus
}
#endif
  
#endif /* DebugInfo_hpp */
