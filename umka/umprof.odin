// taken from https://github.com/marekmaskarinec/umprof
package umka

import "core:path/filepath"
import "core:sort"
import "core:text/table"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:time"

@(private)
UmprofEvent :: struct {
	type:     HookEvent,
	clock:    time.Tick,
	filename: cstring,
	name:     cstring,
	line:     i32,
}

@(private)
UmprofInfo :: struct {
	filename:             cstring,
	name:                 cstring,
	line:                 i32,
	callCount:            int,
	clock, clockSelf:     time.Duration,
	percent, percentSelf: f64,
}

@(private)
UmprofEventParser :: struct {
	arr:    ^[]UmprofInfo,
	arrlen: int,
	arrcap: int,
}

@(private)
events: [dynamic]UmprofEvent

umprofInit :: proc(U: Context) {
	clear(&events)
	SetHook(U, .UMKA_HOOK_CALL, umprofCallHook)
	SetHook(U, .UMKA_HOOK_RETURN, umprofReturnHook)
}

umprofDinit :: proc() {
	delete(events)
}

umprofCallHook :: proc "c" (filename, funcName: cstring, line: i32) {
	context = runtime.default_context()
	append(&events, UmprofEvent{.UMKA_HOOK_CALL, time.tick_now(), filename, funcName, line})
}

umprofReturnHook :: proc "c" (filename, funcName: cstring, line: i32) {
	context = runtime.default_context()
	append(&events, UmprofEvent{.UMKA_HOOK_RETURN, time.tick_now(), filename, funcName, line})
}

umprofPrintInfo :: proc(maxInfo: int = 2048) {
	f, err := os.open("prof.txt", os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	assert(err == nil, "failed to open prof.txt")
	defer os.close(f)

	fmt.fprintfln(f, "Total events collected: %d", len(events))
	arr := make([]UmprofInfo, maxInfo)
	defer delete(arr)
	arrlen := umprofGetInfo(&arr, maxInfo)

	MAX_SMALL :: 14
	MAX_NUMBER :: 14
	MAX_FLOAT :: 14
	MAX_FUNC_NAME :: 35

	fmt.fprintfln(f, "Total funcs parsed: %d", arrlen)
	// odinfmt: disable
	fmt.fprintf(f, "%*s%*s%*s%*s%*s%*s\n",
		MAX_SMALL, "count",
		MAX_FLOAT, "%", MAX_FLOAT, "% self",
		MAX_NUMBER, "clock", MAX_NUMBER, "clock self",
		MAX_FUNC_NAME, "function name")
	for i := 0; i < MAX_FLOAT * 2 + MAX_NUMBER * 3 + MAX_FUNC_NAME; i += 1 {
		fmt.fprintf(f, "-")
	}
	fmt.fprintf(f, "\n")

	for i in 0 ..< arrlen {
		fmt.fprintf(f, "% *d% *f% *f% *d% *d%*s %s:%d\n", MAX_SMALL, arr[i].callCount,
			MAX_FLOAT, arr[i].percent, MAX_FLOAT, arr[i].percentSelf,
			MAX_NUMBER, i64(arr[i].clock), MAX_NUMBER, i64(arr[i].clockSelf),
			MAX_FUNC_NAME, arr[i].name, arr[i].filename, arr[i].line);
	}
	// odinfmt: enable
}

umprofGetInfo :: proc(output: ^[]UmprofInfo, maxInfo: int) -> int {
	if len(events) == 0 do return 1

	par := UmprofEventParser {
		arr    = output,
		arrcap = maxInfo,
	}

	main := umprofGetFunc(&par, &events[0])
	if umprofParseEvent(&par, main, 0) == len(events) do return 0

	total := time.tick_diff(events[0].clock, events[len(events) - 1].clock)
	for i in 0 ..< par.arrlen {
		par.arr[i].percent = f64(par.arr[i].clock) / f64(total)
		par.arr[i].percentSelf = f64(par.arr[i].clockSelf) / f64(total)
	}
	return par.arrlen
}

umprofGetFunc :: proc(par: ^UmprofEventParser, e: ^UmprofEvent) -> ^UmprofInfo {
	for i in 0 ..< par.arrlen {
		if par.arr[i].name == e.name &&
		   par.arr[i].filename == e.filename &&
		   par.arr[i].line == e.line {
			return &par.arr[i]
		}
	}
	if par.arrlen == par.arrcap do return nil

	info := &par.arr[par.arrlen]
	par.arrlen += 1
	info.filename = e.filename
	info.name = e.name
	info.line = e.line
	info.callCount = 0
	return info
}

umprofParseEvent :: proc(par: ^UmprofEventParser, out: ^UmprofInfo, i: int) -> int {
	noRec := out.clock
	noRecSelf := out.clockSelf
	notSelf: time.Duration = 0
	p := i + 1
	for p < len(events) && events[p].type != .UMKA_HOOK_RETURN {
		info := umprofGetFunc(par, &events[p])
		if info == nil do return len(events)

		offset := info.clock
		p = umprofParseEvent(par, info, p)
		if p >= len(events) do return p
		notSelf += info.clock - offset

		p += 1
	}

	out.callCount += 1
	out.clock = noRec + time.tick_diff(events[i].clock, events[p].clock)
	out.clockSelf = noRecSelf + time.tick_diff(events[i].clock, events[p].clock) - notSelf
	return p
}

umprofPrintTable :: proc(filename: string = "prof.txt", maxInfo: int = 1024) {
	f, err := os.open(filename, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	assert(err == nil, "failed to open file")
	w := os.stream_from_handle(f)
	defer os.close(f)

	arr := make([]UmprofInfo, maxInfo)
	defer delete(arr)
	arrlen := umprofGetInfo(&arr, maxInfo)

	fmt.fprintfln(f, "Total events collected: %d", len(events))
	fmt.fprintfln(f, "Total funcs parsed: %d", arrlen)
	
	// odinfmt: disable
	t: table.Table
	table.init(&t, context.temp_allocator, context.temp_allocator)
	table.padding(&t, 2, 2)
	table.header(&t, "count", "%", "% self", "clock", "clock self", "clock/count", "clock self/count", "location", "funcname")

	sort.heap_sort_proc(arr[0:arrlen], proc(a, b: UmprofInfo) -> int {
		return sort.compare_i64s(i64(b.clock), i64(a.clock))
	})
	for i in 0 ..< arrlen {
		a := arr[i]
		table.row(&t, a.callCount, fmt.tprintf("%.3f", a.percent), fmt.tprintf("%.3f", a.percentSelf),
			// i64(a.clock), i64(a.clockSelf),
			a.clock, a.clockSelf, a.clock / time.Duration(a.callCount), a.clockSelf / time.Duration(a.callCount),
			fmt.tprintf("%s:%d", filepath.base(string(a.filename)), a.line), a.name)
	}

	decorations := table.Decorations {
		"┌", "┬", "┐",
		"├", "┼", "┤",
		"└", "┴", "┘",
		"│", "─",
	}

	table.write_decorated_table(w, &t, decorations)
	fmt.fprintln(f)
	// odinfmt: enable
}

