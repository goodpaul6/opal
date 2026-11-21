package main

import rl "vendor:raylib"
import "core:slice"
import "core:math"
import "core:fmt"
import "core:time"

Theme_Font_Variant :: enum {
    H1,
    H2,
    H3,
    H4,
    H5,
    H6,
    BODY,
    PRE,
    H1_CODE,
    H2_CODE,
    H3_CODE,
    H4_CODE,
    H5_CODE,
    H6_CODE,
}

THEME_HEADING_VARIANTS :: [?]Theme_Font_Variant{.H1, .H2, .H3, .H4, .H5, .H6}
THEME_HEADING_CODE_VARIANTS :: [?]Theme_Font_Variant{.H1_CODE, .H2_CODE, .H3_CODE, .H4_CODE, .H5_CODE, .H6_CODE}
Theme_Font_Sizes :: [Theme_Font_Variant]i32

// hhea ascents and heights, and OS/2 cap heights, for the bundled faces.
INTER_ASCENT :: 2728
INTER_HEIGHT :: 3408
INTER_CAP_HEIGHT :: 2048
COMMIT_MONO_ASCENT :: 900
COMMIT_MONO_HEIGHT :: 1100
COMMIT_MONO_CAP_HEIGHT :: 700

// Divide the H1-to-body interval into six steps, rounding to the nearest
// pixel. A gap of at least six gives each heading its own nominal size.
theme_font_sizes :: proc(h1, body, pre: i32) -> (sizes: Theme_Font_Sizes) {
    steps :: len(THEME_HEADING_VARIANTS)
    gap := h1 - body
    assert(gap >= steps)
    sizes[.BODY] = body
    sizes[.PRE] = pre
    code_variants := THEME_HEADING_CODE_VARIANTS
    cap_height_ratio :: (f32(INTER_CAP_HEIGHT) / INTER_HEIGHT) / (f32(COMMIT_MONO_CAP_HEIGHT) / COMMIT_MONO_HEIGHT)
    for variant, i in THEME_HEADING_VARIANTS {
        sizes[variant] = body + (gap * (steps - i32(i)) + steps / 2) / steps
        sizes[code_variants[i]] = i32(math.round(f32(sizes[variant]) * cap_height_ratio))
    }
    return
}

// This is the static data for a given theme.
Theme_Data :: struct {
    zoom_level_to_font_sizes: []Theme_Font_Sizes,
    font_data: [Theme_Font_Variant][]byte, // Borrowed, read-only embedded bytes.

    bg_color: rl.Color,
    fg_color: rl.Color,

    // Only the bundled faces opt in to scaling pair adjustments across sizes.
    reuse_font_pairs: bool,
    font_pair_cache: [Theme_Font_Variant]Font_Pair_Cache,
}

Theme :: struct {
    data: ^Theme_Data,

    zoom_level: int,

    // Logical fonts own the density-independent advances and line heights.
    fonts: [Theme_Font_Variant]rl.Font,
    font_metrics: [Theme_Font_Variant]Font_Metrics,
    // A zero texture ID means the logical atlas can be used directly.
    native_fonts: [Theme_Font_Variant]rl.Font,
    body_placement, native_body_placement: Font_Raster_Placement,
    pixel_scale: [2]f32,
    previous_zoom: ^Theme, // One inactive zoom level, with its own atlases.
}

theme_data_make_default :: proc() -> Theme_Data {
    INTER_DATA := #load("fonts/Inter-Regular.ttf")
    COMMIT_MONO_DATA := #load("fonts/CommitMono-400-Regular.otf")
    font_data: [Theme_Font_Variant][]byte
    for variant in Theme_Font_Variant {
        monospace := variant == .PRE || variant >= .H1_CODE
        font_data[variant] = monospace ? COMMIT_MONO_DATA[:] : INTER_DATA[:]
    }

    data := Theme_Data{
        zoom_level_to_font_sizes = slice.clone([]Theme_Font_Sizes{
            theme_font_sizes(36, 24, 24),
            theme_font_sizes(48, 30, 30),
            theme_font_sizes(60, 36, 36),
            theme_font_sizes(72, 48, 48),
            theme_font_sizes(96, 60, 60),
        }),
        font_data = font_data,

        bg_color = {0x16, 0x16, 0x1D, 0xFF},
        fg_color = {0xDC, 0xD7, 0xBA, 0xFF},
    }
    when ODIN_OS == .Darwin {
        data.reuse_font_pairs = true
        data.font_pair_cache[.H1] = bundled_inter_font_pairs(INTER_DATA[:])
    }
    return data
}

