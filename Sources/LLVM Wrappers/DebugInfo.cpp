//
//  DebugInfo.cpp
//  Trill
//
//  Created by Harlan Haskins on 8/31/16.
//  Copyright © 2016 Harlan. All rights reserved.
//

#include "DebugInfo.h"
#include "llvm/Support/Path.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/DebugInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/DIBuilder.h"

namespace llvm {
namespace dwarf {
  const unsigned DW_LANG_TRILL = 0xabcd;
}
}

using namespace llvm;

class DebugInfoBuilder {
  Module *module;
  DIBuilder *builder;
  DataLayout *layout;
  StringMap<DICompileUnit *> compileUnits;
  DenseMap<Type *, DIType *> typeCache;
  DenseMap<Function *, DISubprogram *> functionCache;

public:
  DebugInfoBuilder(Module *module): module(module),
    builder(new DIBuilder(*module)),
    layout(new DataLayout(module)) {}
  
  DICompileUnit *getOrCreateCompileUnit(StringRef filename) {
    auto it = compileUnits.find(filename);
    if (it != compileUnits.end()) {
      return it->getValue();
    }
    auto dir = llvm::sys::path::parent_path(filename);
    auto base = llvm::sys::path::filename(filename);
    auto unit = builder->createCompileUnit(dwarf::DW_LANG_TRILL,
                                           base, dir, "trill", false, "", 0);
    compileUnits[filename] = unit;
    return unit;
  }
  
  DIType *getOrCreateType(Type *type, RawSourceLocation loc) {
    auto it = typeCache.find(type);
    if (it != typeCache.end()) {
      return it->getSecond();
    }
    return createType(type, loc);
  }
  
  DISubprogram *getOrCreateFunction(Function *function,
                                    StringRef prettyName,
                                    RawSourceLocation loc) {
    auto it = functionCache.find(function);
    if (it != functionCache.end()) {
      return it->getSecond();
    }
    return createFunction(function, prettyName, loc);
  }
  
  ~DebugInfoBuilder() {
    delete builder;
    delete layout;
  }
private:
  DISubprogram *createFunction(Function *function,
                               StringRef prettyName,
                               RawSourceLocation loc) {
    auto unit = getOrCreateCompileUnit(loc.file);
    auto ty = dyn_cast<DISubroutineType>(getOrCreateType(function->getType(), loc));
    auto fn = builder->createFunction(unit->getFile(),
                                      prettyName,
                                      function->getName(),
                                      unit->getFile(),
                                      loc.line,
                                      ty,
                                      true, true, loc.line);
    return fn;
  }
  DIType *createType(Type *type, RawSourceLocation loc) {
    auto unit = getOrCreateCompileUnit(loc.file);
    switch (type->getTypeID()) {
      case Type::VoidTyID:
        return builder->createBasicType("Void", 0, 0, 0);
      case Type::IntegerTyID: {
        std::string name = "Int";
        if (type->getIntegerBitWidth() == 1) {
          name = "Bool";
        } else {
          name += std::to_string(type->getIntegerBitWidth());
        }
        return builder->createBasicType(name, type->getIntegerBitWidth(), 0, 0);
      }
      case Type::PointerTyID: {
        auto eltType = type->getPointerElementType();
        auto eltDIType = getOrCreateType(eltType, loc);
        return builder->createPointerType(eltDIType,
                                          eltType->getPrimitiveSizeInBits());
      }
      case Type::FunctionTyID: {
        auto funcTy = dyn_cast<FunctionType>(type);
        SmallVector<Metadata *, 8> elements;
        elements.push_back(getOrCreateType(funcTy->getReturnType(), loc));
        for (int i = 0; i < funcTy->getNumParams(); ++i) {
          elements.push_back(getOrCreateType(funcTy->getParamType(i), loc));
        }
        
        return builder->createSubroutineType(
            builder->getOrCreateTypeArray(elements));
      }
      case Type::StructTyID: {
        auto structTy = dyn_cast<StructType>(type);
        auto structLayout = layout->getStructLayout(structTy);
        
        auto replaceableFwdDecl =
          builder->createReplaceableCompositeType(dwarf::DW_TAG_structure_type,
                                                  "", unit->getFile(),
                                                  unit->getFile(), dwarf::DW_LANG_TRILL,
                                                  structLayout->getSizeInBits(),
                                                  structLayout->getAlignment(), 0, 0);
        auto fwdDecl = llvm::TempDIType(replaceableFwdDecl);
        typeCache[type] = fwdDecl.get();
        SmallVector<Metadata *, 10> elements;
        for (int i = 0; i < structTy->getNumElements(); ++i) {
          auto eltTy = structTy->getElementType(i);
          auto eltAlign = layout->getPrefTypeAlignment(eltTy);
          auto eltDiTy = builder->createMemberType(unit->getFile(),
                                                   "", unit->getFile(),
                                                   loc.line,
                                                   eltTy->getPrimitiveSizeInBits(),
                                                   eltAlign,
                                                   structLayout->getElementOffset(i),
                                                   0, getOrCreateType(eltTy, loc));
          elements.push_back(eltDiTy);
        }
        auto nodeArray = builder->getOrCreateArray(elements);
        auto result = builder->createStructType(unit->getFile(),
                                                type->getStructName(),
                                                unit->getFile(), loc.line,
                                                structLayout->getSizeInBits(),
                                                structLayout->getAlignment(),
                                                0, nullptr, nodeArray);
        builder->replaceTemporary(std::move(fwdDecl), result);
        return result;
      }
      default:
        return nullptr;
    }
  }
};

DebugInfoBuilderRef wrap(DebugInfoBuilder *builder) {
  return reinterpret_cast<DebugInfoBuilderRef>(builder);
}

DebugInfoBuilder *unwrap(DebugInfoBuilderRef builder) {
  return reinterpret_cast<DebugInfoBuilder *>(builder);
}

DebugInfoBuilderRef LLVMCreateDebugInfoBuilder(LLVMModuleRef moduleRef) {
  auto module = reinterpret_cast<Module *>(moduleRef);
  auto builder = new DebugInfoBuilder(module);
  return wrap(builder);
}

void LLVMCreateTypeDebugInfo(DebugInfoBuilderRef builderRef,
                             LLVMTypeRef typeRef, RawSourceLocation loc) {
  auto type = unwrap(typeRef);
  auto builder = unwrap(builderRef);
  builder->getOrCreateType(type, loc);
}

void LLVMCreateFunctionDebugInfo(DebugInfoBuilderRef builderRef,
                                 LLVMValueRef functionRef,
                                 const char *prettyName,
                                 RawSourceLocation loc) {
  auto function = dyn_cast<Function>(unwrap(functionRef));
  auto builder = unwrap(builderRef);
  builder->getOrCreateFunction(function, prettyName, loc);
}

void DestroyDebugInfoBuilder(DebugInfoBuilderRef builderRef) {
  auto builder = unwrap(builderRef);
  delete builder;
}
