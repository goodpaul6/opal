package main

import "core:slice"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_font_raster_darwin_masks :: proc(t: ^testing.T) {
    font_data := [?][]byte{
        #load("fonts/Inter-Regular.ttf"),
        #load("fonts/CommitMono-400-Regular.otf"),
    }
    for bytes in font_data {
        sizes := [?]i32{16, 32}
        for size in sizes {
            codepoints := [?]rune{'A', 'g', 'j', 'é', ' ', 0xffff}
            font := rl.Font{baseSize = size, glyphPadding = 4}
            font.glyphs = rl.LoadFontData(raw_data(bytes), i32(len(bytes)), size, raw_data(codepoints[:]), len(codepoints), .DEFAULT, &font.glyphCount)
            if !testing.expect(t, font.glyphs != nil) do return
            defer rl.UnloadFontData(font.glyphs, font.glyphCount)
            atlas := rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, size, font.glyphPadding, 1)
            defer rl.UnloadImage(atlas)
            defer rl.MemFree(font.recs)
            if !testing.expect(t, rl.IsImageValid(atlas) && font.recs != nil) do return

            if !testing.expect(t, font_raster_atlas_has_padding(font, atlas)) do return
            // Force the j's native mask beyond the padding it can borrow.
            font.glyphs[2].offsetX += 3
            glyphs := slice.clone(font.glyphs[:font.glyphCount])
            defer delete(glyphs)
            recs := slice.clone(font.recs[:font.glyphCount])
            defer delete(recs)
            pixels := ([^][2]u8)(atlas.data)[:int(atlas.width) * int(atlas.height)]
            before := slice.clone(pixels)
            defer delete(before)

            testing.expect_value(t, font_raster_repaint_darwin({}, &font, atlas), 0)
            testing.expect(t, slice.equal(pixels, before))
            padding := font.glyphPadding
            count := font_raster_repaint_darwin(bytes, &font, atlas)
            testing.expect(t, count >= 2, "expected CTFontDrawGlyphs masks at both sizes and for both bundled fonts")
            testing.expect(t, font.glyphPadding >= padding / 2 && font.glyphPadding <= padding)
            for glyph, i in glyphs {
                rec, updated := recs[i], font.recs[i]
                if i == 2 || i == 4 || i == 5 {
                    testing.expect_value(t, font.glyphs[i], glyph)
                    testing.expect_value(t, updated, rec)
                }
                testing.expect_value(t, f32(font.glyphs[i].offsetX - glyph.offsetX), updated.x - rec.x)
                testing.expect_value(t, f32(font.glyphs[i].offsetY - glyph.offsetY), updated.y - rec.y)
                testing.expect_value(t, font.glyphs[i].advanceX, glyph.advanceX)
                testing.expect_value(t, font.glyphs[i].value, glyph.value)
                testing.expect(t, updated.x >= rec.x - f32(padding / 2) && updated.y >= rec.y - f32(padding / 2))
                testing.expect(t, updated.x + updated.width <= rec.x + rec.width + f32(padding / 2))
                testing.expect(t, updated.y + updated.height <= rec.y + rec.height + f32(padding / 2))
            }

            has_clear, has_edge, has_solid := false, false, false
            changed := 0
            for pixel, index in pixels {
                has_clear = has_clear || pixel[1] == 0
                has_edge = has_edge || (pixel[1] > 0 && pixel[1] < 255)
                has_solid = has_solid || pixel[1] == 255
                if pixel == before[index] do continue
                changed += 1
                testing.expect_value(t, pixel[0], before[index][0])
                x, y := f32(index % int(atlas.width)), f32(index / int(atlas.width))
                repainted_slots := [?]int{0, 1, 3}
                inside := false
                for i in repainted_slots {
                    rect := font.recs[i]
                    if x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height {
                        inside = true
                        break
                    }
                }
                testing.expect(t, inside, "changed padding, blank, unmapped, or overflowing glyph")
            }
            testing.expect(t, changed > 0)
            testing.expect(t, has_clear && has_edge && has_solid)

            // Foreground alpha belongs to the compositor, not the cached mask.
            after := slice.clone(pixels)
            defer delete(after)
            copy(pixels, before)
            copy(font.glyphs[:font.glyphCount], glyphs)
            copy(font.recs[:font.glyphCount], recs)
            font.glyphPadding = padding
            transparent_ink := rl.Color{255, 255, 255, 0}
            testing.expect_value(t, font_raster_repaint_darwin(bytes, &font, atlas, transparent_ink), count)
            testing.expect(t, slice.equal(pixels, after))
        }
    }
}

