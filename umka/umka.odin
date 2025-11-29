package umka

import "base:intrinsics"
import "core:c"

UMKA_SHARED :: #config(UMKA_SHARED, false)

when ODIN_DEBUG {
	when ODIN_OS == .Linux {
		foreign import lib {"linux/libumka_debug.so" when UMKA_SHARED else "linux/libumka_static_linux_debug.a"}
	} else {
		#panic("This OS is not supported")
	}
} else {
	when ODIN_OS == .Linux {
		foreign import lib {"linux/libumka.so" when UMKA_SHARED else "linux/libumka_static_linux.a"}
	} else when ODIN_OS == .Windows {
		foreign import lib {"windows/libumka.dll" when UMKA_SHARED else "windows/libumka_static.lib"}
	} else {
		#panic("This OS is not supported")
	}
}

StackSlot :: struct #raw_union {
	intVal:    i64,
	uintVal:   u64,
	ptrVal:    rawptr,
	realVal:   f64,
	real32Val: f32,
}

FuncContext :: struct {
	entryOffset: i64,
	params:      ^StackSlot,
	result:      ^StackSlot,
}

ExternFunc :: #type proc "c" (params: ^StackSlot, result: ^StackSlot)

HookEvent :: enum c.int {
	UMKA_HOOK_CALL,
	UMKA_HOOK_RETURN,
	UMKA_NUM_HOOKS,
}

HookFunc :: #type proc "c" (fileName: cstring, funcName: cstring, line: c.int)

Type :: struct {}

DynArray :: struct($T: typeid) {
	type:     ^Type,
	itemSize: i64,
	data:     [^]T,
}

Map :: struct {
	type: ^Type,
	root: ^rawptr,
}

Any :: struct {}
// Any :: struct {
// 	_: struct #raw_union {
// 		data: rawptr,
// 		self: rawptr,
// 	},
// 	_: struct #raw_union {
// 		type:     ^Type,
// 		selfType: ^Type,
// 	},
// }

Str :: [^]c.char

Closure :: struct {
	entryOffset: i64,
	upvalue:     Any,
}

Error :: struct {
	fileName:        cstring,
	fnName:          cstring,
	line, pos, code: c.int,
	msg:             cstring,
}

WarningCallback :: #type proc "c" (warning: ^Error)

Context :: distinct rawptr

@(default_calling_convention = "c", link_prefix = "umka")
foreign lib {
	Alloc :: proc() -> Context ---
	Init :: proc(U: Context, fileName: cstring, sourceString: cstring, stackSize: c.int, reserved: rawptr, argc: c.int, argv: [^]^c.char, fileSystemEnabled: c.bool, implLibsEnabled: c.bool, warningCallback: WarningCallback) -> c.bool ---
	Compile :: proc(U: Context) -> c.bool ---
	Run :: proc(U: Context) -> c.int ---
	Call :: proc(U: Context, fn: ^FuncContext) -> c.int ---
	Free :: proc(U: Context) ---
	GetError :: proc(U: Context) -> ^Error ---
	Alive :: proc(U: Context) -> c.bool ---
	Asm :: proc(U: Context) -> [^]c.char ---
	AddModule :: proc(U: Context, fileName: cstring, sourceString: cstring) -> c.bool ---
	AddFunc :: proc(U: Context, name: cstring, func: ExternFunc) -> c.bool ---
	GetFunc :: proc(U: Context, moduleName: cstring, fnName: cstring, fn: ^FuncContext) -> c.bool ---
	GetCallStack :: proc(U: Context, depth: c.int, nameSize: c.int, offset: ^c.int, fileName: [^]c.char, fnName: [^]c.char, line: ^c.int) -> c.bool ---
	SetHook :: proc(U: Context, event: HookEvent, hook: HookFunc) ---
	AllocData :: proc(U: Context, size: c.int, onFree: ExternFunc) -> rawptr ---
	IncRef :: proc(U: Context, ptr: rawptr) ---
	DecRef :: proc(U: Context, ptr: rawptr) ---
	GetMapItem :: proc(U: Context, collection: ^Map, key: StackSlot) -> rawptr ---
	MakeStr :: proc(U: Context, str: cstring) -> [^]c.char ---
	GetStrLen :: proc(str: cstring) -> c.int ---
	MakeDynArray :: proc(U: Context, array: rawptr, type: ^Type, len: c.int) ---
	GetDynArrayLen :: proc(array: rawptr) -> c.int ---
	GetVersion :: proc() -> cstring ---
	GetMemUsage :: proc(U: Context) -> i64 ---
	MakeFuncContext :: proc(U: Context, closureType: ^Type, entryOffset: c.int, fn: ^FuncContext) ---
	GetParam :: proc(params: ^StackSlot, index: c.int) -> ^StackSlot ---
	GetUpvalue :: proc(params: ^StackSlot) -> ^Any ---
	GetResult :: proc(params: ^StackSlot, result: ^StackSlot) -> ^StackSlot ---
	GetMetadata :: proc(U: Context) -> rawptr ---
	SetMetadata :: proc(U: Context, metadata: rawptr) ---
	MakeStruct :: proc(U: Context, type: ^Type) -> rawptr ---
	GetBaseType :: proc(type: ^Type) -> ^Type ---
	GetParamType :: proc(params: ^StackSlot, index: c.int) -> ^Type ---
	GetResultType :: proc(params: ^StackSlot, result: ^StackSlot) -> ^Type ---
	GetFieldType :: proc(structType: ^Type, fieldName: cstring) -> ^Type ---
	GetMapKeyType :: proc(mapType: ^Type) -> ^Type ---
	GetMapItemType :: proc(mapType: ^Type) -> ^Type ---
}

