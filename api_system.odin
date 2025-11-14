package main

import "base:runtime"
import "core:bufio"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "core:sys/windows"
_ :: windows

import "umka"
import sdl "vendor:sdl2"

Match :: struct {
	text:      umka.Str,
	line, col: i64,
}

f_search_file_find :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	U := umka.GetInstance(result)

	pattern := cstring(umka.GetParam(params, 0).ptrVal)
	file := cstring(umka.GetParam(params, 1).ptrVal)
	matches := make_dynamic_array([dynamic]Match, context.temp_allocator)
	search_file_find_helper(U, pattern, file, &matches)

	res := (^umka.DynArray(Match))(umka.GetResult(params, result).ptrVal)
	dtype := umka.GetResultType(params, result)
	n := len(matches)
	umka.MakeDynArray(U, res, dtype, i32(n))
	_ = runtime.copy_slice_raw(res.data, raw_data(matches), n, n, size_of(Match))
}

search_file_find_helper :: proc(
	U: umka.Context,
	pattern, file: cstring,
	matches: ^[dynamic]Match,
) {
	f, ferr := os.open(string(file))
	if ferr != nil do return
	defer os.close(f)

	r: bufio.Reader
	buffer: [65536]byte
	bufio.reader_init_with_buf(&r, os.stream_from_handle(f), buffer[:])
	defer bufio.reader_destroy(&r)

	pat_u8 := transmute([]u8)(string(pattern))

	line_no: i64 = 1
	for {
		// This will allocate a string because the line might go over the backing
		// buffer and thus need to join things together
		line, err := bufio.reader_read_slice(&r, '\n')
		if err != nil {
			if err == .EOF || err == .Unknown {
				break
			}
			// TODO handle longer lines
		}
		pos := strcasestr(line, pat_u8)
		if pos >= 0 {
			tline := strings.unsafe_string_to_cstring(
				strings.clone_from_bytes(line, context.temp_allocator),
			)
			append(
				matches,
				Match{text = umka.MakeStr(U, tline), line = line_no, col = i64(pos + 1)},
			)
			// fmt.println("Found match at:", line_no, pos + 1, "in:", file)
		}
		line_no += 1
	}
	return
}

strcasestr :: proc(h: []u8, n: []u8) -> int {
	lower :: #force_inline proc "contextless" (ch: byte) -> byte {return ('a' - 'A') | ch}
	if len(n) == 0 do return 0

	first := lower(n[0])
	for i := 0; i < len(h); i += 1 {
		if lower(h[i]) == first {
			n_idx := 1
			h_idx := i + 1
			for {
				// needle exhausted, we found the str
				if n_idx >= len(n) do return i
				// haystack exhausted?
				if h_idx >= len(h) do break
				// mismatch, break and try again
				if lower(h[h_idx]) != lower(n[n_idx]) do break
				// move to next char
				n_idx += 1
				h_idx += 1
			}
		}
	}
	return -1
}

button_name :: proc(button: u8) -> cstring {
	switch (button) {
	case 1:
		return "left"
	case 2:
		return "middle"
	case 3:
		return "right"
	case:
		return "?"
	}
}

key_name :: proc(dst: []u8, sym: sdl.Keycode) -> cstring {
	keyname: string = string(sdl.GetKeyName(sym))

	i := 0
	for c in keyname {
		dst[i] = cast(u8)libc.tolower(i32(c))
		i += 1
	}
	return cstring(raw_data(dst))
}

EventType :: enum i64 {
	QUIT,
	RESIZED,
	EXPOSED,
	FILEDROPPED,
	KEYPRESSED,
	KEYRELEASED,
	TEXTINPUT,
	MOUSEPRESSED,
	MOUSERELEASED,
	MOUSEMOVED,
	MOUSEWHEEL,
}

Event :: struct {
	type:       EventType,
	s:          umka.Str,
	x, y, w, z: f64,
}

f_poll_event :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	context = runtime.default_context()
	U := umka.GetInstance(result)
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	events := make([dynamic]Event, context.temp_allocator)
	defer delete(events)
	poll_event_helper(U, &events)

	res := (^umka.DynArray(Event))(umka.GetResult(params, result).ptrVal)
	rtype := umka.GetResultType(params, result)
	n := len(events)
	umka.MakeDynArray(U, res, rtype, i32(n))
	_ = runtime.copy_slice_raw(res.data, raw_data(events), n, n, size_of(Event))
}

