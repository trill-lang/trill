//
//  LLVMWrappers.cpp
//  Trill
//

#include "LLVMWrappers.h"
#include "clang/AST/Decl.h"
#include "clang/AST/Attr.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/TextDiagnosticPrinter.h"
#include "clang/Driver/Driver.h"
#include "clang/Driver/Job.h"
#include "clang/Lex/LiteralSupport.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Program.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/TargetRegistry.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm-c/TargetMachine.h"
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


std::pair<char **, size_t> toCStrings(std::vector<std::string> strings) {
  char **cStrings = (char **)malloc(strings.size() * sizeof(char *));
  for (auto i = 0; i < strings.size(); ++i) {
    cStrings[i] = strdup(strings[i].c_str());
  }
  return { cStrings, strings.size() };
}

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
  if (Error err = arch.takeError()) {
    return strdup(errorToErrorCode(std::move(err)).message().c_str());
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

LLVMExecutionEngineRef LLVMCreateOrcMCJITReplacement(LLVMModuleRef module, LLVMTargetMachineRef targetRef) {
  auto target = reinterpret_cast<TargetMachine *>(targetRef);
  EngineBuilder builder(std::unique_ptr<Module>(unwrap(module)));
  builder.setMCJITMemoryManager(make_unique<SectionMemoryManager>());
  builder.setErrorStr(&GlobalJITError);
  builder.setTargetOptions(target->Options);
  builder.setUseOrcMCJITReplacement(true);
  return wrap(builder.create());
}

RawOptions ParseArguments(int argc, char **argv) {
  cl::opt<bool> emitAST("emit-ast", cl::desc("Emit the AST to stdout"));
  cl::opt<OptimizationLevel> optimizationLevel(cl::desc("Choose optimization level:"),
                                               cl::values(clEnumVal(O0 , "No optimizations, enable debugging"),
                                                          clEnumVal(O1, "Enable trivial optimizations"),
                                                          clEnumVal(O2, "Enable default optimizations"),
                                                          clEnumVal(O3, "Enable expensive optimizations"),
                                                          clEnumValEnd));
  cl::opt<bool> emitLLVM("emit-llvm", cl::desc("Emit the generated LLVM IR"));
  cl::opt<bool> emitASM("emit-asm", cl::desc("Emit the generated assembly"));
  cl::opt<bool> emitObject("emit-object", cl::desc("Emit the generated object file"));
  cl::opt<bool> jit("run", cl::desc("JIT the specified files"));
  cl::opt<bool> emitJS("emit-js", cl::desc("Emit the generated JavaScript to stdout"));
  cl::opt<bool> jsonDiagnostics("json-diagnostics", cl::desc("Emit diagnostics as JSON"));
  cl::opt<bool> emitTiming("emit-timing", cl::desc("Emit pass times (for performance debugging)"));
  cl::opt<bool> prettyPrint("pretty-print", cl::desc("Emit pretty-printed AST"));
  cl::opt<bool> onlyDiagnostics("only-diagnostics", cl::desc("Only emit diagnostics"));
  cl::opt<std::string> target("target", cl::desc("Override the LLVM target machine"));
  cl::opt<std::string> outputFile("o", cl::desc("output-filename"));
  cl::list<std::string> filenames(cl::Positional, cl::desc("<filenames>"));
  cl::list<std::string> linkerFlags("Xlinker", cl::Positional,
                                    cl::PositionalEatsArgs,
                                    cl::desc("<extra linker flags>"));
  cl::list<std::string> ccFlags("Xcc", cl::Positional,
                                cl::PositionalEatsArgs,
                                cl::desc("<extra clang flags>"));
  cl::ParseCommandLineOptions(argc, argv);
  
  RawMode mode;
  if (onlyDiagnostics) {
    mode = OnlyDiagnostics;
  } else if (emitLLVM) {
    mode = EmitLLVM;
  } else if (emitJS) {
    mode = EmitJavaScript;
  } else if (emitAST) {
    mode = EmitAST;
  } else if (emitASM) {
    mode = EmitASM;
  } else if (prettyPrint) {
    mode = PrettyPrint;
  } else if (jit) {
    mode = JIT;
  } else if (emitObject) {
    mode = EmitObj;
  } else {
    mode = EmitBinary;
  }
  
  bool importC = mode != EmitJavaScript && mode != PrettyPrint;
  
  auto outputFilename = outputFile.empty() ? nullptr : strdup(outputFile.c_str());
  auto targetMachine = target.empty() ? nullptr : strdup(target.c_str());
  bool isStdin = filenames.size() == 1 && filenames[0] == "-";
  
  auto filenamesPair = toCStrings(filenames);
  auto linkerPair = toCStrings(linkerFlags);
  auto ccPair = toCStrings(ccFlags);
  
  return RawOptions {
    optimizationLevel,
    importC,
    emitTiming,
    isStdin,
    jsonDiagnostics,
    mode,
    targetMachine,
    outputFilename,
    filenamesPair.first,
    filenamesPair.second,
    linkerPair.first,
    linkerPair.second,
    ccPair.first,
    ccPair.second
  };
}

void DestroyRawOptions(RawOptions options) {
  free(options.outputFilename);
  free(options.target);
  for (auto i = 0; i < options.filenameCount; ++i) {
    free(options.filenames[i]);
  }
  free(options.filenames);
}

int clang_linkExecutableFromObject(const char *targetTriple,
                                   const char *filename,
                                   char **linkerFlags,
                                   size_t linkerFlagsCount,
                                   char **ccFlags,
                                   size_t ccFlagsCount) {
  std::string inputPath(filename);
  std::string outputPath = sys::path::stem(inputPath);
  auto clangPath = sys::findProgramByName("clang");
  if (auto err = clangPath.getError()) {
    return err.value();
  }
  std::vector<const char *> args {
    clangPath->c_str(),
    inputPath.c_str(),
    "-l", "c++",
    "-l", "gc",
    "-l", "trillRuntime",
    "-L", "/usr/local/lib",
    "-o", outputPath.c_str(),
  };
  for (auto flag : ArrayRef<char *>(ccFlags, ccFlagsCount)) {
    args.push_back(flag);
  }
  if (linkerFlagsCount > 0) {
    args.push_back("-Xlinker");
    SmallString<20> linkerFlag;
    for (size_t i = 0; i < linkerFlagsCount; ++i) {
      linkerFlag += linkerFlags[i];
      if (i < linkerFlagsCount - 1) {
        linkerFlag += ' ';
      }
    }
    args.push_back(linkerFlag.c_str());
  }
  auto options = new clang::DiagnosticOptions();
  auto diagClient = new clang::TextDiagnosticPrinter(llvm::errs(),
                                                     options);
  auto diagID = new clang::DiagnosticIDs();
  clang::DiagnosticsEngine diags(diagID, options, diagClient);
  
  clang::driver::Driver driver(args[0], targetTriple, diags);
  auto compilation = driver.BuildCompilation(args);
  if (!compilation)
    return 1;
  
  auto failingCommands =
    SmallVector<std::pair<int, const clang::driver::Command *>, 1>();
  int result = driver.ExecuteCompilation(*compilation, failingCommands);
  if (result < 0) {
    driver.generateCompilationDiagnostics(*compilation, *failingCommands[0].second);
    return 1;
  }
  
  if (auto err = llvm::sys::fs::remove(inputPath)) {
    return err.value();
  }
  
  return 0;
}
