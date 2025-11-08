package main

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os/os2"

import "umka"

print_compile_warning :: proc "c" (w: ^umka.Error) {
	context = runtime.default_context()
	fmt.eprintf(yellow("%s(%d:%d) Warn: "), w.fileName, w.line, w.pos)
	fmt.eprintf("%s\n", w.msg)
	print_line(w)
}

print_compile_error :: proc(U: umka.Context) {
	e := umka.GetError(U)
	fmt.eprintf(red("%s(%d:%d) Error: "), e.fileName, e.line, e.pos)
	fmt.eprintf("%s\n", e.msg)
	print_line(e)
}

print_line :: proc(e: ^umka.Error) {
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
			fmt.eprintf("%s\n", buf)
			fmt.eprintf(yellow("%*s\n"), e.pos, "^")
		}
	}
}

print_runtime_error :: proc(U: umka.Context, exitcode: i32) {
	e := umka.GetError(U)
	if len(e.msg) > 0 {
		fmt.eprintf(red("%s(%d:) exitcode=%d: Error"), e.fileName, e.line, exitcode)
		fmt.eprintf("%s\n", e.msg)
		fmt.eprintf("Stack trace:\n")

		for depth: i32 = 0; depth < 10; depth += 1 {
			STRLEN :: 256 + 1
			fileName, fnName: [STRLEN]u8
			line: i32
					// odinfmt: disable
			if !umka.GetCallStack(U, depth, STRLEN, nil, raw_data(fileName[:]), raw_data(fnName[:]),  &line) {
				break
			}
			// odinfmt: enable

			fmt.eprintf("    %s:%d:%s\n", fileName, line, fileName)
		}
	}
}

