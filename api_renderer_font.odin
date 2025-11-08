package main

import "base:runtime"

import "umka"

f_load :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	filename := cstring(umka.GetParam(params, 0).ptrVal)
	size := f32(umka.GetParam(params, 1).realVal)
	self: ^RenFont
	self = ren_load_font(filename, size)
	if (self != nil) {
		umka.GetResult(params, result).ptrVal = &self
	}
}

f_set_tab_width :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	self := (^^RenFont)(umka.GetParam(params, 0).ptrVal)
	n := umka.GetParam(params, 1).intVal
	ren_set_font_tab_width(self^, i32(n))
}

f_gc :: proc "c" (params, result: ^umka.StackSlot) {
	self := (^^RenFont)(umka.GetParam(params, 0).ptrVal)
	context = runtime.default_context()
	if (self^ != nil) {rencache_free_font(self^)}
}


f_get_width :: proc "c" (params, result: ^umka.StackSlot) {
	self := (^^RenFont)(umka.GetParam(params, 0).ptrVal)
	text := cstring(umka.GetParam(params, 1).ptrVal)
	context = runtime.default_context()
	w := ren_get_font_width(self^, text)
	umka.GetResult(params, result).intVal = i64(w)
}


f_get_height :: proc "c" (params, result: ^umka.StackSlot) {
	self := (^^RenFont)(umka.GetParam(params, 0).ptrVal)
	h := ren_get_font_height(self^)
	umka.GetResult(params, result).intVal = i64(h)
}

