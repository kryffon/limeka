package main

import "base:runtime"

import "umka"

f_show_debug :: proc "c" (params, result: ^umka.StackSlot) {
	b := (^bool)(umka.GetParam(params, 0).ptrVal)
	rencache_show_debug(b^)
}

f_get_size :: proc "c" (params, result: ^umka.StackSlot) {
	w, h: i32
	ren_get_size(&w, &h)

	Result :: struct {
		w, h: i64,
	}
	res := (^Result)(umka.GetResult(params, result).ptrVal)
	res.w = i64(w)
	res.h = i64(h)
}

f_begin_frame :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	rencache_begin_frame()
}

f_end_frame :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	rencache_end_frame()
}

f_set_clip_rect :: proc "c" (params, result: ^umka.StackSlot) {
	rect: RenRect
	rect.x = i32(umka.GetParam(params, 0).intVal)
	rect.y = i32(umka.GetParam(params, 1).intVal)
	rect.width = i32(umka.GetParam(params, 2).intVal)
	rect.height = i32(umka.GetParam(params, 3).intVal)
	context = runtime.default_context()
	rencache_set_clip_rect(rect)
}

f_draw_rect :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	rect: RenRect
	rect.x = i32(umka.GetParam(params, 0).intVal)
	rect.y = i32(umka.GetParam(params, 1).intVal)
	rect.width = i32(umka.GetParam(params, 2).intVal)
	rect.height = i32(umka.GetParam(params, 3).intVal)
	color := (^RenColor)(umka.GetParam(params, 4).ptrVal)
	rencache_draw_rect(rect, color^)
}

f_draw_text :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	font := (^^RenFont)(umka.GetParam(params, 0).ptrVal)
	text := cstring(umka.GetParam(params, 1).ptrVal)
	x := umka.GetParam(params, 2).realVal
	y := umka.GetParam(params, 3).realVal
	color := (^RenColor)(umka.GetParam(params, 4).ptrVal)

	r := rencache_draw_text(font^, text, int(x), int(y), color^)
	umka.GetResult(params, result).intVal = i64(r)
}

// odinfmt: disable
@(private="file")
regs := []FuncReg {
  { "show_debug",    f_show_debug    },
  { "get_size",      f_get_size      },
  { "begin_frame",   f_begin_frame   },
  { "end_frame",     f_end_frame     },
  { "set_clip_rect", f_set_clip_rect },
  { "draw_rect",     f_draw_rect     },
  { "draw_text",     f_draw_text     },

  // font
  { "font_free",          f_gc            },
  { "font_load",          f_load          },
  { "font_set_tab_width", f_set_tab_width },
  { "font_get_width",     f_get_width     },
  { "font_get_height",    f_get_height    },
}
// odinfmt: enable

renderer_source := #load("modules/renderer.um", cstring)

add_module_renderer :: proc(U: umka.Context) -> bool {
	for reg in regs {
		if !umka.AddFunc(U, reg.name, reg.func) do return false
	}
	return umka.AddModule(U, "renderer.um", renderer_source)
}

