package main

import "umka"

API_TYPE_FONT :: "Font"

FuncReg :: struct {
	name: cstring,
	func: umka.ExternFunc,
}

api_load_libs :: proc(U: umka.Context) -> bool {
	return add_module_system(U) && add_module_renderer(U) && add_module_strings(U)
}

