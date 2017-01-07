//
//  LLVMType.swift
//  Trill
//

import Foundation

protocol LLVMType {
    func asLLVM() -> LLVMTypeRef
}

extension LLVMType {
    func dump() {
        LLVMDumpType(asLLVM())
    }
}

internal func convertType(_ type: LLVMTypeRef) -> LLVMType {
    switch LLVMGetTypeKind(type) {
    case LLVMVoidTypeKind: return VoidType()
    case LLVMHalfTypeKind: return FloatType.half
    case LLVMFloatTypeKind: return FloatType.float
    case LLVMDoubleTypeKind: return FloatType.double
    case LLVMX86_FP80TypeKind: return FloatType.x86FP80
    case LLVMFP128TypeKind: return FloatType.fp128
    case LLVMPPC_FP128TypeKind: return FloatType.fp128
    case LLVMLabelTypeKind: return LabelType()
    case LLVMIntegerTypeKind:
        let width = LLVMGetIntTypeWidth(type)
        return IntType(width: Int(width))
    case LLVMFunctionTypeKind:
        var params = [LLVMType]()
        let count = Int(LLVMCountParamTypes(type))
        let paramsPtr = UnsafeMutablePointer<LLVMTypeRef?>.allocate(capacity: count)
        defer { free(paramsPtr) }
        LLVMGetParamTypes(type, paramsPtr)
        for i in 0..<count {
            let ty = paramsPtr[i]!
            params.append(convertType(ty))
        }
        let ret = convertType(LLVMGetReturnType(type))
        let isVarArg = LLVMIsFunctionVarArg(type) != 0
        return FunctionType(argTypes: params, returnType: ret, isVarArg: isVarArg)
    case LLVMStructTypeKind:
        var elements = [LLVMType]()
        let count = Int(LLVMCountStructElementTypes(type))
        let elementsPtr = UnsafeMutablePointer<LLVMTypeRef?>.allocate(capacity: count)
        defer { free(elementsPtr) }
        LLVMGetStructElementTypes(type, elementsPtr)
        for i in 0..<count {
            let ty = elementsPtr[i]!
            elements.append(convertType(ty))
        }
        let isPacked = LLVMIsPackedStruct(type) != 0
        return StructType(elementTypes: elements, packed: isPacked)
    case LLVMArrayTypeKind:
        let elementType = convertType(LLVMGetElementType(type))
        let count = Int(LLVMGetArrayLength(type))
        return ArrayType(elementType: elementType, count: count)
    case LLVMPointerTypeKind:
        let pointee = convertType(LLVMGetElementType(type))
        let addressSpace = Int(LLVMGetPointerAddressSpace(type))
        return PointerType(pointee: pointee, addressSpace: addressSpace)
    case LLVMVectorTypeKind:
        let elementType = convertType(LLVMGetElementType(type))
        let count = Int(LLVMGetVectorSize(type))
        return VectorType(elementType: elementType, count: count)
    case LLVMMetadataTypeKind:
        return MetadataType(llvm: type)
    case LLVMX86_MMXTypeKind:
        return X86MMXType()
    case LLVMTokenTypeKind:
        return TokenType(llvm: type)
    default: fatalError("unknown type kind for type \(type)")
    }
}

struct VoidType: LLVMType {
    func asLLVM() -> LLVMTypeRef {
        return LLVMVoidType()
    }
}

struct IntType: LLVMType {
    let width: Int
    
    static let int1 = IntType(width: 1)
    static let int8 = IntType(width: 8)
    static let int16 = IntType(width: 16)
    static let int32 = IntType(width: 32)
    static let int64 = IntType(width: 64)
    static let int128 = IntType(width: 128)
    
    func constant(_ value: UInt64, signExtend: Bool = false) -> LLVMValueRef {
        return LLVMConstInt(asLLVM(), value, signExtend.llvm)
    }
    
    func asLLVM() -> LLVMTypeRef {
        return LLVMIntType(UInt32(width))
    }
}

struct ArrayType: LLVMType {
    let elementType: LLVMType
    let count: Int
    func asLLVM() -> LLVMTypeRef {
        return LLVMArrayType(elementType.asLLVM(), UInt32(count))
    }
}

struct MetadataType: LLVMType {
    let llvm: LLVMTypeRef
    func asLLVM() -> LLVMTypeRef {
        return llvm
    }
}

struct LabelType: LLVMType {
    func asLLVM() -> LLVMTypeRef {
        return LLVMLabelType()
    }
}

enum FloatType: LLVMType {
    case half, float, double, x86FP80, fp128, ppcFP128
    
    func asLLVM() -> LLVMTypeRef {
        switch self {
        case .half: return LLVMHalfType()
        case .float: return LLVMFloatType()
        case .double: return LLVMDoubleType()
        case .x86FP80: return LLVMX86FP80Type()
        case .fp128: return LLVMFP128Type()
        case .ppcFP128: return LLVMPPCFP128Type()
        }
    }
}

struct PointerType: LLVMType {
    let pointee: LLVMType
    let addressSpace: Int
    init(pointee: LLVMType, addressSpace: Int = 0) {
        self.pointee = pointee
        self.addressSpace = addressSpace
    }
    
    func asLLVM() -> LLVMTypeRef {
        return LLVMPointerType(pointee.asLLVM(), UInt32(addressSpace))
    }
}

struct FunctionType: LLVMType {
    let argTypes: [LLVMType]
    let returnType: LLVMType
    let isVarArg: Bool
    
    init(argTypes: [LLVMType], returnType: LLVMType, isVarArg: Bool = false) {
        self.argTypes = argTypes
        self.returnType = returnType
        self.isVarArg = isVarArg
    }
    
    func asLLVM() -> LLVMTypeRef {
        var argLLVMTypes = argTypes.map { $0.asLLVM() as Optional }
        return argLLVMTypes.withUnsafeMutableBufferPointer { buf in
            return LLVMFunctionType(returnType.asLLVM(),
                                    buf.baseAddress,
                                    UInt32(buf.count),
                                    isVarArg.llvm)!
        }
    }
}

struct StructType: LLVMType {
    let elementTypes: [LLVMType]
    let packed: Bool
    func asLLVM() -> LLVMTypeRef {
        var types = elementTypes.map { $0.asLLVM() as Optional }
        return types.withUnsafeMutableBufferPointer { buf in
            return LLVMStructType(buf.baseAddress!, UInt32(elementTypes.count), packed.llvm)
        }
    }
}

struct X86MMXType: LLVMType {
    func asLLVM() -> LLVMTypeRef {
        return LLVMX86MMXType()
    }
}

struct TokenType: LLVMType {
    let llvm: LLVMTypeRef
    func asLLVM() -> LLVMTypeRef {
        return llvm
    }
}

struct VectorType: LLVMType {
    let elementType: LLVMType
    let count: Int
    
    func asLLVM() -> LLVMTypeRef {
        return LLVMVectorType(elementType.asLLVM(), UInt32(count))
    }
}
