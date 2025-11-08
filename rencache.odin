package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:strings"

/* a cache over the software renderer -- all drawing operations are stored as
** commands when issued. At the end of the frame we write the commands to a grid
** of hash values, take the cells that have changed since the previous frame,
** merge them into dirty rectangles and redraw only those regions */

CELLS_X :: 80
CELLS_Y :: 50
CELL_SIZE :: 96
COMMAND_BUF_SIZE :: 1024 * 512

HASH_INITIAL :: 2166136261

@(private)
CommandType :: enum {
	FREE_FONT,
	SET_CLIP,
	DRAW_TEXT,
	DRAW_RECT,
}

Command :: struct {
	type:      CommandType,
	size:      i32,
	rect:      RenRect,
	color:     RenColor,
	font:      ^RenFont,
	tab_width: i32,
	text:      [0]u8,
}

cells_buf1: [CELLS_X * CELLS_Y]u32
cells_buf2: [CELLS_X * CELLS_Y]u32
cells_prev: []u32 = cells_buf1[:]
cells: []u32 = cells_buf2[:]
rect_buf: [CELLS_X * CELLS_Y / 2]RenRect

command_buf: [COMMAND_BUF_SIZE]u8
command_buf_idx: int

screen_rect: RenRect
show_debug: bool


hash :: proc "contextless" (h: u32, data: []u8) -> u32 {
	h := h
	for d in data {
		h = (h ~ u32(d)) * 16777619
	}
	return h
}

cell_idx :: proc "contextless" (x: i32, y: i32) -> i32 {
	return x + y * CELLS_X
}

rects_overlap :: proc "contextless" (a: RenRect, b: RenRect) -> bool {
// odinfmt: disable
  return b.x + b.width  >= a.x && b.x <= a.x + a.width &&
         b.y + b.height >= a.y && b.y <= a.y + a.height
// odinfmt: enable
}

intersect_rects :: proc "contextless" (a: RenRect, b: RenRect) -> RenRect {
	x1: i32 = math.max(a.x, b.x)
	y1: i32 = math.max(a.y, b.y)
	x2: i32 = math.min(a.x + a.width, b.x + b.width)
	y2: i32 = math.min(a.y + a.height, b.y + b.height)
	return {x1, y1, max(0, x2 - x1), max(0, y2 - y1)}
}

merge_rects :: proc "contextless" (a: RenRect, b: RenRect) -> RenRect {
	x1: i32 = min(a.x, b.x)
	y1: i32 = min(a.y, b.y)
	x2: i32 = max(a.x + a.width, b.x + b.width)
	y2: i32 = max(a.y + a.height, b.y + b.height)
	return {x1, y1, x2 - x1, y2 - y1}
}

push_command :: proc(type: CommandType, size: int) -> ^Command {

	cmd := cast(^Command)&command_buf[command_buf_idx]
	n := command_buf_idx + size
	if n > COMMAND_BUF_SIZE {
		fmt.println("Command buffer exhausted!")
		return nil
	}
	command_buf_idx = n
	runtime.memset(cmd, 0, size)
	cmd.type = type
	cmd.size = cast(i32)size
	return cmd
}

next_command :: proc(prev: ^^Command) -> bool {
	if prev^ == nil {
		prev^ = cast(^Command)&command_buf[0]
	} else {
		cmd := prev^
		prev^ = (^Command)(uintptr(cmd) + uintptr(cmd.size))
	}
	return prev^ != (cast(^Command)&command_buf[command_buf_idx])
}

rencache_show_debug :: proc "contextless" (enable: bool) {
	show_debug = enable
}

rencache_free_font :: proc(font: ^RenFont) {
	cmd := push_command(.FREE_FONT, size_of(Command))
	if cmd != nil do cmd.font = font
}

rencache_set_clip_rect :: proc(rect: RenRect) {
	cmd := push_command(.SET_CLIP, size_of(Command))
	if cmd != nil do cmd.rect = intersect_rects(rect, screen_rect)
}

rencache_draw_rect :: proc(rect: RenRect, color: RenColor) {
	if !rects_overlap(screen_rect, rect) do return
	cmd := push_command(.DRAW_RECT, size_of(Command))
	if cmd != nil {
		cmd.rect = intersect_rects(rect, screen_rect)
		cmd.color = color
	}
}

rencache_draw_text :: proc(font: ^RenFont, text: cstring, x: int, y: int, color: RenColor) -> int {
	rect: RenRect = ---
	rect.x = cast(i32)x
	rect.y = cast(i32)y
	rect.width = ren_get_font_width(font, text)
	rect.height = ren_get_font_height(font)

	if (rects_overlap(screen_rect, rect)) {
		text_len := len(text) + 1
		cmd := push_command(.DRAW_TEXT, size_of(Command) + text_len)
		if cmd != nil {
			cmd.color = color
			cmd.rect = rect
			cmd.font = font
			cmd.tab_width = ren_get_font_tab_width(font)
			text_buf: [^]u8 = cast([^]u8)&cmd.text
			text_in: [^]u8 = cast([^]u8)text

			for i in 0..<text_len {
				text_buf[i] = text_in[i]
			}
		}
	}

	return x + int(rect.width)
}

