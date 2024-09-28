package main

import "core:strings"
import rl "vendor:raylib"

Dyn_Font_Glyph :: struct {
	font_size:  i32,
	gi:         rl.GlyphInfo,
	atlas_rect: rl.Rectangle,
}

Dyn_Font :: struct {
	file_data: []u8,
	atlas:     rl.Image,
	texture:   rl.Texture,
	glyphs:    [dynamic]Dyn_Font_Glyph,
}

dyn_font_make :: proc(file_data: []u8) -> Dyn_Font {
	atlas := rl.GenImageColor(512, 512, rl.Color{0, 0, 0, 0})
	texture := rl.LoadTextureFromImage(atlas)

	rl.SetTextureFilter(texture, .BILINEAR)

	return {
		file_data = file_data,
		atlas = atlas,
		texture = texture,
		glyphs = make([dynamic]Dyn_Font_Glyph),
	}
}

dyn_font_draw_text :: proc(using font: ^Dyn_Font, text: string, font_size: i32, pos: rl.Vector2) {
	codepoints := make([]rune, strings.rune_count(text), context.temp_allocator)

	for codepoint, index in text {
		codepoints[index] = codepoint
	}

	rendered_glyphs := rl.LoadFontData(
		raw_data(file_data),
		i32(len(file_data)),
		font_size,
		raw_data(codepoints),
		i32(len(codepoints)),
		.DEFAULT,
	)
}
