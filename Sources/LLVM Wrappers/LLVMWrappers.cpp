//
//  LLVMWrappers.cpp
//  Trill
//

#include "LLVMWrappers.h"
#include "clang/AST/Decl.h"
#include "clang/AST/Attr.h"
#include "clang/Lex/LiteralSupport.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/Analysis/Passes.h"
#include "llvm/Transforms/Scalar.h"
#include "llvm/Transforms/IPO.h"
#include "llvm/Transforms/IPO/PassManagerBuilder.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"
#include "llvm/ExecutionEngine/RTDyldMemoryManager.h"
#include "llvm/ExecutionEngine/OrcMCJITReplacement.h"
#include "llvm/ExecutionEngine/SectionMemoryManager.h"
#include "llvm/Object/ObjectFile.h"
#include "llvm/Object/Archive.h"

using namespace llvm;
int clang_isNoReturn(CXCursor cursor) {
  assert(cursor.kind == CXCursor_FunctionDecl);
  auto fn = static_cast<const clang::FunctionDecl *>(cursor.data[0]);
  if (!fn) return 0;
  return fn->isNoReturn() ? 1 : 0;
}

char *_Nullable LLVMAddArchive(LLVMExecutionEngineRef ref, const char *filename) {
  auto engine = unwrap(ref);
  auto buf = MemoryBuffer::getFile(filename);
  if (auto err = buf.getError()) {
    return strdup(err.message().c_str());
  }
  auto arch = object::Archive::create(*buf.get());
  if (auto err = arch.getError()) {
    return strdup(err.message().c_str());
  }
  auto archive = std::move(arch.get());
  auto bin = object::OwningBinary<object::Archive>(std::move(archive),
                                                   std::move(buf.get()));
  engine->addArchive(std::move(bin));
  return NULL;
}

std::string GlobalJITError;

const char *LLVMGetJITError() {
  return GlobalJITError.c_str();
}

LLVMExecutionEngineRef LLVMCreateOrcMCJITReplacementForModule(LLVMModuleRef module) {
  EngineBuilder builder(std::unique_ptr<Module>(unwrap(module)));
  builder.setMCJITMemoryManager(make_unique<SectionMemoryManager>());
  builder.setErrorStr(&GlobalJITError);
  builder.setUseOrcMCJITReplacement(true);
  return wrap(builder.create());
}

RawOptions ParseArguments(int argc, char **argv) {
  cl::opt<std::string> filename(cl::Positional, cl::desc("<input file>"), cl::Required);
  cl::opt<bool> emitAST("emit-ast", cl::desc("Emit the AST to stdout"));
  cl::opt<OptimizationLevel> optimizationLevel(cl::desc("Choose optimization level:"),
                                               cl::values(clEnumVal(O0 , "No optimizations, enable debugging"),
                                                          clEnumVal(O1, "Enable trivial optimizations"),
                                                          clEnumVal(O2, "Enable default optimizations"),
                                                          clEnumVal(O3, "Enable expensive optimizations"),
                                                          clEnumValEnd));
  cl::opt<bool> emitLLVM("emit-llvm", cl::desc("Emit the generated LLVM IR to stdout"));
  cl::opt<bool> emitJS("emit-js", cl::desc("Emit the generated JavaScript to stdout"));
  cl::opt<bool> noImport("no-import", cl::desc("Don't import C declarations"));
  cl::opt<bool> emitTiming("emit-timing", cl::desc("Emit pass times (for performance debugging)"));
  cl::opt<bool> prettyPrint("pretty-print", cl::desc("Emit pretty-printed AST"));
  cl::list<std::string> args(cl::Positional, cl::desc("<interpreter-args>"), cl::Optional);
  cl::ParseCommandLineOptions(argc, argv);
  
  RawMode mode;
  bool importC = !noImport;
  if (emitLLVM) {
    mode = EmitLLVM;
  } else if (emitJS) {
    importC = false;
    mode = EmitJavaScript;
  } else if (emitAST) {
    mode = EmitAST;
  } else if (prettyPrint) {
    mode = PrettyPrint;
  } else {
    mode = JIT;
  }
  
  char **remainingArgs = (char **)malloc(args.size() * sizeof(char *));
  for (auto i = 0; i < args.size(); ++i) {
    remainingArgs[i] = strdup(args[i].c_str());
  }
  
  auto file = filename == "-" ? "<stdin>" : filename.c_str();
  
  return RawOptions {
    optimizationLevel,
    importC,
    emitTiming,
    mode,
    strdup(file),
    remainingArgs,
    args.size()
  };
}

void DestroyRawOptions(RawOptions options) {
  free(options.filename);
  for (auto i = 0; i < options.argCount; ++i) {
    free(options.remainingArgs[i]);
  }
  free(options.remainingArgs);
}