theme_data_destroy :: proc(data: ^Theme_Data) {
    delete(data.zoom_level_to_font_sizes)
    when ODIN_OS == .Darwin {
        for &cache in data.font_pair_cache do font_metrics_destroy(&cache.metrics)
    }
}

theme_make :: proc(data: ^Theme_Data, zoom_level := 0, pixel_scale := [2]f32{1, 1}) -> Theme {
    theme := Theme{data = data, zoom_level = zoom_level, pixel_scale = pixel_scale}
    theme_ensure_font(&theme, .BODY)
    return theme
}

// Load optional styles on first use. Measurement and drawing share the
// logical metrics, with a separate atlas only at a different raster size.
theme_ensure_font :: proc(theme: ^Theme, variant: Theme_Font_Variant) {
    if theme.fonts[variant].baseSize != 0 do return

    size := theme.data.zoom_level_to_font_sizes[theme.zoom_level][variant]
    native_size := theme_raster_size(size, theme.pixel_scale.y)
    theme_load_logical_font(theme, variant, size, upload_texture = native_size == size)
    theme_update_native_font(theme, variant, theme_raster_size(theme.fonts[variant].baseSize, theme.pixel_scale.y))
}

@(private="file")
theme_load_logical_font :: proc(theme: ^Theme, variant: Theme_Font_Variant, size: i32, upload_texture: bool) {
    placement: ^Font_Raster_Placement
    when ODIN_OS == .Darwin {
        if theme.zoom_level == 0 && variant == .BODY && size == 24 do placement = &theme.body_placement
    }
    theme.fonts[variant] = theme_load_font(theme.data, variant, size,
                                          &theme.font_metrics[variant], placement, cache_half = placement != nil,
                                          upload_texture = upload_texture)
}

THEME_FONT_PUNCTUATION :: [?]rune{'–', '—', '‘', '’', '“', '”', '•', '…', '€', '→', '✓'}

theme_font_codepoints :: proc() -> (codepoints: [191 + len(THEME_FONT_PUNCTUATION)]rune) {
    // raylib's default atlas only includes printable ASCII. Include Latin-1
    // and common writing punctuation without requiring a dynamic font atlas.
    punctuation := THEME_FONT_PUNCTUATION
    for i in 0..<95 do codepoints[i] = 0x20 + rune(i)
    for i in 0..<96 do codepoints[95 + i] = 0xA0 + rune(i)
    copy(codepoints[191:], punctuation[:])
    return
}

@(private="file")
theme_load_font :: proc(data: ^Theme_Data, variant: Theme_Font_Variant, size: i32, metrics: ^Font_Metrics = nil,
                        placement: ^Font_Raster_Placement = nil, cache_half := false, upload_texture := true) -> rl.Font {
    raster_tick, metrics_tick: time.Tick
    when OPAL_TRACE_INPUT do raster_tick = time.tick_now()
    codepoints := theme_font_codepoints()
    bytes := data.font_data[variant]
    coverage_gain: Font_Coverage_Gain
    when OPAL_TEXT_COVERAGE {
        coverage_gain = font_raster_coverage_gain(data.fg_color, data.bg_color)
    }
    font, ok := font_raster_load(bytes, size, codepoints[:], coverage_gain, foreground = data.fg_color,
                                 placement = placement, cache_half = cache_half, upload_texture = upload_texture)
    when OPAL_TRACE_INPUT do metrics_tick = time.tick_now()
    if !ok do font = rl.GetFontDefault()
    when ODIN_OS == .Darwin {
        if ok && metrics != nil {
            pair_cache: ^Font_Pair_Cache
            if data.reuse_font_pairs {
                for v in Theme_Font_Variant {
                    other := data.font_data[v]
                    if raw_data(other) == raw_data(bytes) && len(other) == len(bytes) {
                        pair_cache = &data.font_pair_cache[v]
                        break
                    }
                }
            }
            metrics^ = font_metrics_load_darwin(bytes, &font, pair_cache)
        }
    }
    if font.texture.id != 0 do rl.SetTextureFilter(font.texture, .POINT)
    when OPAL_TRACE_INPUT {
        fmt.eprintf("font %v %dpx: atlas %.3f ms, metrics %.3f ms\n", variant, size,
            time.duration_milliseconds(time.tick_diff(raster_tick, metrics_tick)),
            time.duration_milliseconds(time.tick_since(metrics_tick)))
    }
    return font
}

