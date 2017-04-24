//
//  LLVMWrappers.cpp
//  Trill
//

#include "LLVMWrappers.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"

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

LLVMExecutionEngineRef LLVMCreateOrcMCJITReplacement(LLVMModuleRef module, LLVMTargetMachineRef targetRef) {
  auto target = reinterpret_cast<TargetMachine *>(targetRef);
  target->Options.DebuggerTuning = DebuggerKind::LLDB;
  target->Options.MCOptions.SanitizeAddress = true;
  EngineBuilder builder(std::unique_ptr<Module>(unwrap(module)));
  builder.setMCJITMemoryManager(make_unique<SectionMemoryManager>());
  builder.setTargetOptions(target->Options);
  builder.setUseOrcMCJITReplacement(true);
  return wrap(builder.create());
}

RawOptions ParseArguments(int argc, char **argv) {
  cl::OptionCategory category("trill");
  cl::cat cat(category);
  cl::opt<OptimizationLevel> optimizationLevel(cl::desc("Choose optimization level:"),
                                               cl::values(clEnumVal(O0 , "No optimizations, enable debugging"),
                                                          clEnumVal(O1, "Enable trivial optimizations"),
                                                          clEnumVal(O2, "Enable default optimizations"),
                                                          clEnumVal(O3, "Enable expensive optimizations")), cat);
  cl::opt<RawOutputFormat> emit("emit", cl::desc("Output format to emit"),
                                cl::values(clEnumValN(Binary, "binary", "A binary executable"),
                                           clEnumValN(Object, "object", "An object file that has not been linked (.o)"),
                                           clEnumValN(ASM, "asm", "Assembly for the target (.s)"),
                                           clEnumValN(LLVM, "ir", "Textual LLVM IR (.ll)"),
                                           clEnumValN(Bitcode, "bitcode", "LLVM Bitcode (.bc)"),
                                           clEnumValN(AST, "ast", "A serailized Abstract Syntax Tree"),
                                           clEnumValN(JavaScript, "js", "JavaScript")), cat);
  cl::opt<bool> jit("run", cl::desc("JIT the specified files"), cat);
  cl::opt<bool> parseOnly("parse-only", cl::desc("Only parse, do not run semantic analysis"), cat);
  cl::opt<bool> showImports("show-imports", cl::desc("Show imported items in the AST dump"), cat);
  cl::opt<bool> stdlib("stdlib", cl::desc("Include the trill standard library"), cat);
  stdlib = true;
  cl::opt<bool> jsonDiagnostics("json-diagnostics", cl::desc("Emit diagnostics as JSON"), cat);
  cl::opt<bool> printTiming("debug-print-timing", cl::desc("Emit pass times (for performance debugging)"), cat);
  cl::opt<bool> onlyDiagnostics("diagnostics-only", cl::desc("Only emit diagnostics"), cat);
  cl::opt<std::string> target("target", cl::desc("Override the LLVM target machine"), cat);
  cl::opt<std::string> outputFile("o", cl::desc("Output filename"), cat);
  cl::list<std::string> filenames(cl::Positional, cl::desc("<filenames>"), cat);
  cl::list<std::string> linkerFlags("Xlinker", cl::Positional,
                                    cl::PositionalEatsArgs,
                                    cl::desc("<extra linker flags>"), cat);
  cl::list<std::string> ccFlags("Xcc", cl::Positional,
                                cl::PositionalEatsArgs,
                                cl::desc("<extra clang flags>"), cat);
  cl::list<std::string> jitArgs("args", cl::Positional,
                                cl::PositionalEatsArgs,
                                cl::desc("<JIT arguments>"), cat);
  cl::HideUnrelatedOptions(category);
  cl::ParseCommandLineOptions(argc, argv);
  
  RawMode mode;
  if (onlyDiagnostics) {
    mode = OnlyDiagnostics;
  } else if (jit) {
    mode = RunJIT;
  } else {
    mode = Emit;
  }
  
  RawOutputFormat outputFormat = Binary;
  if (emit.hasArgStr()) {
    outputFormat = emit;
  } else if (mode == Emit) {
    outputFormat = Binary;
  }
  
  bool importC = !(mode == Emit && outputFormat == JavaScript);
  
  auto outputFilename = outputFile.empty() ? nullptr : strdup(outputFile.c_str());
  auto targetMachine = target.empty() ? nullptr : strdup(target.c_str());
  bool isStdin = filenames.size() == 1 && filenames[0] == "-";
  
  auto filenamesPair = toCStrings(filenames);
  auto linkerPair = toCStrings(linkerFlags);
  auto ccPair = toCStrings(ccFlags);
  auto jitPair = toCStrings(jitArgs);
  
  return RawOptions {
    optimizationLevel,
    importC,
    printTiming,
    parseOnly,
    isStdin,
    jsonDiagnostics,
    showImports,
    stdlib,
    mode,
    outputFormat,
    targetMachine,
    outputFilename,
    filenamesPair.first,
    filenamesPair.second,
    linkerPair.first,
    linkerPair.second,
    ccPair.first,
    ccPair.second,
    jitPair.first,
    jitPair.second
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
                                   const char *runtimeFrameworkPath,
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
    "-framework", "trillRuntime",
    "-F", runtimeFrameworkPath,
    "-rpath", runtimeFrameworkPath,
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