@(export)
rencache_invalidate :: proc "c" () {
	runtime.memset(raw_data(cells_prev), 0xff, len(cells_prev) * size_of(u32))
}

rencache_begin_frame :: proc() {
	/* reset all cells if the screen width/height has changed */
	w, h: i32
	ren_get_size(&w, &h)
	if (screen_rect.width != w || h != screen_rect.height) {
		screen_rect.width = w
		screen_rect.height = h
		rencache_invalidate()
	}
}

update_overlapping_cells :: proc "contextless" (r: RenRect, h: u32) {
	x1 := r.x / CELL_SIZE
	y1 := r.y / CELL_SIZE
	x2 := (r.x + r.width) / CELL_SIZE
	y2 := (r.y + r.height) / CELL_SIZE

	h := h

	for y in y1..=y2 {
		for x in x1..=x2 {
			idx := cell_idx(x, y)
			cells[idx] = hash(cells[idx], mem.ptr_to_bytes(&h, 1))
		}
	}
}

push_rect :: proc "contextless" (r: RenRect, count: int) -> int {
	/* try to merge with existing rectangle */
	#reverse for &rp in rect_buf[0:count] {
		if (rects_overlap(rp, r)) {
			rp = merge_rects(rp, r)
			return count
		}
	}
	/* couldn't merge with previous rectangle: push */
	rect_buf[count] = r

	count := count
	count += 1
	return count
}

rencache_end_frame :: proc() {
	/* update cells from commands */
	cr: RenRect
	cmd: ^Command
	for next_command(&cmd) {
		if cmd.type == CommandType.SET_CLIP {
			cr = cmd.rect
		}
		r := intersect_rects(cmd.rect, cr)
		if (r.width == 0 || r.height == 0) {
			continue
		}
		h: u32 = HASH_INITIAL

		// hash the bytes
		off := cast(i32)(uintptr(cmd) - uintptr(&command_buf[0]))
		h = hash(h, command_buf[off:off + cmd.size])
		update_overlapping_cells(r, h)
	}

	/* push rects for all cells changed from last frame, reset cells */
	rect_count := 0
	max_x := screen_rect.width / CELL_SIZE + 1
	max_y := screen_rect.height / CELL_SIZE + 1
	for y in 0 ..< max_y {
		for x in 0 ..< max_x {
			/* compare previous and current cell for change */
			idx := cell_idx(x, y)
			if (cells[idx] != cells_prev[idx]) {
				rect_count = push_rect(RenRect{x, y, 1, 1}, rect_count)
			}
			cells_prev[idx] = HASH_INITIAL
		}
	}

	/* expand rects from cells to pixels */
	for &r in rect_buf[0:rect_count] {
		r.x *= CELL_SIZE
		r.y *= CELL_SIZE
		r.width *= CELL_SIZE
		r.height *= CELL_SIZE
		r = intersect_rects(r, screen_rect)
	}

	/* redraw updated regions */
	has_free_commands := false
	for &r in rect_buf[0:rect_count] {
		/* draw */
		ren_set_clip_rect(r)

		cmd = nil
		for next_command(&cmd) {
			switch cmd.type {
			case .FREE_FONT:
				has_free_commands = true
			case .SET_CLIP:
				ren_set_clip_rect(intersect_rects(cmd.rect, r))
			case .DRAW_RECT:
				ren_draw_rect(cmd.rect, cmd.color)
			case .DRAW_TEXT:
				ren_set_font_tab_width(cmd.font, cmd.tab_width)
				text := strings.string_from_ptr(
					cast([^]u8)&cmd.text,
					int(cmd.size) - size_of(Command),
				)
				ren_draw_text(cmd.font, text, cmd.rect.x, cmd.rect.y, cmd.color)
			}
		}
		if (show_debug) {
			color := RenColor{u8(rand.uint32()), u8(rand.uint32()), u8(rand.uint32()), 50} // red(bgra)
			ren_draw_rect(r, color)
		}
	}

	/* update dirty rects */
	if rect_count > 0 {
		ren_update_rects(raw_data(&rect_buf), i32(rect_count))
	}

	// /* free fonts */
	if has_free_commands {
		cmd = nil
		for next_command(&cmd) {
			if (cmd.type == CommandType.FREE_FONT) {
				ren_free_font(cmd.font)
			}
		}
	}

	// reset command buffer
	command_buf_idx = 0
	/* swap cell buffer and reset */
	cells, cells_prev = cells_prev, cells
}

