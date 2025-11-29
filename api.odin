package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
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

source_files := [?]string {
	"data/core/common.um",
	"data/core/config.um",
	"data/core/style.um",
	"data/core/syntax.um",
	"data/core/tokenizer.um",
	"data/core/cex.um",
	"data/core/view.um",
	"data/core/doc/doc.um",
	"data/core/doc/search.um",
	"data/core/doc/translate.um",
	"data/core/command.um",
	"data/core/keymap.um",
	"data/core/logview.um",
	"data/core/docview.um",
	"data/core/commandview.um",
	"data/core/statusview.um",
	"data/core/emptyview.um",
	"data/core/rootview.um",
	"data/core/commands/commandutils.um",
	"data/core/core.um",
}

api_add_lite_modules :: proc(U: umka.Context) -> bool {
	for filename in source_files {
		source, ok := os.read_entire_file_from_filename(filename)
		assert(ok, fmt.tprintf("failed to read file: %q", filename))

		modname := strings.unsafe_string_to_cstring(filepath.base(filename))
		if !umka.AddModule(U, modname, cstring(raw_data(source))) do return false
	}
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