poll_event_helper :: proc(U: umka.Context, events: ^[dynamic]Event) {
	buf: [16]u8
	mx, my, wx, wy: i32
	e: sdl.Event

	if (!sdl.PollEvent(&e)) {
		return
	}

	#partial switch (e.type) {
	case .QUIT:
		append(events, Event{type = .QUIT})
		return

	case .WINDOWEVENT:
		if (e.window.event == sdl.WindowEventID.RESIZED) {
			append(
				events,
				Event{type = .RESIZED, x = f64(e.window.data1), y = f64(e.window.data2)},
			)
			return
		} else if (e.window.event == sdl.WindowEventID.EXPOSED) {
			rencache_invalidate()
			append(events, Event{type = .EXPOSED})
			return
		}
		/* on some systems, when alt-tabbing to the window SDL will queue up
         * several KEYDOWN events for the `tab` key; we flush all keydown
         * events on focus so these are discarded */
		if (e.window.event == sdl.WindowEventID.FOCUS_GAINED) {
			sdl.FlushEvent(sdl.EventType.KEYDOWN)
		}
		poll_event_helper(U, events)
		return

	case .DROPFILE:
		sdl.GetGlobalMouseState(&mx, &my)
		sdl.GetWindowPosition(window, &wx, &wy)
		append(
			events,
			Event {
				type = .FILEDROPPED,
				s = umka.MakeStr(U, e.drop.file),
				x = f64(mx - wx),
				y = f64(my - wy),
			},
		)
		sdl.free(cast([^]u8)e.drop.file)
		return

	case .KEYDOWN:
		kname := key_name(buf[:], e.key.keysym.sym)
		append(events, Event{type = .KEYPRESSED, s = umka.MakeStr(U, kname)})
		return

	case .KEYUP:
		kname := key_name(buf[:], e.key.keysym.sym)
		append(events, Event{type = .KEYRELEASED, s = umka.MakeStr(U, kname)})
		return

	case .TEXTINPUT:
		text := cstring(raw_data(e.text.text[:]))
		append(events, Event{type = .TEXTINPUT, s = umka.MakeStr(U, text)})
		return

	case .MOUSEBUTTONDOWN:
		if (e.button.button == 1) {
			sdl.CaptureMouse(true)
		}
		append(
			events,
			Event {
				type = .MOUSEPRESSED,
				s = umka.MakeStr(U, button_name(e.button.button)),
				x = f64(e.button.x),
				y = f64(e.button.y),
				w = f64(e.button.clicks),
			},
		)
		return

	case .MOUSEBUTTONUP:
		if (e.button.button == 1) {
			sdl.CaptureMouse(false)
		}
		append(
			events,
			Event {
				type = .MOUSERELEASED,
				s = umka.MakeStr(U, button_name(e.button.button)),
				x = f64(e.button.x),
				y = f64(e.button.y),
			},
		)
		return

	case .MOUSEMOTION:
		append(
			events,
			Event {
				type = .MOUSEMOVED,
				x = f64(e.motion.x),
				y = f64(e.motion.y),
				w = f64(e.motion.xrel),
				z = f64(e.motion.yrel),
			},
		)
		return

	case .MOUSEWHEEL:
		append(events, Event{type = .MOUSEWHEEL, x = f64(e.wheel.y)})
		return

	case:
		poll_event_helper(U, events)
		return
	}
}

f_wait_event :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	n := umka.GetParam(params, 0).realVal
	res := (^bool)(umka.GetResult(params, result).ptrVal)
	res^ = bool(sdl.WaitEventTimeout(nil, i32(n * 1000)))
}

cursor_cache: [sdl.SystemCursor.NUM_SYSTEM_CURSORS]^sdl.Cursor

cursor_opts := [?]cstring{"arrow", "ibeam", "sizeh", "sizev", "hand"}

cursor_enums := [?]sdl.SystemCursor {
	sdl.SystemCursor.ARROW,
	sdl.SystemCursor.IBEAM,
	sdl.SystemCursor.SIZEWE,
	sdl.SystemCursor.SIZENS,
	sdl.SystemCursor.HAND,
}

f_set_cursor :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	optstr := cstring(umka.GetParam(params, 0).ptrVal)
	opt := sdl.SystemCursor.ARROW
	for name, i in cursor_opts {
		if name == optstr do opt = cursor_enums[i]
	}
	cursor_value := cursor_enums[opt]
	n: i32 = cast(i32)cursor_value
	cursor: ^sdl.Cursor = cursor_cache[cursor_value]
	if (cursor == nil) {
		cursor = sdl.CreateSystemCursor(cursor_value)
		cursor_cache[n] = cursor
	}
	sdl.SetCursor(cursor)
}

f_set_window_title :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	title := cstring(umka.GetParam(params, 0).ptrVal)
	sdl.SetWindowTitle(window, title)
}

window_opts := [?]cstring{"normal", "maximized", "fullscreen"}
Win :: enum {
	WIN_NORMAL,
	WIN_MAXIMIZED,
	WIN_FULLSCREEN,
}

