package main

import "base:runtime"
import "core:strings"
import "core:text/match"

import "umka"

// umka module for lua-like(not exact) string matching and string functions

f_lower :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	U := umka.GetInstance(result)
	text := cstring(umka.GetParam(params, 0).ptrVal)
	lower := strings.to_lower(string(text), context.temp_allocator)
	lower_c := strings.unsafe_string_to_cstring(lower)
	umka.GetResult(params, result).ptrVal = rawptr(umka.MakeStr(U, lower_c))
}

f_upper :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	U := umka.GetInstance(result)
	text := cstring(umka.GetParam(params, 0).ptrVal)
	upper := strings.to_upper(string(text), context.temp_allocator)
	upper_c := strings.unsafe_string_to_cstring(upper)
	umka.GetResult(params, result).ptrVal = rawptr(umka.MakeStr(U, upper_c))
}

f_rfind :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	U := umka.GetInstance(result)
	text := cstring(umka.GetParam(params, 0).ptrVal)
	pattern := cstring(umka.GetParam(params, 1).ptrVal)
	offset := umka.GetParam(params, 2).intVal
	dtype := (^umka.Type)(umka.GetParam(params, 3).ptrVal)

	Capture :: struct {
		s, e: i64,
	}
	captures: [dynamic]Capture
	ret_offset: i64
	defer delete(captures)
	{
		caps: [match.MAX_CAPTURES]match.Match
		ss := string(text)[offset:]
		_, ok := match.gfind(&ss, string(pattern), &caps)
		if ok {
			for c in caps {
				// NOTE this might not be correct
				if c.byte_start == c.byte_end && c.byte_end == 0 do break
				append(&captures, Capture{offset + i64(c.byte_start), offset + i64(c.byte_end)})
			}
			ret_offset = offset + i64(caps[0].byte_end)
		}
	}

	Result :: struct {
		captures: umka.DynArray(Capture),
		offset:   i64,
	}
	res := (^Result)(umka.GetResult(params, result).ptrVal)
	n := len(captures)
	umka.MakeDynArray(U, &res.captures, dtype, i32(n))
	_ = runtime.copy_slice_raw(res.captures.data, raw_data(captures), n, n, size_of(Capture))
	res.offset = ret_offset
}

f_search :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	text := string(cstring(umka.GetParam(params, 0).ptrVal))
	pattern := cstring(umka.GetParam(params, 1).ptrVal)
	offset := umka.GetParam(params, 2).intVal

	Result :: struct {
		s, e: i64,
		ok:   bool,
	}
	res := (^Result)(umka.GetResult(params, result).ptrVal)
	s := strings.index(text[offset:], string(pattern))
	res.s = offset + i64(s)
	res.e = offset + i64(s + len(pattern))
	res.ok = s != -1
}

f_gsub :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	U := umka.GetInstance(result)
	text := cstring(umka.GetParam(params, 0).ptrVal)
	pattern := cstring(umka.GetParam(params, 1).ptrVal)
	repl := cstring(umka.GetParam(params, 2).ptrVal)
	r := match.gsub(string(text), string(pattern), string(repl), context.temp_allocator)
	res := strings.unsafe_string_to_cstring(r)
	umka.GetResult(params, result).ptrVal = rawptr(umka.MakeStr(U, res))
}

// odinfmt: disable
@(private="file")
regs := [?]FuncReg {
	{"lower",  f_lower  },
	{"upper",  f_upper  },
	{"rfind",  f_rfind  },
	{"search", f_search },
	{"gsub",   f_gsub   },

}
// odinfmt: enable

strings_source := #load("modules/strings.um", cstring)

add_module_strings :: proc(U: umka.Context) -> bool {
	for reg in regs {
		if !umka.AddFunc(U, reg.name, reg.func) do return false
	}
	return umka.AddModule(U, "strings.um", strings_source)
}