// Font rasterizers take a single integer size; use vertical density to
// preserve the nominal line height at fractional framebuffer scales.
theme_raster_size :: proc(logical_size: i32, pixel_scale_y: f32) -> i32 {
    return max(1, i32(math.round(f32(logical_size) * pixel_scale_y)))
}

theme_heading_code_offset :: proc(theme: ^Theme, heading, code: Theme_Font_Variant) -> f32 {
    scale := theme.pixel_scale.y
    // Raylib and CoreText truncate the scaled ascent when they place glyphs
    // in the atlas. Match those baselines in framebuffer pixels.
    heading_size := theme_raster_size(theme.fonts[heading].baseSize, scale)
    code_size := theme_raster_size(theme.fonts[code].baseSize, scale)
    heading_baseline := i32(f32(heading_size) / INTER_HEIGHT * INTER_ASCENT)
    code_baseline := i32(f32(code_size) / COMMIT_MONO_HEIGHT * COMMIT_MONO_ASCENT)
    return f32(heading_baseline - code_baseline) / scale
}

theme_set_pixel_scale :: proc(theme: ^Theme, scale: [2]f32) {
    if scale == theme.pixel_scale do return
    for variant in Theme_Font_Variant {
        logical_size := theme.fonts[variant].baseSize
        if logical_size == 0 do continue
        size := theme_raster_size(logical_size, scale.y)
        if size == theme_raster_size(logical_size, theme.pixel_scale.y) do continue
        theme_update_native_font(theme, variant, size)
    }
    theme.pixel_scale = scale
}

@(private="file")
theme_update_native_font :: proc(theme: ^Theme, variant: Theme_Font_Variant, size: i32) {
    logical_size := theme.fonts[variant].baseSize
    native_font := &theme.native_fonts[variant]
    if native_font.texture.id != 0 do rl.UnloadFont(native_font^)
    native_font^ = {}
    placement: ^Font_Raster_Placement
    when ODIN_OS == .Darwin {
        if theme.zoom_level == 0 && variant == .BODY {
            theme.native_body_placement = {}
            if logical_size == 24 && size == 48 do placement = &theme.native_body_placement
        }
    }
    if size != logical_size {
        native_font^ = theme_load_font(theme.data, variant, size, placement = placement)
    } else if theme.fonts[variant].texture.id == 0 {
        // The window moved to a display where the logical atlas is drawable.
        theme_unload_font(theme.fonts[variant])
        font_metrics_destroy(&theme.font_metrics[variant])
        theme_load_logical_font(theme, variant, logical_size, upload_texture = true)
    }
}

@(private="file")
theme_unload_font :: proc(font: rl.Font) {
    if font.texture.id != 0 {
        rl.UnloadFont(font)
    } else if font.glyphs != nil {
        rl.UnloadFontData(font.glyphs, font.glyphCount)
        rl.MemFree(font.recs)
    }
}

@(private="file")
theme_unload_fonts :: proc(theme: ^Theme) {
    for font in theme.native_fonts {
        if font.texture.id != 0 do rl.UnloadFont(font)
    }
    for variant in Theme_Font_Variant {
        theme_unload_font(theme.fonts[variant])
        font_metrics_destroy(&theme.font_metrics[variant])
    }
}

theme_destroy :: proc(theme: ^Theme) {
    theme_unload_fonts(theme)
    if theme.previous_zoom != nil {
        theme_unload_fonts(theme.previous_zoom)
        free(theme.previous_zoom)
    }
}

theme_set_zoom_level :: proc(theme: ^Theme, raw_zoom_level: int) {
    data := theme.data
    zoom_level := clamp(raw_zoom_level, 0, len(data.zoom_level_to_font_sizes) - 1)
    if zoom_level == theme.zoom_level do return

    scale := theme.pixel_scale
    previous := theme.previous_zoom
    if previous == nil {
        previous = new(Theme)
        previous.zoom_level = -1
    }
    if previous.zoom_level == zoom_level {
        restored := previous^
        previous^ = theme^
        theme^ = restored
        theme_set_pixel_scale(theme, scale)
    } else {
        theme_unload_fonts(previous)
        previous^ = theme^
        theme^ = theme_make(data, zoom_level, scale)
    }
    previous.previous_zoom = nil
    theme.previous_zoom = previous
}
