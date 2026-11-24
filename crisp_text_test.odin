package main

import "core:testing"
import rl "vendor:raylib"

@(test)
test_crisp_text_native_glyph_bounds :: proc(t: ^testing.T) {
    // Neither a fractional line origin nor a negative bearing should move
    // the quad off the pixel grid or resize it to a fractional pixel extent.
    source := rl.Rectangle{100, 200, 9, 15}
    glyph := rl.GlyphInfo{offsetX = -2, offsetY = 3}
    cases := [?]struct {
        scale: [2]f32,
        native_origin: [2]f32,
    }{
        {{1, 1}, {2, 2}},
        {{2, 2}, {5, 2}},
        {{1.25, 1.5}, {3, 2}},
    }
    for c in cases {
        dest := display_glyph_destination(c.scale, {3.6, -0.6}, source, glyph)
        testing.expect_value(t, [2]f32{dest.x, dest.y} * c.scale, c.native_origin)
        testing.expect_value(t, [2]f32{dest.width, dest.height} * c.scale, [2]f32{9, 15})
    }
    dest := display_glyph_destination({2, 2}, {4, 6}, source, glyph, 0.5)
    testing.expect_value(t, dest, rl.Rectangle{3.5, 6.75, 2.25, 3.75})
    // When the atlas matches effective device zoom, every texel maps to one device pixel.
    sharp := display_glyph_destination({2, 2}, {4, 6}, source, glyph, 2, 4)
    testing.expect_value(t, sharp, rl.Rectangle{3, 7.5, 4.5, 7.5})
}

@(test)
test_crisp_text_logical_advances :: proc(t: ^testing.T) {
    glyphs := [?]rl.GlyphInfo{
        {value = '?', advanceX = 6},
        {value = 'é', advanceX = 7},
        {value = ' '},
    }
    recs := [?]rl.Rectangle{{}, {}, {width = 3}}
    font := rl.Font{baseSize = 24, glyphCount = len(glyphs), glyphs = raw_data(glyphs[:]), recs = raw_data(recs[:])}
    testing.expect_value(t, display_text_width(&font, "é 	☃"), f32(19))
    testing.expect_value(t, theme_raster_size(font.baseSize, 1), i32(24))
    testing.expect_value(t, theme_raster_size(font.baseSize, 1.2), i32(29))
    testing.expect_value(t, theme_raster_size(font.baseSize, 2), i32(48))

    // The snapped caret does not affect the logical pen, and shares the
    // same snapped position as the next glyph's zero-bearing origin.
    theme := Theme{pixel_scale = {1.25, 1.5}}
    caret := display_snap_rect(&theme, {3.6 + 19, -0.6, 2, 24})
    glyph := display_glyph_destination(theme.pixel_scale, {3.6 + 19, -0.6}, {0, 0, 9, 15}, {})
    testing.expect_value(t, [2]f32{caret.x, caret.y}, [2]f32{glyph.x, glyph.y})
    testing.expect_value(t, caret.width * theme.pixel_scale.x, f32(3))
    testing.expect_value(t, caret.height * theme.pixel_scale.y, f32(36))
}

@(test)
test_crisp_text_native_phase_and_block_edge :: proc(t: ^testing.T) {
    cases := [?]struct { device_x, x: f32, rows: i32 }{
        {3.49, 3, 0}, {3.5, 3, 64}, {3.99, 3, 64}, {4, 4, 0},
        {-0.51, -1, 0}, {-0.5, -1, 64}, {-0.01, -1, 64},
    }
    for c in cases {
        x, rows := display_glyph_phase(c.device_x, 64)
        testing.expect_value(t, x, c.x)
        testing.expect_value(t, rows, c.rows)
        x, rows = display_glyph_phase(c.device_x, 0)
        testing.expect_value(t, x, c.x)
        testing.expect_value(t, rows, i32(0))
    }

    // A bearing of -2 device pixels with a fractional viewport/pen sum.
    // The block must cover the exact left edge at both densities.
    densities := [?]f32{1, 2}
    for density in densities {
        theme := Theme{pixel_scale = {density, density}}
        bounds := rl.Rectangle{1.75 / density, 0, 7 / density, 24}
        block := display_snap_rect(&theme, bounds, floor_left = true)
        legacy := display_snap_rect(&theme, bounds)
        testing.expect_value(t, block.x * density, f32(1))
        testing.expect_value(t, legacy.x * density, f32(2))
        testing.expect_value(t, (block.x + block.width) * density, (legacy.x + legacy.width) * density)
    }
}
