///
/// LLVMWrappers.cpp
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

#include "LLVMWrappers.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"

#define _DEBUG
#define _GNU_SOURCE
#define __STDC_CONSTANT_MACROS
#define __STDC_FORMAT_MACROS
#define __STDC_LIMIT_MACROS
#undef DEBUG
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

#include "clang/AST/Attr.h"
#include "clang/AST/Decl.h"
#include "clang/Driver/Driver.h"
#include "clang/Driver/Job.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/TextDiagnosticPrinter.h"
#include "clang/Lex/LiteralSupport.h"
#include "llvm-c/TargetMachine.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"
#include "llvm/ExecutionEngine/OrcMCJITReplacement.h"
#include "llvm/ExecutionEngine/RTDyldMemoryManager.h"
#include "llvm/ExecutionEngine/SectionMemoryManager.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/Object/Archive.h"
#include "llvm/Object/ObjectFile.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/Program.h"
#include "llvm/Support/TargetRegistry.h"
#include "llvm/Target/TargetMachine.h"

#pragma clang diagnostic pop

using namespace llvm;

std::pair<char **, size_t> toCStrings(std::vector<std::string> strings) {
  char **cStrings = (char **)malloc(strings.size() * sizeof(char *));
  for (auto i = 0; i < strings.size(); ++i) {
    cStrings[i] = strdup(strings[i].c_str());
  }
  return { cStrings, strings.size() };
}

int clang_isNoReturn(void *cursorPtr) {
  auto cursor = *static_cast<CXCursor *>(cursorPtr);
  assert(cursor.kind == CXCursor_FunctionDecl);
  auto fn = static_cast<const clang::FunctionDecl *>(cursor.data[0]);
  if (!fn) return 0;
  return fn->isNoReturn() ? 1 : 0;
}

char *_Nullable LLVMAddArchive(void *ref, const char *filename) {
  auto engine = unwrap((LLVMExecutionEngineRef)ref);
  auto buf = MemoryBuffer::getFile(filename);
  if (auto err = buf.getError()) {
    return strdup(err.message().c_str());
  }
  auto arch = object::Archive::create(*buf.get());
  if (Error err = arch.takeError()) {
    return strdup(errorToErrorCode(std::move(err)).message().c_str());
  }
  auto archive = std::move(arch.get());
  auto bin = object::OwningBinary<object::Archive>(std::move(archive),
                                                   std::move(buf.get()));
  engine->addArchive(std::move(bin));
  return NULL;
}

void *LLVMCreateOrcMCJITReplacement(void *module, void *targetRef) {
  auto target = reinterpret_cast<TargetMachine *>(targetRef);
  target->Options.DebuggerTuning = DebuggerKind::LLDB;
  target->Options.MCOptions.SanitizeAddress = true;
  EngineBuilder builder(std::unique_ptr<Module>(unwrap((LLVMModuleRef)module)));
  builder.setMCJITMemoryManager(make_unique<SectionMemoryManager>());
  builder.setTargetOptions(target->Options);
  builder.setUseOrcMCJITReplacement(true);
  return (void *)builder.create();
}
