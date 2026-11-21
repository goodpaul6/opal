package main

import "core:mem"
import "core:hash"
import "core:os"
import "core:slice"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_inter_fractional_advance_and_pair_kerning :: proc(t: ^testing.T) {
    bytes := #load("fonts/Inter-Regular.ttf")
    extended := [?]rune{'ö', 'Å', 'é', 0xffff}
    codepoints: [FONT_PAIR_COUNT + len(extended)]rune
    for i in 0..<FONT_PAIR_COUNT do codepoints[i] = FONT_PAIR_FIRST + rune(i)
    copy(codepoints[FONT_PAIR_COUNT:], extended[:])
    font := rl.Font{baseSize = 24, glyphPadding = 4}
    font.glyphs = rl.LoadFontData(raw_data(bytes), i32(len(bytes)), font.baseSize, raw_data(codepoints[:]), len(codepoints), .DEFAULT, &font.glyphCount)
    if !testing.expect(t, font.glyphs != nil) do return
    defer rl.UnloadFontData(font.glyphs, font.glyphCount)
    atlas := rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, font.baseSize, font.glyphPadding, 0)
    defer rl.UnloadImage(atlas)
    defer rl.MemFree(font.recs)
    if !testing.expect(t, rl.IsImageValid(atlas) && font.recs != nil) do return

    cache: Font_Pair_Cache
    defer font_metrics_destroy(&cache.metrics)
    metrics := font_metrics_load_darwin(bytes, &font, &cache)
    defer font_metrics_destroy(&metrics)
    testing.expect_value(t, len(metrics.advances), int(font.glyphCount))
    testing.expect(t, font_pair_delta(&metrics, 'A', 'V') < 0)
    testing.expect(t, font_pair_delta(&metrics, 'T', 'o') < 0)
    testing.expect_value(t, font_pair_delta(&metrics, 'f', 'i'), f32(0)) // Ligature not applied.
    testing.expect(t, font_pair_delta(&metrics, 'T', 'é') < 0)
    testing.expect(t, font_pair_delta(&metrics, 'Å', 'V') < 0)
    testing.expect_value(t, font_pair_delta(&metrics, 'T', 'á'), f32(0)) // Not in the atlas.
    testing.expect_value(t, font_pair_delta(&metrics, 'T', 0xffff), f32(0)) // Not in the face.
    testing.expect_value(t, font_pair_delta(&metrics, 'T', 0x100e9), f32(0)) // Not a BMP alias.

    // TextKit origin for ö in “Ångström”, including the r–ö pair. Exercise the
    // actual pen with both allocators disabled, not just the cached value.
    origin: f32
    {
        context.allocator = mem.panic_allocator()
        context.temp_allocator = mem.panic_allocator()
        pen: Display_Pen
        for ch in "Ångströ" do origin = display_pen_step(&pen, &font, &metrics, ch)
    }
    testing.expectf(t, abs(origin - 61.71831) < 0.002, "ö: origin %.5f, want 61.71831", origin)
    testing.expect(t, display_glyph_advance(&font, 'é', &metrics) != display_glyph_advance(&font, 'é'))
    testing.expect_value(t, display_glyph_advance(&font, '☃', &metrics), display_glyph_advance(&font, '?', &metrics))

    // AppKit/CoreText reference at the atlas's hhea-scaled size of 24.
    cases := [?]struct { text: string, width: f32 }{
        {"AVAVAVAV", 98.141},
        {"iiiiiiiiiiiiiiii", 75.268},
        {"ToToToTo", 89.577},
    }
    for c in cases {
        actual := display_text_width(&font, c.text, &metrics)
        testing.expectf(t, abs(actual - c.width) < 0.002, "%s: width %.4f, want %.3f", c.text, actual, c.width)
    }

    // The second size can keep its own advances while sharing Inter's pair
    // adjustments. Compare all cached pairs with CoreText at that size.
    larger := font
    larger.baseSize = 60
    scaled := font_metrics_load_darwin(bytes, &larger, &cache)
    defer font_metrics_destroy(&scaled)
    exact := font_metrics_load_darwin(bytes, &larger)
    defer font_metrics_destroy(&exact)
    testing.expect(t, scaled.pair_reference == &cache.metrics)
    for left in codepoints {
        for right in codepoints {
            testing.expectf(t, abs(font_pair_delta(&scaled, left, right) - font_pair_delta(&exact, left, right)) < 0.00001,
                "cached pair differs at runes %x, %x", left, right)
        }
    }
}

@(private="file")
inter_font_pairs_from_coretext :: proc(t: ^testing.T, bytes: []byte, codepoints: []rune) -> Font_Metrics {
    font, ok := font_raster_load(bytes, INTER_KERNING_REFERENCE_SIZE, codepoints, upload_texture = false)
    if !testing.expect(t, ok) do return {}
    defer rl.UnloadFontData(font.glyphs, font.glyphCount)
    defer rl.MemFree(font.recs)
    return font_metrics_load_darwin(bytes, &font)
}

@(test)
test_bundled_inter_font_pairs_match_coretext :: proc(t: ^testing.T) {
    bytes := #load("fonts/Inter-Regular.ttf")
    codepoints := theme_font_codepoints()
    cache := bundled_inter_font_pairs(bytes)
    defer font_metrics_destroy(&cache.metrics)
    exact := inter_font_pairs_from_coretext(t, bytes, codepoints[:])
    defer font_metrics_destroy(&exact)

    testing.expect_value(t, cache.base_size, i32(INTER_KERNING_REFERENCE_SIZE))
    testing.expect_value(t, cache.metrics.pair_rows, exact.pair_rows)
    testing.expect(t, slice.equal(cache.metrics.pairs[:], exact.pairs[:]))
    testing.expect(t, slice.equal(cache.metrics.extended_pairs, exact.extended_pairs))
}

when #config(OPAL_GENERATE_FONT_PAIRS, false) {
    @(test)
    generate_inter_font_pairs :: proc(t: ^testing.T) {
        bytes := #load("fonts/Inter-Regular.ttf")
        codepoints := theme_font_codepoints()
        metrics := inter_font_pairs_from_coretext(t, bytes, codepoints[:])
        defer font_metrics_destroy(&metrics)
        if !testing.expect(t, len(metrics.pairs) > 0 && len(metrics.extended_pairs) > 0) do return

        words := make([dynamic]u32le, 0, 3 + 2 * (len(metrics.pairs) + len(metrics.extended_pairs)))
        defer delete(words)
        append(&words, u32le(hash.crc32(bytes)), u32le(hash.crc32(mem.slice_to_bytes(codepoints[:]))),
               u32le(len(metrics.pairs)))
        for l in 0..<FONT_PAIR_COUNT {
            left := FONT_PAIR_FIRST + rune(l)
            for r in 0..<FONT_PAIR_COUNT {
                right := FONT_PAIR_FIRST + rune(r)
                delta := font_pair_delta(&metrics, left, right)
                if delta != 0 {
                    append(&words, u32le(font_extended_pair_key(left, right)), u32le(transmute(u32)delta))
                }
            }
        }
        for entry in metrics.extended_pairs {
            append(&words, u32le(entry.key), u32le(transmute(u32)entry.delta))
        }
        err := os.write_entire_file("fonts/Inter-kerning.bin", mem.slice_to_bytes(words[:]))
        testing.expect(t, err == nil)
    }
}