@(test)
test_font_raster_darwin_em_dash_case_offset :: proc(t: ^testing.T) {
    bytes := #load("fonts/Inter-Regular.ttf")
    sizes := [?]i32{24, 48}
    for size in sizes {
        codepoints := [?]rune{'A', '—', ' '}
        font := rl.Font{baseSize = size, glyphPadding = 4}
        font.glyphs = rl.LoadFontData(raw_data(bytes), i32(len(bytes)), size, raw_data(codepoints[:]), len(codepoints), .DEFAULT, &font.glyphCount)
        if !testing.expect(t, font.glyphs != nil) do return
        defer rl.UnloadFontData(font.glyphs, font.glyphCount)
        atlas := rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, size, font.glyphPadding, 1)
        defer rl.UnloadImage(atlas)
        defer rl.MemFree(font.recs)
        if !testing.expect(t, rl.IsImageValid(atlas) && font.recs != nil && font_raster_atlas_has_padding(font, atlas)) do return

        half_rows: i32
        if size == 24 {
            half_rows = font_raster_expand_half_darwin(&atlas)
            if !testing.expect(t, half_rows > 0) do return
        }
        glyph := font.glyphs[1]
        rec := font.recs[1]
        placement: Font_Raster_Placement
        testing.expect_value(t, font_raster_repaint_darwin(bytes, &font, atlas, rl.WHITE, &placement, half_rows), 2)
        testing.expect(t, placement.native[1])
        testing.expect_value(t, placement.em_dash_case_y, -size / 24)
        testing.expect_value(t, placement.half_rows, half_rows)
        testing.expect_value(t, font.glyphs[1].advanceX, glyph.advanceX)
        // The normal (lowercase) mask's raster placement is not moved.
        testing.expect_value(t, f32(font.glyphs[1].offsetY - glyph.offsetY), font.recs[1].y - rec.y)
    }
}

@(test)
test_font_raster_darwin_half_plane :: proc(t: ^testing.T) {
    bytes := #load("fonts/Inter-Regular.ttf")
    codepoints := [?]rune{'A', 'o', ' ', 0xffff}
    font := rl.Font{baseSize = 24, glyphPadding = 4}
    font.glyphs = rl.LoadFontData(raw_data(bytes), i32(len(bytes)), 24, raw_data(codepoints[:]), len(codepoints), .DEFAULT, &font.glyphCount)
    if !testing.expect(t, font.glyphs != nil) do return
    defer rl.UnloadFontData(font.glyphs, font.glyphCount)
    atlas := rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, 24, font.glyphPadding, 1)
    defer rl.UnloadImage(atlas)
    defer rl.MemFree(font.recs)
    if !testing.expect(t, rl.IsImageValid(atlas) && font.recs != nil && font_raster_atlas_has_padding(font, atlas)) do return

    rows := atlas.height
    if !testing.expect_value(t, font_raster_expand_half_darwin(&atlas), rows) do return
    testing.expect_value(t, atlas.height, 2 * rows)
    placement: Font_Raster_Placement
    testing.expect_value(t, font_raster_repaint_darwin(bytes, &font, atlas, rl.WHITE, &placement, rows), 2)
    testing.expect_value(t, placement.half_rows, rows)
    testing.expect(t, placement.native[0] && placement.native[1])
    testing.expect(t, !placement.native[2] && !placement.native[3])

    pixels := ([^][2]u8)(atlas.data)[:int(atlas.width) * int(atlas.height)]
    plane := int(atlas.width) * int(rows)
    for r in font.recs[:2] {
        sum, changes := 0, 0
        for y in int(r.y)..<int(r.y + r.height) {
            for x in int(r.x)..<int(r.x + r.width) {
                j := y * int(atlas.width) + x
                sum += int(pixels[j + plane][1])
                if pixels[j + plane][1] != pixels[j][1] do changes += 1
            }
        }
        testing.expect(t, sum > 0 && changes > 0, "expected a distinct nonempty half-pixel mask")
    }
    for pixel, i in pixels[plane:] {
        if pixel[1] == 0 do continue
        x, y := f32(i % int(atlas.width)), f32(i / int(atlas.width))
        inside := false
        for r in font.recs[:2] {
            inside = inside || (r.x <= x && x < r.x + r.width && r.y <= y && y < r.y + r.height)
        }
        testing.expect(t, inside, "half-pixel ink outside its packed glyph slot")
    }
}
