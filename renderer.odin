package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:os"

import sdl "vendor:sdl2"
import stbtt "vendor:stb/truetype"

@(private)
clip: ClipRect

@(private)
MAX_GLYPHSET :: 256

RenColor :: struct {
	b, g, r, a: u8,
}

RenRect :: struct {
	x, y, width, height: i32,
}

RenImage :: struct {
	pixels:        []RenColor,
	width, height: i32,
}

ClipRect :: struct {
	left, top, right, bottom: i32,
}

GlyphSet :: struct {
	image:  ^RenImage,
	glyphs: [256]stbtt.bakedchar,
}

RenFont :: struct {
	data:    []byte,
	stbfont: stbtt.fontinfo,
	sets:    [MAX_GLYPHSET]^GlyphSet,
	size:    f32,
	height:  i32,
}

initial_frame: bool
loaded_fonts: [dynamic]^RenFont
default_allocator: runtime.Allocator

ren_init :: proc(win: ^sdl.Window) {
	window = win
	surf: ^sdl.Surface = sdl.GetWindowSurface(window)
	ren_set_clip_rect(RenRect{0, 0, surf.w, surf.h})
	default_allocator = context.allocator
}

ren_update_rects :: proc "contextless" (rects: [^]RenRect, count: i32) {
	sdl.UpdateWindowSurfaceRects(window, cast([^]sdl.Rect)rects, count)
	initial_frame = true
	if initial_frame {
		sdl.ShowWindow(window)
		initial_frame = false
	}
}

ren_set_clip_rect :: proc "contextless" (rect: RenRect) {
	clip.left = rect.x
	clip.top = rect.y
	clip.right = rect.x + rect.width
	clip.bottom = rect.y + rect.height
}

ren_get_size :: proc "contextless" (x: ^i32, y: ^i32) {
	surf: ^sdl.Surface = sdl.GetWindowSurface(window)
	x^ = surf.w
	y^ = surf.h
}

ren_new_image :: proc(width: i32, height: i32) -> ^RenImage {
	assert(width > 0 && height > 0)
	image: ^RenImage = new(RenImage, default_allocator)
	image.pixels = make([]RenColor, width * height, default_allocator)
	image.width = width
	image.height = height
	return image
}

ren_free_image :: proc(image: ^RenImage) {
	delete(image.pixels, default_allocator)
	free(image, default_allocator)
}

load_glyphset :: proc(font: ^RenFont, idx: i32) -> ^GlyphSet {
	set := new(GlyphSet, default_allocator)
	/* init image */
	width: i32 = 128
	height: i32 = 128


	done: i32 = -1
	set.image = ren_new_image(width, height)
	for done < 0 {
		//   /* load glyphs */
		s :=
			stbtt.ScaleForMappingEmToPixels(&font.stbfont, 1) /
			stbtt.ScaleForPixelHeight(&font.stbfont, 1)

		res: i32 = stbtt.BakeFontBitmap(
			raw_data(font.data),
			0,
			font.size * s,
			cast([^]u8)raw_data(set.image.pixels),
			width,
			height,
			idx * 256,
			256,
			raw_data(&set.glyphs),
		)

		/* retry with a larger image buffer if the buffer wasn't large enough */
		if (res < 0) {
			width *= 2
			height *= 2
			ren_free_image(set.image)
			set.image = ren_new_image(width, height)
		}
		done = res
	}
	/* adjust glyph yoffsets and xadvance */
	ascent, descent, linegap: i32
	stbtt.GetFontVMetrics(&font.stbfont, &ascent, &descent, &linegap)
	scale: f32 = stbtt.ScaleForMappingEmToPixels(&font.stbfont, font.size)
	scaled_ascent: i32 = cast(i32)(f32(ascent) * scale + 0.5)

	for i in 0 ..< 256 {
		set.glyphs[i].yoff += f32(scaled_ascent)
		set.glyphs[i].xadvance = math.floor(set.glyphs[i].xadvance)
	}

	/* convert 8bit data to 32bit */
	for i := width * height - 1; i >= 0; i -= 1 {
		raw_pixels: [^]RenColor = raw_data(set.image.pixels)
		n: u8 = (cast([^]u8)raw_pixels)[i]
		set.image.pixels[i] = RenColor {
			r = 255,
			g = 255,
			b = 255,
			a = n,
		}
	}
	return set
}

