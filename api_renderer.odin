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

Color :: struct {
	r, g, b, a: u8,
}

color2rencolor :: proc(c: ^Color, def: u8 = 255) -> RenColor {
	if c == nil do return {def, def, def, 255}
	return {c.b, c.g, c.r, c.a}
}

f_draw_rect :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	rect: RenRect
	rect.x = i32(umka.GetParam(params, 0).intVal)
	rect.y = i32(umka.GetParam(params, 1).intVal)
	rect.width = i32(umka.GetParam(params, 2).intVal)
	rect.height = i32(umka.GetParam(params, 3).intVal)
	color := (^Color)(umka.GetParam(params, 4))
	rencache_draw_rect(rect, color2rencolor(color))
}

f_draw_text :: proc "c" (params, result: ^umka.StackSlot) {
	context = runtime.default_context()
	font := fonts[umka.GetParam(params, 0).intVal]
	text := cstring(umka.GetParam(params, 1).ptrVal)
	x := umka.GetParam(params, 2).realVal
	y := umka.GetParam(params, 3).realVal
	color := (^Color)(umka.GetParam(params, 4))

	r := 0
	if text != nil {
		r = rencache_draw_text(font, text, int(x), int(y), color2rencolor(color))
	}
	umka.GetResult(params, result).intVal = i64(r)
}

// odinfmt: disable
@(private="file")
regs := []FuncReg {
  { "f_show_debug",    f_show_debug    },
  { "f_get_size",      f_get_size      },
  { "f_begin_frame",   f_begin_frame   },
  { "f_end_frame",     f_end_frame     },
  { "f_set_clip_rect", f_set_clip_rect },
  { "f_draw_rect",     f_draw_rect     },
  { "f_draw_text",     f_draw_text     },

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

