package umka

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os/os2"
import "core:terminal/ansi"

PrintCompileWarning :: proc "c" (w: ^Error) {
	context = runtime.default_context()
	fmt.eprintf(yellow("%s(%d:%d) Warn: "), w.fileName, w.line, w.pos)
	fmt.eprintf("%s\n", w.msg)
	print_line(w)
}

PrintCompileError :: proc(U: Context) {
	e := GetError(U)
	fmt.eprintf(red("%s(%d:%d) Error: "), e.fileName, e.line, e.pos)
	fmt.eprintf("%s\n", e.msg)
	print_line(e)
}

PrintRuntimeError :: proc(U: Context) {
	e := GetError(U)
	if len(e.msg) > 0 {
		fmt.eprintf(red("%s(%d:%d) exitcode=%d Error: "), e.fileName, e.line, e.pos, e.code)
		fmt.eprintf("%s\n", e.msg)
		print_line(e)
		fmt.eprintf("Stack trace:\n")

		for depth: i32 = 0; depth < 10; depth += 1 {
			STRLEN :: 256 + 1
			fileName, fnName: [STRLEN]u8
			line: i32
					// odinfmt: disable
			if !GetCallStack(U, depth, STRLEN, nil, raw_data(fileName[:]), raw_data(fnName[:]),  &line) {
				break
			}
			// odinfmt: enable

			fmt.eprintf("    %s:%d:%s\n", fileName, line, fnName)
		}
	}
}

@(private)
print_line :: proc(e: ^Error) {
	f, err := os2.open(string(e.fileName))
	defer os2.close(f)
	if err != nil do return

	r := os2.to_reader(f)
	cur_line_num: i32 = 1
	cur_byte := -1
	start, end: int = 0, -1
	for true {
		cur_byte += 1
		b, berr := io.read_byte(r)
		if berr != nil do break
		if b == '\n' {
			if cur_line_num == e.line {
				end = cur_byte
				break
			}
			cur_line_num += 1
			start = cur_byte + 1
		}
	}
	if end > start {
		buf := make([]u8, end - start)
		defer delete(buf)
		_, rerr := os2.read_at(f, buf, i64(start))
		if rerr == nil {
			for &b in buf do if b == '\t' do b = ' '
			fmt.eprintf("\n%s\n", buf)
			fmt.eprintf(yellow("%*s\n\n"), e.pos, "^")
		}
	}
}

@(private)
red :: #force_inline proc($s: string) -> string {
	return ansi.CSI + ansi.FG_BRIGHT_RED + ansi.SGR + s + ansi.CSI + ansi.RESET + ansi.SGR
}

@(private)
yellow :: #force_inline proc($s: string) -> string {
	return ansi.CSI + ansi.FG_BRIGHT_YELLOW + ansi.SGR + s + ansi.CSI + ansi.RESET + ansi.SGR
}

