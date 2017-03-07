//
//  runtime.c
//  Trill
//

#include "demangle.h"
#include "runtime.h"
#include <assert.h>
#include <cxxabi.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <inttypes.h>
#include <libgen.h>
#include <mutex>
#include <signal.h>
#include <string>

namespace trill {

#define MAX_STACK_DEPTH 256

std::string demangle(std::string symbol) {
  std::string out;
  if (demangle(symbol, out))
    return out;
  
  int status;
  if (auto result = abi::__cxa_demangle(symbol.c_str(), nullptr, nullptr, &status)) {
    out = result;
    free(result);
    return out;
  }
  out = symbol;
  return out;
}
    
void trill_once(uint64_t *predicate, void (*initializer)()) {
    std::call_once(*reinterpret_cast<std::once_flag *>(predicate), initializer);
}

void trill_printStackTrace() {
  void *symbols[MAX_STACK_DEPTH];
  int frames = backtrace(symbols, MAX_STACK_DEPTH);
  fputs("Current stack trace:\n", stderr);
  for (int i = 0; i < frames; i++) {
    Dl_info handle;
    if (dladdr(symbols[i], &handle) == 0) {
      continue;
    }

    auto copy = strdup(handle.dli_fname); // need to un-const this value
    auto base = basename(copy);
    free(copy);
    
    auto symbol = demangle(handle.dli_sname);
    fprintf(stderr, "%-4d %-34s 0x%016" PRIxPTR " %s + %ld\n", i, base,
            reinterpret_cast<long>(handle.dli_saddr), symbol.c_str(),
            reinterpret_cast<intptr_t>(symbols[i]) -
            reinterpret_cast<intptr_t>(handle.dli_saddr));
  }
}

TRILL_NORETURN
void crash() {
  trill_printStackTrace();
  exit(-1);
}

TRILL_NORETURN
void trill_fatalError(const char *_Nonnull message) {
  fprintf(stderr, "fatal error: %s\n", message);
  crash();
}
  
__attribute__((always_inline))
static void *trill_malloc(size_t size) {
  return malloc(size);
}

void *trill_alloc(size_t size) {
  void *ptr = trill_malloc(size);
  if (!ptr) {
    trill_fatalError("malloc failed");
  }
  memset(ptr, 0, size);
  return ptr;
}

void trill_registerDeinitializer(void *object, void (*deinitializer)(void *)) {
}
  
void trill_handleSignal(int signal) {
  trill_fatalError(strsignal(signal));
}
  
void trill_init() {
  signal(SIGABRT, trill_handleSignal);
  signal(SIGSEGV, trill_handleSignal);
  signal(SIGILL, trill_handleSignal);
}

}
