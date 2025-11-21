package main

import "base:runtime"

import "umka"

fonts: [dynamic]^RenFont

f_load :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	filename := cstring(umka.GetParam(params, 0).ptrVal)
	size := f32(umka.GetParam(params, 1).realVal)
	self := ren_load_font(filename, size)
	if (self != nil) {
		append(&fonts, self)
		umka.GetResult(params, result).intVal = i64(len(fonts) - 1)
	}
}

f_set_tab_width :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	self := fonts[umka.GetParam(params, 0).intVal]
	n := umka.GetParam(params, 1).intVal
	ren_set_font_tab_width(self, i32(n))
}

f_gc :: proc "c" (params, result: ^umka.StackSlot) {
	self := fonts[umka.GetParam(params, 0).intVal]
	context = runtime.default_context()
	if (self != nil) {rencache_free_font(self)}
}


f_get_width :: proc "c" (params, result: ^umka.StackSlot) {
	self := fonts[umka.GetParam(params, 0).intVal]
	text := cstring(umka.GetParam(params, 1).ptrVal)
	context = runtime.default_context()
	w := ren_get_font_width(self, text)
	umka.GetResult(params, result).intVal = i64(w)
}


f_get_height :: proc "c" (params, result: ^umka.StackSlot) {
	self := fonts[umka.GetParam(params, 0).intVal]
	h := ren_get_font_height(self)
	umka.GetResult(params, result).intVal = i64(h)
}

