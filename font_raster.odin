package main

import rl "vendor:raylib"

// Narrow the antialiasing ramp around half coverage, without filtering across
// texels or shifting the half-coverage contour. A 20/255 shoulder reduced
// intermediate pixels in the native 2x fixture without materially changing
// total ink in the heading or body. Keep grayscale AA rather than thresholding.
FONT_COVERAGE_SHOULDER :: 20

font_raster_coverage :: proc(alpha: u8) -> u8 {
    ramp :: 255 - 2 * FONT_COVERAGE_SHOULDER
    coverage := clamp(int(alpha) - FONT_COVERAGE_SHOULDER, 0, ramp)
    return u8((coverage * 255 + ramp / 2) / ramp)
}

font_raster_adjust_atlas :: proc(atlas: rl.Image) {
    if atlas.format != .UNCOMPRESSED_GRAY_ALPHA do return
    // raylib's font atlas stores white luminance followed by glyph coverage.
    pixels := ([^][2]u8)(atlas.data)[:int(atlas.width) * int(atlas.height)]
    for &pixel in pixels do pixel[1] = font_raster_coverage(pixel[1])
}

OPAL_TEXT_COVERAGE :: #config(OPAL_TEXT_COVERAGE, #config(OPAL_EXPERIMENTAL_COVERAGE, ODIN_OS == .Darwin))

// Gain in eighths. Light text on a dark background benefits from stronger
// intermediate coverage. Preserve transparent pixels and solid strokes.
Font_Coverage_Gain :: enum {
    OFF = 0,
    DARK_INK = 1,
    LIGHT_INK = 6,
}

font_raster_coverage_gain :: proc(fg, bg: rl.Color) -> Font_Coverage_Gain {
    // Encoded RGB luma is only used to classify the theme's polarity.
    luma :: proc(c: rl.Color) -> int {
        return 2126 * int(c.r) + 7152 * int(c.g) + 722 * int(c.b)
    }
    ink, paper := luma(fg), luma(bg)
    if ink > paper do return .LIGHT_INK
    if ink < paper do return .DARK_INK
    return .OFF
}

font_raster_gain_coverage :: proc(alpha: u8, gain: Font_Coverage_Gain) -> u8 {
    if alpha == 255 do return alpha
    a := int(alpha)
    denom :: 8 * 255
    return u8(min(254, a + (int(gain) * a * (255 - a) + denom / 2) / denom))
}

font_raster_apply_coverage_gain :: proc(atlas: rl.Image, gain: Font_Coverage_Gain) {
    if gain == .OFF || atlas.format != .UNCOMPRESSED_GRAY_ALPHA do return
    coverage: [256]u8
    for &alpha, i in coverage do alpha = font_raster_gain_coverage(u8(i), gain)
    pixels := ([^][2]u8)(atlas.data)[:int(atlas.width) * int(atlas.height)]
    for &pixel in pixels do pixel[1] = coverage[pixel[1]]
}

// Optional Darwin placement data, indexed by atlas glyph index. The half-pixel
// masks share the primary texture, at a fixed row offset.
FONT_RASTER_PHASE_LIMIT :: 256
Font_Raster_Placement :: struct {
    native: [FONT_RASTER_PHASE_LIMIT]bool,
    half_rows: i32,
    em_dash_case_y: i32, // Device-pixel displacement of the same-advance case alternate.
}

// Keep raylib's advances and base size; on Darwin, replace masks that fit
// the padded atlas. The atlas is uploaded once per font size.
font_raster_load :: proc(bytes: []byte, size: i32, codepoints: []rune, coverage_gain := Font_Coverage_Gain.OFF, foreground := rl.WHITE,
                         placement: ^Font_Raster_Placement = nil, cache_half := false, upload_texture := true) -> (font: rl.Font, ok: bool) {
    if placement != nil do placement^ = {}
    font = {
        baseSize = size,
        glyphPadding = 4,
    }
    font.glyphs = rl.LoadFontData(raw_data(bytes), i32(len(bytes)), size, raw_data(codepoints), i32(len(codepoints)), .DEFAULT, &font.glyphCount)
    if font.glyphs == nil do return {}, false
    defer {
        if ok {
            // Drawing uses the texture. Measurement needs only the glyph metadata.
            for i in 0..<font.glyphCount {
                rl.UnloadImage(font.glyphs[i].image)
                font.glyphs[i].image = {}
            }
        } else {
            if placement != nil do placement^ = {}
            rl.UnloadFontData(font.glyphs, font.glyphCount)
            rl.MemFree(font.recs)
        }
    }

    if !upload_texture {
        // raylib's glyph lookup requires rectangles even for a metrics-only
        // font. Keep the bitmap width used by glyphs with no explicit advance.
        font.recs = cast([^]rl.Rectangle)rl.MemAlloc(u32(font.glyphCount) * size_of(rl.Rectangle))
        if font.recs == nil do return {}, false
        for glyph, i in font.glyphs[:font.glyphCount] {
            font.recs[i] = {width = f32(glyph.image.width), height = f32(glyph.image.height)}
        }
        ok = true
        return
    }

    pack_method: i32
    when ODIN_OS == .Darwin {
        // Skyline packing reserves padding around the actual glyph height,
        // including tall glyphs that extend beyond raylib's usual shelf height.
        pack_method = 1
    }
    atlas := rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, size, font.glyphPadding, pack_method)
    defer rl.UnloadImage(atlas)
    if !rl.IsImageValid(atlas) || font.recs == nil do return
    when ODIN_OS == .Darwin {
        if !font_raster_atlas_has_padding(font, atlas) {
            // A failed skyline pack can leave nonempty rectangles outside the image.
            rl.UnloadImage(atlas)
            rl.MemFree(font.recs)
            font.recs = nil
            atlas = rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, size, font.glyphPadding, 0)
            if !rl.IsImageValid(atlas) || font.recs == nil do return
            pack_method = 0
        }
    }
    font_raster_adjust_atlas(atlas)
    when ODIN_OS == .Darwin {
        if pack_method == 1 {
            half_rows: i32
            if placement != nil && len(codepoints) <= FONT_RASTER_PHASE_LIMIT && cache_half {
                half_rows = font_raster_expand_half_darwin(&atlas)
            }
            font_raster_repaint_darwin(bytes, &font, atlas, foreground, placement, half_rows)
        }
    }
    when OPAL_TEXT_COVERAGE {
        // Shape both the repainted glyphs and the adjusted fallback masks.
        font_raster_apply_coverage_gain(atlas, coverage_gain)
    }
    font.texture = rl.LoadTextureFromImage(atlas)
    if font.texture.id == 0 do return

    ok = true
    return
}
