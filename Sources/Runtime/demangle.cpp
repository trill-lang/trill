//
//  demangle.cpp
//  Trill
//

#include "demangle.h"
#include <assert.h>
#include <cstdlib>
#include <string>
#include <vector>

namespace trill {
bool readNum(std::string &str, int &out) {
  char *end;
  const char *start = str.c_str();
  int num = (int)strtol(start, &end, 10);
  if (end == start) { return false; }
  str.erase(0, end - start);
  out = num;
  return true;
}

bool readName(std::string &str, std::string &out) {
  int num = 0;
  if (!readNum(str, num)) { return false; }
  if (str.size() < num) { return false; }
  out += str.substr(0, num);
  str.erase(0, num);
  return true;
}

bool readType(std::string &str, std::string &out) {
  if (str.front() == 'P') {
    str.erase(0, 1);
    int num;
    if (!readNum(str, num)) { return false; }
    out += std::string(num, '*');
    if (str.front() != 'T') { return false; }
    str.erase(0, 1);
  }
  if (str.front() == 'F') {
    str.erase(0, 1);
    out += '(';
    std::vector<std::string> argNames;
    while (str.front() != 'R') {
      std::string name;
      if (!readType(str, name)) { return false; }
      argNames.push_back(name);
    }
    str.erase(0, 1);
    for (auto i = 0; i < argNames.size(); ++i) {
      out += argNames[i];
      if (i < argNames.size() - 1) {
        out += ", ";
      }
    }
    out += ") -> ";
    if (!readType(str, out)) { return false; }
  } else if (str.front() == 'A') {
    str.erase(0, 1);
    std::string underlying;
    if (!readType(str, underlying)) { return false; }
    out += "[" + underlying + "]";
  } else if (str.front() == 't') {
    str.erase(0, 1);
    out += '(';
    std::vector<std::string> fieldNames;
    while (str.front() != 'T') {
      std::string name;
      if (!readType(str, name)) { return false; }
      fieldNames.push_back(name);
    }
    str.erase(0, 1);
    for (auto i = 0; i < fieldNames.size(); ++i) {
      out += fieldNames[i];
      if (i < fieldNames.size() - 1) {
        out += ", ";
      }
    }
    out += ')';
  } else if (str.front() == 's') {
    str.erase(0, 1);
    switch (str.front()) {
    case 'i':
      str.erase(0, 1);
      out += "Int";
      int num;
      if (readNum(str, num)) {
        out += std::to_string(num);
      }
      break;
#define SPECIAL_TYPE(c, name) \
    case c:                   \
      str.erase(0, 1);        \
      out += name;            \
      break;
#include "SpecialTypes.def"
    default:
      return false;
    }
  } else {
    if (!readName(str, out)) { return false; }
  }
  return true;
}

bool readArg(std::string &str, std::string &out) {
  std::string external = "";
  std::string internal = "";
  auto isSingleName = false;
  if (str.front() == 'S') {
    str.erase(0, 1);
    isSingleName = true;
  } else if (str.front() == 'E') {
    str.erase(0, 1);
    if (!readName(str, external)) { return false; }
  }
  if (!readName(str, internal)) { return false; }
  std::string type;
  if (!readType(str, type)) { return false; }
  if (!isSingleName) {
    if (external.empty()) {
      external = "_";
    }
    out += external + " ";
  }
  out += internal + ": ";
  out += type;
  return true;
}

bool demangleFunction(std::string &symbol, std::string &out) {
  symbol.erase(0, 1);
  if (symbol.front() == 'D') {
    symbol.erase(0, 1);
    if (!readType(symbol, out)) { return false; }
    out += ".deinit";
  } else {
    if (symbol.front() == 'M') {
      symbol.erase(0, 1);
      if (!readType(symbol, out)) { return false; }
      out += '.';
      if (!readName(symbol, out)) { return false; }
    } else if (symbol.front() == 'm') {
      symbol.erase(0, 1);
      out += "static ";
      if (!readType(symbol, out)) { return false; }
      out += '.';
      if (!readName(symbol, out)) { return false; }
    } else if (symbol.front() == 'g') {
      symbol.erase(0, 1);
      out += "getter for ";
      if (!readType(symbol, out)) { return false; }
      out += '.';
      if (!readName(symbol, out)) { return false; }
      out += ": ";
      if (!readType(symbol, out)) { return false; }
      return true;
    } else if (symbol.front() == 's') {
      symbol.erase(0, 1);
      out += "setter for ";
      if (!readType(symbol, out)) { return false; }
      out += '.';
      if (!readName(symbol, out)) { return false; }
      out += ": ";
      if (!readType(symbol, out)) { return false; }
      return true;
    } else if (symbol.front() == 'I') {
      symbol.erase(0, 1);
      if (!readType(symbol, out)) { return false; }
      out += ".init";
    } else if (symbol.front() == 'S') {
      symbol.erase(0, 1);
      if (!readType(symbol, out)) { return false; }
      out += ".subscript";
    } else if (symbol.front() == 'O') {
      symbol.erase(0, 1);
      switch (symbol.front()) {
#define MANGLED_OPERATOR(c, str) \
      case c:                    \
        out += str;              \
        break;
#include "MangledOperators.def"
      default: return false;
      }
      symbol.erase(0, 1);
    } else {
      if (!readName(symbol, out)) { return false; }
    }
    out += '(';
    std::vector<std::string> args;
    while (!symbol.empty() && symbol.front() != 'R') {
      std::string arg;
      if (!readArg(symbol, arg)) { return false; }
      args.push_back(arg);
    }
    for (auto i = 0; i < args.size(); ++i) {
      out += args[i];
      if (i < args.size() - 1) {
        out += ", ";
      }
    }
    out += ')';
    if (symbol.front() == 'R') {
      symbol.erase(0, 1);
      std::string type;
      if (!readType(symbol, type)) { return false; }
      out += " -> " + type;
    }
    if (symbol.front() == 'C') {
      symbol.erase(0, 1);
      out += " (closure #1)";
    }
  }
  return true;
}

bool demangleType(std::string &symbol, std::string &out) {
  symbol.erase(0, 1);
  return readType(symbol, out);
}
  
bool demangleGlobal(std::string &symbol, std::string &out, const char *kind) {
  symbol.erase(0, 1);
  out += kind;
  out += " for global ";
  if (!readName(symbol, out)) { return false; }
  return true;
}

bool demangleWitnessTable(std::string &symbol, std::string &out) {
  symbol.erase(0, 1);
  out += "witness table for ";
  if (!readName(symbol, out)) { return false; }
  out += " to ";
  if (!readName(symbol, out)) { return false; }
  return true;
}

bool demangleClosure(std::string &symbol, std::string &out) {
  assert(false && "closure demangling is unimplemented");
  return false;
}

bool demangleProtocol(std::string &symbol, std::string &out) {
  symbol.erase(0, 1);
  out += "protocol ";
  if (!readName(symbol, out)) { return false; }
  return true;
}

bool demangle(std::string &symbol, std::string &out) {
  if (symbol.substr(0, 2) == "_W") {
    symbol.erase(0, 2);
  } else if (symbol.substr(0, 3) == "__W") {
    symbol.erase(0, 3);
  } else {
    return false;
  }
  switch (symbol.front()) {
  case 'C':
    return demangleClosure(symbol, out);
  case 'F':
    return demangleFunction(symbol, out);
  case 'T':
      return demangleType(symbol, out);
  case 'g':
    return demangleGlobal(symbol, out, "accessor");
  case 'G':
    return demangleGlobal(symbol, out, "initializer");
  case 'W':
    return demangleWitnessTable(symbol, out);
  case 'P':
    return demangleProtocol(symbol, out);
  }
  return false;
}

char *trill_demangle(const char *symbol) {
  std::string sym(symbol);
  std::string out;
  if (!demangle(sym, out)) {
    return nullptr;
  }
  return strdup(out.c_str());
}

}
