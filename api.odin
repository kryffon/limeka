package main

import "core:fmt"
import "core:os"
import "core:strings"
import "umka"

API_TYPE_FONT :: "Font"

FuncReg :: struct {
	name: cstring,
	func: umka.ExternFunc,
}

api_load_libs :: proc(U: umka.Context) -> bool {
	return add_module_system(U) && add_module_renderer(U) && add_module_strings(U)
}

api_add_lite_modules :: proc(U: umka.Context) -> bool {
	common_source := #load("data/core/common.um", cstring)
	if !umka.AddModule(U, "common.um", common_source) do return false

	config_source := #load("data/core/config.um", cstring)
	if !umka.AddModule(U, "config.um", config_source) do return false

	style_source := #load("data/core/style.um", cstring)
	if !umka.AddModule(U, "style.um", style_source) do return false

	syntax_source := #load("data/core/syntax.um", cstring)
	if !umka.AddModule(U, "syntax.um", syntax_source) do return false

	tokenizer_source := #load("data/core/tokenizer.um", cstring)
	if !umka.AddModule(U, "tokenizer.um", tokenizer_source) do return false

	coreextra_source := #load("data/core/coreextra.um", cstring)
	if !umka.AddModule(U, "cex.um", coreextra_source) do return false

	view_source := #load("data/core/view.um", cstring)
	if !umka.AddModule(U, "view.um", view_source) do return false

	doc_source := #load("data/core/doc/doc.um", cstring)
	if !umka.AddModule(U, "doc.um", doc_source) do return false

	search_source := #load("data/core/doc/search.um", cstring)
	if !umka.AddModule(U, "search.um", search_source) do return false

	translate_source := #load("data/core/doc/translate.um", cstring)
	if !umka.AddModule(U, "translate.um", translate_source) do return false

	command_source := #load("data/core/command.um", cstring)
	if !umka.AddModule(U, "command.um", command_source) do return false

	keymap_source := #load("data/core/keymap.um", cstring)
	if !umka.AddModule(U, "keymap.um", keymap_source) do return false

	logview_source := #load("data/core/logview.um", cstring)
	if !umka.AddModule(U, "logview.um", logview_source) do return false

	docview_source := #load("data/core/docview.um", cstring)
	if !umka.AddModule(U, "docview.um", docview_source) do return false

	commandview_source := #load("data/core/commandview.um", cstring)
	if !umka.AddModule(U, "commandview.um", commandview_source) do return false

	statusview_source := #load("data/core/statusview.um", cstring)
	if !umka.AddModule(U, "statusview.um", statusview_source) do return false

	emptyview_source := #load("data/core/emptyview.um", cstring)
	if !umka.AddModule(U, "emptyview.um", emptyview_source) do return false

	rootview_source := #load("data/core/rootview.um", cstring)
	if !umka.AddModule(U, "rootview.um", rootview_source) do return false

	commandutils_source := #load("data/core/commands/commandutils.um", cstring)
	if !umka.AddModule(U, "commandutils.um", commandutils_source) do return false

	core_source := #load("data/core/core.um", cstring)
	if !umka.AddModule(U, "core.um", core_source) do return false

	return true
}

DEFAULT_PLUGIN_SRC: cstring : `fn load*() {}`
PLUGIN_PATH :: "data/plugins/"
USER_INIT_PATH :: "data/user/init.um"

add_plugin_user_module :: proc(U: umka.Context, failsafe: bool = false) -> bool {
	if failsafe {
		return umka.AddModule(U, "plugins.um", DEFAULT_PLUGIN_SRC)
	}

	handle, err1 := os.open(PLUGIN_PATH)
	defer os.close(handle)
	if err1 != nil {
		fmt.eprintfln("failed to open plugin dir at: %s", PLUGIN_PATH)
		return umka.AddModule(U, "plugins.um", DEFAULT_PLUGIN_SRC)
	}

	entries, err2 := os.read_dir(handle, -1, context.temp_allocator)
	if err2 != nil {
		fmt.eprintfln("failed to read_dir at: %s", PLUGIN_PATH)
		return umka.AddModule(U, "plugins.um", DEFAULT_PLUGIN_SRC)
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	strings.write_string(&b, "import (\n")
	for e in entries {
		strings.write_byte(&b, '"')
		strings.write_string(&b, PLUGIN_PATH)
		strings.write_string(&b, e.name)
		strings.write_byte(&b, '"')
		strings.write_byte(&b, '\n')
	}
	strings.write_string(&b, "user = ")
	strings.write_quoted_string(&b, USER_INIT_PATH)
	strings.write_string(&b, "\n)\nfn load*() {\n")
	for e in entries {
		strings.write_string(&b, e.name[0:len(e.name) - 3])
		strings.write_string(&b, "::load()\n")
	}
	strings.write_string(&b, "user::init()\n")
	strings.write_byte(&b, '}')

	src := strings.to_cstring(&b)
	return umka.AddModule(U, "plugins.um", src)
}