GetInstance :: #force_inline proc "contextless" (result: ^StackSlot) -> Context {
	return (Context)(result.ptrVal)
}


// macros

SetStackSlotValue :: #force_inline proc(slot: ^StackSlot, value: $T) {
	when intrinsics.type_is_integer(T) {
		when intrinsics.type_is_unsigned(T) {
			slot.uintVal = u64(value)
		} else {
			slot.intVal = i64(value)
		}
	} else when intrinsics.type_is_float(T) {
		when intrinsics.type_is_subtype_of(T, f32) {
			slot.real32Val = f32(value)
		} else {
			slot.realVal = f64(value)
		}
	} else when intrinsics.type_is_pointer(T) {
		slot.ptrVal = rawptr(value)
	} else {
		#panic("Unsupported type. Maybe try pointer.")
	}
}

GetStackSlotValue :: #force_inline proc(slot: ^StackSlot, $T: typeid) -> T {
	when intrinsics.type_is_integer(T) {
		when intrinsics.type_is_unsigned(T) {
			return T(slot.uintVal)
		} else {
			return T(slot.intVal)
		}
	} else when intrinsics.type_is_float(T) {
		when intrinsics.type_is_subtype_of(T, f32) {
			return T(slot.real32Val)
		} else {
			return T(slot.realVal)
		}
	} else when intrinsics.type_is_pointer(T) {
		return (T)(slot.ptrVal)
	} else {
		#panic("Unsupported type. Maybe try pointer.")
	}
}

SetFuncParam :: #force_inline proc(fn: ^FuncContext, index: int, value: $T) {
	param := GetParam(fn.params, c.int(index))
	if param != nil do SetStackSlotValue(param, value)
}

SetFuncResult :: #force_inline proc(fn: ^FuncContext, result: $T) {
	when intrinsics.type_is_pointer(T) {
		GetResult(fn.params, fn.result).ptrVal = rawptr(result)
	} else {
		#panic("result type must be a pointer")
	}
}

GetFuncResult :: #force_inline proc(fn: ^FuncContext, $T: typeid) -> T {
	result := GetResult(fn.params, fn.result)
	return GetStackSlotValue(result, T)
}

// only works if it is single return of dyn array type
FillResultDynArray :: #force_inline proc(
	U: Context,
	params, result: ^StackSlot,
	array: ^$T/[dynamic]$E,
) {
	res := (^DynArray(E))(GetResult(params, result).ptrVal)
	rtype := GetResultType(params, result)
	n := len(array)
	MakeDynArray(U, res, rtype, i32(n))
	_ = runtime.copy_slice_raw(res.data, raw_data(array^), n, n, size_of(E))
}