f_set_window_mode :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	nstr := cstring(umka.GetParam(params, 0).ptrVal)
	n := Win.WIN_NORMAL
	for name, i in cursor_opts {
		if name == nstr do n = Win(i)
	}
	sdl.SetWindowFullscreen(
		window,
		n == .WIN_FULLSCREEN ? sdl.WINDOW_FULLSCREEN_DESKTOP : sdl.WindowFlags{},
	)
	if (n == .WIN_NORMAL) {sdl.RestoreWindow(window)}
	if (n == .WIN_MAXIMIZED) {sdl.MaximizeWindow(window)}
}


f_window_has_focus :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	flags := sdl.GetWindowFlags(window)
	b := cast(bool)(flags & cast(u32)sdl.WINDOW_INPUT_FOCUS)
	res := (^bool)(umka.GetResult(params, result).ptrVal)
	res^ = b
}

f_show_confirm_dialog :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	title := cstring(umka.GetParam(params, 0).ptrVal)
	msg := cstring(umka.GetParam(params, 1).ptrVal)

	b: bool
	when ODIN_OS == .Windows {
		context = runtime.default_context()
		message := windows.utf8_to_wstring(string(msg))
		caption := windows.utf8_to_wstring(string(title))
		id := windows.MessageBoxW(
			windows.HWND(nil),
			message,
			caption,
			windows.UINT(windows.MB_YESNO | windows.MB_ICONWARNING),
		)
		b = id == windows.IDYES
	} else {
		buttons := []sdl.MessageBoxButtonData {
			{sdl.MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT, 1, "Yes"},
			{sdl.MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT, 0, "No"},
		}
		data: sdl.MessageBoxData = {
			title      = title,
			message    = msg,
			numbuttons = 2,
			buttons    = raw_data(buttons),
		}
		buttonid: i32
		sdl.ShowMessageBox(&data, &buttonid)
		b = buttonid == 1
	}
	res := (^bool)(umka.GetResult(params, result).ptrVal)
	res^ = b
}

Error :: struct {
	msg: umka.Str,
}

f_chdir :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	context = runtime.default_context()
	path := cstring(umka.GetParam(params, 0).ptrVal)
	err := os.set_current_directory(string(path))
	res := (^bool)(umka.GetResult(params, result).ptrVal)
	res^ = err != nil
}

FileInfo :: struct {
	name:     umka.Str,
	modified: i64,
	size:     i64,
	is_dir:   bool,
}

f_list_dir :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	context = runtime.default_context()
	U := umka.GetInstance(result)
	// create a separate temp region
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	path := cstring(umka.GetParam(params, 0).ptrVal)
	filelist := make_dynamic_array([dynamic]FileInfo, context.temp_allocator)
	defer delete(filelist)

	list_dir_helper(U, path, &filelist)
	res := (^umka.DynArray(FileInfo))(umka.GetResult(params, result).ptrVal)
	dtype := umka.GetResultType(params, result)
	n := len(filelist)
	umka.MakeDynArray(U, res, dtype, i32(n))
	_ = runtime.copy_slice_raw(res.data, raw_data(filelist), n, n, size_of(FileInfo))
}

list_dir_helper :: proc(U: umka.Context, path: cstring, filelist: ^[dynamic]FileInfo) {
	handle, err1 := os.open(string(path))
	defer os.close(handle)
	if err1 != nil do return

	entries, err2 := os.read_dir(handle, -1, context.temp_allocator)
	if err2 != nil do return

	for e, _ in entries {
		if e.name == "." || e.name == ".." {
			continue
		}
		name := cstring(strings.clone_to_cstring(e.name, context.temp_allocator))
		append(
			filelist,
			FileInfo {
				name = umka.MakeStr(U, name),
				modified = time.time_to_unix(e.modification_time),
				size = e.size,
				is_dir = e.is_dir,
			},
		)
	}
}


f_absolute_path :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	context = runtime.default_context()
	U := umka.GetInstance(result)
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	path := cstring(umka.GetParam(params, 0).ptrVal)
	apath, ok := filepath.abs(string(path), context.temp_allocator)
	Result :: struct {
		apath: umka.Str,
		ok:    bool,
	}
	res := (^Result)(umka.GetResult(params, result).ptrVal)
	res.apath = umka.MakeStr(U, strings.unsafe_string_to_cstring(apath))
	res.ok = ok
}

f_get_file_info :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	context = runtime.default_context()
	U := umka.GetInstance(result)
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	path := cstring(umka.GetParam(params, 0).ptrVal)

	Result :: struct {
		fi: FileInfo,
		ok: bool,
	}
	res := (^Result)(umka.GetResult(params, result).ptrVal)

	fi, err := os.stat(string(path), context.temp_allocator)
	defer os.file_info_delete(fi, context.temp_allocator)
	if err != nil {
		res.ok = false
		return
	}

	res.fi.name = umka.MakeStr(U, strings.unsafe_string_to_cstring(fi.name))
	res.fi.modified = time.time_to_unix(fi.modification_time)
	res.fi.size = fi.size
	res.fi.is_dir = fi.is_dir
	res.ok = true
}