get_glyphset :: proc(font: ^RenFont, codepoint: i32) -> ^GlyphSet {
	idx := (codepoint >> 8) % MAX_GLYPHSET
	assert(font != nil)
	if font.sets[idx] == nil {
		font.sets[idx] = load_glyphset(font, idx)
	}
	return font.sets[idx]
}

ren_load_font :: proc(filename: cstring, size: f32) -> ^RenFont {
	/* init font */
	font := new(RenFont, default_allocator)
	font.size = size

	/* load font into buffer */
	data, success := os.read_entire_file_from_filename(string(filename), default_allocator)
	if !success {
		fmt.println("Failed to read file from filename", filename)
		free(font, default_allocator)
		return nil
	}
	font.data = data

	/* init stbfont */
	ok := cast(i32)stbtt.InitFont(&font.stbfont, raw_data(font.data), 0)
	if ok == 0 {
		fmt.println("Failed to init font")
		return nil
	}

	/* get height and scale */
	ascent, descent, linegap: i32
	stbtt.GetFontVMetrics(&font.stbfont, &ascent, &descent, &linegap)
	scale := stbtt.ScaleForMappingEmToPixels(&font.stbfont, size)
	font.height = cast(i32)(cast(f32)(ascent - descent + linegap) * scale + 0.5)

	/* make tab and newline glyphs invisible */
	set: ^GlyphSet = get_glyphset(font, '\n')
	set.glyphs['\t'].x1 = set.glyphs['\t'].x0
	set.glyphs['\n'].x1 = set.glyphs['\n'].x0
	append(&loaded_fonts, font)

	return font
}

ren_free_font :: proc(font: ^RenFont) {
	for f, i in loaded_fonts {
		if f == font {
			unordered_remove(&loaded_fonts, i)
			break
		}
	}

	for i in 0 ..< MAX_GLYPHSET {
		set: ^GlyphSet = font.sets[i]
		if set != nil {
			ren_free_image(set.image)
			free(set, default_allocator)
		}
	}
	delete(font.data, default_allocator)
	free(font, default_allocator)
}

ren_free_fonts :: proc() {
	size := len(loaded_fonts)
	for i := 0; i < size; i += 1 {
		ren_free_font(pop(&loaded_fonts))
	}
	assert(len(loaded_fonts) == 0)
}

ren_set_font_tab_width :: proc(font: ^RenFont, n: i32) {
	set: ^GlyphSet = get_glyphset(font, '\t')
	set.glyphs['\t'].xadvance = cast(f32)n
}

ren_get_font_tab_width :: proc(font: ^RenFont) -> i32 {
	set: ^GlyphSet = get_glyphset(font, '\t')
	return cast(i32)set.glyphs['\t'].xadvance
}

ren_get_font_width :: proc(font: ^RenFont, text: cstring) -> i32 {
	x: i32 = 0
	p := string(text) // not a copy
	for codepoint in p {
		set: ^GlyphSet = get_glyphset(font, cast(i32)codepoint)
		g: ^stbtt.bakedchar = &set.glyphs[codepoint & 0xff]
		x += cast(i32)g.xadvance
	}
	return x
}

ren_get_font_height :: proc "contextless" (font: ^RenFont) -> i32 {
	return font.height
}

blend_pixel :: #force_inline proc "contextless" (dst: RenColor, src: RenColor) -> RenColor {
	dst := dst

	ia := u32(0xff - src.a)
	src_a := u32(src.a)
	dst.r = u8(((u32(src.r) * src_a) + (u32(dst.r) * ia)) >> 8)
	dst.g = u8(((u32(src.g) * src_a) + (u32(dst.g) * ia)) >> 8)
	dst.b = u8(((u32(src.b) * src_a) + (u32(dst.b) * ia)) >> 8)
	return dst
}