f_get_clipboard :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	U := umka.GetInstance(result)
	text: cstring = sdl.GetClipboardText()
	if (text == nil) {
		umka.GetResult(params, result).ptrVal = nil
		return
	}
	umka.GetResult(params, result).ptrVal = rawptr(umka.MakeStr(U, text))
	sdl.free(cast([^]u8)text)
}

f_set_clipboard :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	text := cstring(umka.GetParam(params, 0).ptrVal)
	sdl.SetClipboardText(text)
}

f_get_time :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	n := cast(f64)sdl.GetPerformanceCounter() / cast(f64)sdl.GetPerformanceFrequency()
	umka.GetResult(params, result).realVal = n
}

f_sleep :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	n := umka.GetParam(params, 0).realVal
	sdl.Delay(u32(n * 1000))
}

f_exec :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	context = runtime.default_context()
	len: libc.size_t
	cmd := cstring(umka.GetParam(params, 0).ptrVal)
	buf := make([]u8, len + 32)
	defer delete(buf)

	when ODIN_OS == .Windows {
		_ = cmd
		//   sprintf(buf, "cmd /c \"%s\"", cmd);
		//   WinExec(buf, SW_HIDE);
	} else {
		fmt.bprintf(buf, "%s &", cmd)
		fmt.println("----EXEC---- ", buf)
		_ = libc.system(cast(cstring)raw_data(buf))
	}
}

f_fuzzy_match :: proc "c" (params: ^umka.StackSlot, result: ^umka.StackSlot) {
	strng := cstring(umka.GetParam(params, 0).ptrVal)
	pattern := cstring(umka.GetParam(params, 1).ptrVal)
	score: i32 = 0
	run: i32 = 0

	str := cast([^]u8)strng
	ptn := cast([^]u8)pattern

	pattern_len := len(pattern)
	str_len := len(strng)

	i, j := 0, 0
	for i < str_len && j < pattern_len {
		for str[i] == ' ' do i += 1
		for ptn[j] == ' ' do j += 1
		if (i >= str_len || j >= pattern_len) do break

		s := str[i]
		p := ptn[j]
		if libc.tolower(i32(s)) == libc.tolower(i32(p)) {
			score += run * 10 - i32(s != p)
			run += 1
			j += 1
		} else {
			score -= 10
			run = 0
		}
		i += 1
	}

	Result :: struct {
		i:     i64,
		found: bool,
	}
	res := (^Result)(umka.GetResult(params, result).ptrVal)
	if j < pattern_len {
		res.found = false
	} else {
		remaining := i32(str_len - i)
		res.i = i64(score - remaining)
		res.found = true
	}
}

f_lerp_uint8 :: proc "c" (params, result: ^umka.StackSlot) {
	a := (^u8)(umka.GetParam(params, 0).ptrVal)
	b := (^u8)(umka.GetParam(params, 1).ptrVal)
	t := umka.GetParam(params, 2).realVal
	c := (^u8)(umka.GetResult(params, result).ptrVal)
	c^ = u8(f64(a^) + f64(b^ - a^) * t)
}

// odinfmt: disable
@(private="file")
regs := [?]FuncReg {
  { "poll_event",          f_poll_event          },
  { "wait_event",          f_wait_event          },
  { "set_cursor",          f_set_cursor          },
  { "set_window_title",    f_set_window_title    },
  { "set_window_mode",     f_set_window_mode     },
  { "window_has_focus",    f_window_has_focus    },
  { "show_confirm_dialog", f_show_confirm_dialog },
  { "chdir",               f_chdir               },
  { "list_dir",            f_list_dir            },
  { "absolute_path",       f_absolute_path       },
  { "get_file_info",       f_get_file_info       },
  { "get_clipboard",       f_get_clipboard       },
  { "set_clipboard",       f_set_clipboard       },
  { "get_time",            f_get_time            },
  { "sleep",               f_sleep               },
  { "exec",                f_exec                },
  { "fuzzy_match",         f_fuzzy_match         },
  { "search_file_find",    f_search_file_find    },
  { "lerp_uint8",          f_lerp_uint8          },
}
// odinfmt: enable

system_source := #load("modules/system.um", cstring)

add_module_system :: proc(U: umka.Context) -> bool {
	for reg in regs {
		if !umka.AddFunc(U, reg.name, reg.func) do return false
	}
	return umka.AddModule(U, "system.um", system_source)
}