blend_pixel2 :: #force_inline proc "contextless" (
	dst: RenColor,
	src: RenColor,
	color: RenColor,
) -> RenColor {
	dst := dst

	src_a := (u32(src.a) * u32(color.a)) >> 8
	ia: u32 = u32(0xff - src.a)
	dst.r = u8((u32(src.r) * u32(color.r) * src_a >> 16) + ((u32(dst.r) * ia) >> 8))
	dst.g = u8((u32(src.g) * u32(color.g) * src_a >> 16) + ((u32(dst.g) * ia) >> 8))
	dst.b = u8((u32(src.b) * u32(color.b) * src_a >> 16) + ((u32(dst.b) * ia) >> 8))

	return dst
}

ren_draw_rect :: proc "contextless" (rect: RenRect, color: RenColor) {
	if (color.a == 0) {
		return
	}

	x1: i32 = max(rect.x, clip.left)
	y1: i32 = max(rect.y, clip.top)
	x2: i32 = min(rect.x + rect.width, clip.right)
	y2: i32 = min(rect.y + rect.height, clip.bottom)
	rect_width := x2 - x1

	surf: ^sdl.Surface = sdl.GetWindowSurface(window)
	d := cast([^]RenColor)surf.pixels
	row_start := x1 + y1 * surf.w

	if color.a == 0xff {
		for _ in y1 ..< y2 {
			for i in 0 ..< rect_width {
				d[row_start + i] = color
			}
			row_start += surf.w
		}
	} else {
		for _ in y1 ..< y2 {
			for i in 0 ..< rect_width {
				d[row_start + i] = blend_pixel(d[i], color)
			}
			row_start += surf.w
		}
	}
}

ren_draw_image :: proc "contextless" (
	image: ^RenImage,
	sub: ^RenRect,
	x: i32,
	y: i32,
	color: RenColor,
) {
	if color.a == 0 {
		return
	}
	x := x
	y := y

	/* clip */
	n := clip.left - x
	if n > 0 {
		sub.width -= n
		sub.x += n
		x += n
	}

	n = clip.top - y
	if n > 0 {
		sub.height -= n
		sub.y += n
		y += n
	}

	n = x + sub.width - clip.right
	if n > 0 {
		sub.width -= n
	}

	n = y + sub.height - clip.bottom
	if n > 0 {
		sub.height -= n
	}

	if (sub.width <= 0 || sub.height <= 0) {
		return
	}

	/* draw */
	surf: ^sdl.Surface = sdl.GetWindowSurface(window)
	s: [^]RenColor = raw_data(image.pixels)
	d: [^]RenColor = cast([^]RenColor)(surf.pixels)
	image_row := sub.x + sub.y * image.width
	surf_row := x + y * surf.w

	for _ in 0 ..< sub.height {
		for i in 0 ..< sub.width {
			d[surf_row + i] = blend_pixel2(d[surf_row + i], s[image_row + i], color)
		}
		image_row += image.width
		surf_row += surf.w
	}
}

ren_draw_text :: proc(font: ^RenFont, text: string, x: i32, y: i32, color: RenColor) -> i32 {
	rect: RenRect
	x := x

	for codepoint in text {
		set: ^GlyphSet = get_glyphset(font, cast(i32)codepoint)
		g: ^stbtt.bakedchar = &set.glyphs[codepoint & 0xff]

		rect.x = cast(i32)g.x0
		rect.y = cast(i32)g.y0
		rect.width = cast(i32)(g.x1 - g.x0)
		rect.height = cast(i32)(g.y1 - g.y0)
		ren_draw_image(
			set.image,
			&rect,
			cast(i32)(cast(f32)x + g.xoff),
			cast(i32)(cast(f32)y + g.yoff),
			color,
		)
		x += cast(i32)g.xadvance
	}
	return x
}

