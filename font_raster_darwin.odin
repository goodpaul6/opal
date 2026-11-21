package main

import "core:math"
import "core:hash"
import "core:mem"
import "core:slice"
import rl "vendor:raylib"

foreign import CoreFoundation "system:CoreFoundation.framework"
foreign import CoreGraphics "system:CoreGraphics.framework"
foreign import CoreText "system:CoreText.framework"

@(private="file")
CG_Point :: struct { x, y: f64 }
@(private="file")
CG_Rect :: struct { x, y, width, height: f64 }
@(private="file")
CF_Range :: struct { location, length: int }

@(private="file", default_calling_convention="c")
foreign CoreFoundation {
    CFRelease :: proc(object: rawptr) ---
    CFEqual :: proc(a, b: rawptr) -> bool ---
    CFDictionaryGetValue :: proc(dict, key: rawptr) -> rawptr ---
    CFDataGetLength :: proc(data: rawptr) -> int ---
    CFDataGetBytePtr :: proc(data: rawptr) -> [^]u8 ---
    CFArrayGetCount :: proc(array: rawptr) -> int ---
    CFArrayGetValueAtIndex :: proc(array: rawptr, index: int) -> rawptr ---
    CFStringCreateMutable :: proc(allocator: rawptr, max_length: int) -> rawptr ---
    CFStringDelete :: proc(str: rawptr, range: CF_Range) ---
    CFStringAppendCharacters :: proc(str: rawptr, chars: ^u16, count: int) ---
    CFAttributedStringCreateMutable :: proc(allocator: rawptr, max_length: int) -> rawptr ---
    CFAttributedStringReplaceString :: proc(str: rawptr, range: CF_Range, replacement: rawptr) ---
    CFAttributedStringSetAttribute :: proc(str: rawptr, range: CF_Range, name, value: rawptr) ---
}

@(private="file", default_calling_convention="c")
foreign CoreGraphics {
    CGDataProviderCreateWithData :: proc(info, data: rawptr, size: uint, release: rawptr) -> rawptr ---
    CGDataProviderRelease :: proc(provider: rawptr) ---
    CGFontCreateWithDataProvider :: proc(provider: rawptr) -> rawptr ---
    CGFontRelease :: proc(font: rawptr) ---
    CGFontGetUnitsPerEm :: proc(font: rawptr) -> i32 ---
    CGFontCopyTableForTag :: proc(font: rawptr, tag: u32) -> rawptr ---
    kCGColorSpaceSRGB: rawptr
    CGColorSpaceCreateWithName :: proc(name: rawptr) -> rawptr ---
    CGColorSpaceRelease :: proc(space: rawptr) ---
    CGBitmapContextCreate :: proc(data: rawptr, width, height, bits_per_component, bytes_per_row: uint, space: rawptr, bitmap_info: u32) -> rawptr ---
    CGContextRelease :: proc(ctx: rawptr) ---
    CGContextSetFillColorSpace :: proc(ctx, space: rawptr) ---
    CGContextSetFillColor :: proc(ctx: rawptr, components: ^f64) ---
    CGContextSetShouldAntialias :: proc(ctx: rawptr, enabled: bool) ---
    CGContextSetShouldSmoothFonts :: proc(ctx: rawptr, enabled: bool) ---
    CGContextSetShouldSubpixelPositionFonts :: proc(ctx: rawptr, enabled: bool) ---
    CGContextSetShouldSubpixelQuantizeFonts :: proc(ctx: rawptr, enabled: bool) ---
}

@(private="file", default_calling_convention="c")
foreign CoreText {
    CTFontCreateWithGraphicsFont :: proc(font: rawptr, size: f64, transform, attributes: rawptr) -> rawptr ---
    CTFontGetGlyphsForCharacters :: proc(font: rawptr, characters, glyphs: ^u16, count: int) -> bool ---
    CTFontGetBoundingRectsForGlyphs :: proc(font: rawptr, orientation: u32, glyphs: ^u16, rects: ^CG_Rect, count: int) -> CG_Rect ---
    CTFontDrawGlyphs :: proc(font: rawptr, glyphs: ^u16, positions: ^CG_Point, count: uint, ctx: rawptr) ---
    CTFontGetAdvancesForGlyphs :: proc(font: rawptr, orientation: u32, glyphs: ^u16, advances: ^CG_Point, count: int) -> f64 ---
    CTLineCreateWithAttributedString :: proc(str: rawptr) -> rawptr ---
    CTLineGetGlyphRuns :: proc(line: rawptr) -> rawptr ---
    CTLineGetTypographicBounds :: proc(line: rawptr, ascent, descent, leading: ^f64) -> f64 ---
    CTRunGetGlyphCount :: proc(run: rawptr) -> int ---
    CTRunGetAttributes :: proc(run: rawptr) -> rawptr ---
    CTRunGetStringIndices :: proc(run: rawptr, range: CF_Range, indices: ^int) ---
    CTRunGetGlyphs :: proc(run: rawptr, range: CF_Range, glyphs: ^u16) ---
    CTRunGetPositions :: proc(run: rawptr, range: CF_Range, positions: ^CG_Point) ---
    kCTFontAttributeName: rawptr
}

// Both raster and layout use the same hhea pixel-height scale as stbtt.
@(private="file")
font_darwin_create :: proc(bytes: []byte, size: i32, check_pairs := false) -> (ct_font: rawptr, baseline: int, has_pairs: bool) {
    if len(bytes) == 0 do return
    // The caller's bytes outlive the provider and both derived fonts.
    provider := CGDataProviderCreateWithData(nil, raw_data(bytes), uint(len(bytes)), nil)
    if provider == nil do return
    defer CGDataProviderRelease(provider)
    cg_font := CGFontCreateWithDataProvider(provider)
    if cg_font == nil do return
    defer CGFontRelease(cg_font)

    // Match stbtt_ScaleForPixelHeight and raylib's truncated hhea baseline.
    hhea := CGFontCopyTableForTag(cg_font, 0x68686561) // 'hhea'
    if hhea == nil do return
    defer CFRelease(hhea)
    if CFDataGetLength(hhea) < 8 do return
    data := CFDataGetBytePtr(hhea)
    ascent := i32(i16(u16(data[4]) << 8 | u16(data[5])))
    descent := i32(i16(u16(data[6]) << 8 | u16(data[7])))
    units_per_em := CGFontGetUnitsPerEm(cg_font)
    if ascent <= descent || units_per_em <= 0 do return
    scale := f32(size) / f32(ascent - descent)
    baseline = int(f32(ascent) * scale)
    ct_font = CTFontCreateWithGraphicsFont(cg_font, f64(scale) * f64(units_per_em), nil, nil)
    if check_pairs {
        // Skip the pair scan entirely for faces without pair positioning tables.
        tags := [?]u32{0x47504f53, 0x6b65726e, 0x6b657278} // GPOS, kern, kerx
        for tag in tags {
            table := CGFontCopyTableForTag(cg_font, tag)
            if table != nil {
                CFRelease(table)
                has_pairs = true
                break
            }
        }
    }
    return
}

// The caller uses raylib's skyline packer, which reserves the full padding
// on all sides. Failed packing can leave rectangles outside the image.
font_raster_atlas_has_padding :: proc(font: rl.Font, atlas: rl.Image) -> bool {
    padding := f32(font.glyphPadding)
    for i in 0..<font.glyphCount {
        rec := font.recs[i]
        if rec.x < padding || rec.y < padding || rec.x + rec.width + padding > f32(atlas.width) ||
           rec.y + rec.height + padding > f32(atlas.height) {
            return false
        }
    }
    return true
}

// At most one extra plane, capped at 2048 pixels per axis. Keeping both
// phases in one texture avoids a texture switch when adjacent phases differ.
font_raster_expand_half_darwin :: proc(atlas: ^rl.Image) -> i32 {
    if atlas.format != .UNCOMPRESSED_GRAY_ALPHA || atlas.width > 2048 || atlas.height > 1024 do return 0
    count := int(atlas.width) * int(atlas.height)
    data := rl.MemAlloc(u32(4 * count))
    if data == nil do return 0
    pixels := ([^][2]u8)(data)[:2 * count]
    copy(pixels[:count], ([^][2]u8)(atlas.data)[:count])
    for &pixel in pixels[count:] do pixel = {255, 0}
    rl.MemFree(atlas.data)
    atlas.data = data
    rows := atlas.height
    atlas.height *= 2
    return rows
}

@(private="file")
font_darwin_mask_bounds :: proc(bitmap: [][4]u8, stride, guard, w, h: int) -> (bounds: [4]int, has_ink: bool) {
    bounds = {0, 0, w, h}
    for pixel, i in bitmap {
        if pixel[3] == 0 do continue
        x, y := i % stride - guard, i / stride - guard
        bounds[0], bounds[1] = min(bounds[0], x), min(bounds[1], y)
        bounds[2], bounds[3] = max(bounds[2], x + 1), max(bounds[3], y + 1)
        has_ink = true
    }
    return
}

// Inter's default contextual alternates can substitute a raised em dash in
// cased text. Learn the displacement from the shaped glyph, not its glyph ID
// or a density-specific constant. Only reuse the mask for a vertical translation.
@(private="file")
font_darwin_em_dash_case_y :: proc(ct_font: rawptr, base: u16, bounds: CG_Rect) -> i32 {
    context_chars := [4]u16{'A', ' ', '—', ' '}
    str := CFStringCreateMutable(nil, len(context_chars))
    if str == nil do return 0
    defer CFRelease(str)
    CFStringAppendCharacters(str, &context_chars[0], len(context_chars))
    attributed := CFAttributedStringCreateMutable(nil, len(context_chars))
    if attributed == nil do return 0
    defer CFRelease(attributed)
    CFAttributedStringReplaceString(attributed, {0, 0}, str)
    CFAttributedStringSetAttribute(attributed, {0, len(context_chars)}, kCTFontAttributeName, ct_font)
    line := CTLineCreateWithAttributedString(attributed)
    if line == nil do return 0
    defer CFRelease(line)
    runs := CTLineGetGlyphRuns(line)
    if CFArrayGetCount(runs) != 1 do return 0
    run := CFArrayGetValueAtIndex(runs, 0)
    if CTRunGetGlyphCount(run) != len(context_chars) do return 0
    run_font := CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName)
    if run_font == nil || !CFEqual(run_font, ct_font) do return 0
    indices: [4]int
    CTRunGetStringIndices(run, {0, len(indices)}, &indices[0])
    if indices != ([4]int{0, 1, 2, 3}) do return 0
    alternate: u16
    CTRunGetGlyphs(run, {2, 1}, &alternate)
    if alternate == 0 || alternate == base do return 0
    base_glyph := base
    raised := CTFontGetBoundingRectsForGlyphs(ct_font, 0, &alternate, nil, 1)
    epsilon :: 0.0001
    if raised.y <= bounds.y || abs(raised.x - bounds.x) > epsilon ||
       abs(raised.width - bounds.width) > epsilon || abs(raised.height - bounds.height) > epsilon ||
       abs(CTFontGetAdvancesForGlyphs(ct_font, 0, &alternate, nil, 1) -
           CTFontGetAdvancesForGlyphs(ct_font, 0, &base_glyph, nil, 1)) > epsilon {
        return 0
    }
    return i32(math.round(bounds.y - raised.y))
}

// Repaint only complete masks. Borrow some of the packed padding if native
// ink extends outside the stb box, moving the source and offsets together.
font_raster_repaint_darwin :: proc(bytes: []byte, font: ^rl.Font, atlas: rl.Image, foreground := rl.WHITE,
                                   placement: ^Font_Raster_Placement = nil, half_rows: i32 = 0) -> int {
    if atlas.format != .UNCOMPRESSED_GRAY_ALPHA do return 0
    ct_font, baseline, _ := font_darwin_create(bytes, font.baseSize)
    if ct_font == nil do return 0
    defer CFRelease(ct_font)

    guard :: 4
    borrow := min(guard - 1, int(font.glyphPadding) / 2)
    width, height: int
    for i in 0..<font.glyphCount {
        width = max(width, int(font.recs[i].width))
        height = max(height, int(font.recs[i].height))
    }
    if width <= 0 || height <= 0 do return 0
    stride := (width + 2 * guard + 15) / 16 * 16
    rows := height + 2 * guard
    // An alpha-only surface misses CoreGraphics' color-dependent font smoothing.
    // Draw opaque ink on transparent sRGB and cache only the resulting alpha;
    // raylib supplies the color (and any opacity) when compositing the mask.
    space := CGColorSpaceCreateWithName(kCGColorSpaceSRGB)
    if space == nil do return 0
    defer CGColorSpaceRelease(space)
    bitmap := make([][4]u8, stride * rows)
    defer delete(bitmap)
    can_place := placement != nil && font.glyphCount <= FONT_RASTER_PHASE_LIMIT
    primary: [][4]u8
    if can_place && half_rows > 0 {
        primary = make([][4]u8, len(bitmap))
    }
    defer delete(primary)
    CG_IMAGE_ALPHA_PREMULTIPLIED_LAST :: 1
    CG_BITMAP_BYTE_ORDER_32_BIG :: 4 << 12
    ctx := CGBitmapContextCreate(raw_data(bitmap), uint(stride), uint(rows), 8, uint(4 * stride), space,
                                 CG_IMAGE_ALPHA_PREMULTIPLIED_LAST | CG_BITMAP_BYTE_ORDER_32_BIG)
    if ctx == nil do return 0
    defer CGContextRelease(ctx)
    components := [4]f64{f64(foreground.r) / 255, f64(foreground.g) / 255, f64(foreground.b) / 255, 1}
    CGContextSetFillColorSpace(ctx, space)
    CGContextSetFillColor(ctx, &components[0])
    CGContextSetShouldAntialias(ctx, true)
    CGContextSetShouldSmoothFonts(ctx, true)
    // Display snaps glyph origins to whole device pixels; cache that phase.
    CGContextSetShouldSubpixelPositionFonts(ctx, false)
    CGContextSetShouldSubpixelQuantizeFonts(ctx, false)

    pixels := ([^][2]u8)(atlas.data)
    repainted := 0
    borrowed := 0
    for i in 0..<font.glyphCount {
        rec := font.recs[i]
        glyph := font.glyphs[i]
        w, h := int(rec.width), int(rec.height)
        if w <= 0 || h <= 0 || glyph.value < 0 || glyph.value > 0xffff do continue
        character := u16(glyph.value)
        if character >= 0xd800 && character <= 0xdfff do continue
        glyph_id: u16
        if !CTFontGetGlyphsForCharacters(ct_font, &character, &glyph_id, 1) || glyph_id == 0 do continue

        // The bitmap's first row is the top, while CoreGraphics draws y-up.
        position := CG_Point{f64(guard - int(glyph.offsetX)), f64(rows - guard - baseline + int(glyph.offsetY))}
        bounds := CTFontGetBoundingRectsForGlyphs(ct_font, 0, &glyph_id, nil, 1)
        left, bottom := position.x + bounds.x, position.y + bounds.y
        // Leave space for antialiasing and rasterizer grid fitting outside the outline.
        if !(bounds.width > 0 && bounds.height > 0 && left >= 1 && bottom >= 1 &&
             left + bounds.width <= f64(stride - 1) && bottom + bounds.height <= f64(rows - 1)) {
            continue
        }
        mem.zero_slice(bitmap)
        CTFontDrawGlyphs(ct_font, &glyph_id, &position, 1, ctx)

        rect, has_ink := font_darwin_mask_bounds(bitmap, stride, guard, w, h)
        extra := max(-rect[0], -rect[1], rect[2] - w, rect[3] - h)
        // raylib uses rec.width for the advance when advanceX is zero.
        if !has_ink || extra > borrow || (glyph.advanceX == 0 && rect[2] - rect[0] != w) do continue

        base := bitmap
        has_half := false
        if len(primary) != 0 && left + 0.5 + bounds.width <= f64(stride - 1) {
            copy(primary, bitmap)
            base = primary
            mem.zero_slice(bitmap)
            position.x += 0.5
            CGContextSetShouldSubpixelPositionFonts(ctx, true)
            CTFontDrawGlyphs(ct_font, &glyph_id, &position, 1, ctx)
            CGContextSetShouldSubpixelPositionFonts(ctx, false)
            half, has_ink := font_darwin_mask_bounds(bitmap, stride, guard, w, h)
            union_rect := [4]int{min(rect[0], half[0]), min(rect[1], half[1]), max(rect[2], half[2]), max(rect[3], half[3])}
            union_extra := max(-union_rect[0], -union_rect[1], union_rect[2] - w, union_rect[3] - h)
            if has_ink && union_extra <= borrow && (glyph.advanceX != 0 || union_rect[2] - union_rect[0] == w) {
                rect, extra, has_half = union_rect, union_extra, true
            }
        }
        x0, y0, x1, y1 := rect[0], rect[1], rect[2], rect[3]
        for y in y0..<y1 {
            dest := (int(rec.y) + y) * int(atlas.width) + int(rec.x)
            src := (guard + y) * stride + guard
            for x in x0..<x1 {
                pixels[dest + x][1] = base[src + x][3]
                if has_half do pixels[dest + int(half_rows) * int(atlas.width) + x][1] = bitmap[src + x][3]
            }
        }
        if can_place {
            placement.native[i] = half_rows == 0 || has_half
            placement.half_rows = half_rows
            if character == '—' && placement.native[i] {
                placement.em_dash_case_y = font_darwin_em_dash_case_y(ct_font, glyph_id, bounds)
            }
        }
        font.recs[i] = {rec.x + f32(x0), rec.y + f32(y0), f32(x1 - x0), f32(y1 - y0)}
        font.glyphs[i].offsetX += i32(x0)
        font.glyphs[i].offsetY += i32(y0)
        borrowed = max(borrowed, extra)
        repainted += 1
    }
    font.glyphPadding -= i32(borrowed)
    return repainted
}

INTER_KERNING_REFERENCE_SIZE :: 24

bundled_inter_font_pairs :: proc(bytes: []byte) -> (cache: Font_Pair_Cache) {
    words := #load("fonts/Inter-kerning.bin", []u32le)
    codepoints := theme_font_codepoints()
    // The generated table belongs to this font and glyph repertoire. Fall
    // back to the CoreText scan if either changes before regeneration.
    if len(words) < 3 || len(words) % 2 != 1 ||
        u32(words[0]) != hash.crc32(bytes) ||
        u32(words[1]) != hash.crc32(mem.slice_to_bytes(codepoints[:])) {
        return
    }
    ascii_count := int(words[2])
    entries := words[3:]
    if ascii_count > len(entries) / 2 do return
    ascii_end := 2 * ascii_count
    reserve(&cache.metrics.pairs, ascii_count)
    pos := 0
    for l in 0..<FONT_PAIR_COUNT {
        left := FONT_PAIR_FIRST + rune(l)
        row: [FONT_PAIR_COUNT]f32
        for pos < ascii_end && u32(entries[pos]) >> 16 == u32(left) {
            right := rune(u16(entries[pos]))
            row[right - FONT_PAIR_FIRST] = transmute(f32)u32(entries[pos + 1])
            pos += 2
        }
        font_metrics_append_row(&cache.metrics, left, row[:])
    }
    cache.metrics.extended_pairs = make([]Font_Extended_Pair, len(entries[ascii_end:]) / 2)
    for &entry, i in cache.metrics.extended_pairs {
        pos := ascii_end + i * 2
        entry = {u32(entries[pos]), transmute(f32)u32(entries[pos + 1])}
    }
    cache.base_size = INTER_KERNING_REFERENCE_SIZE
    return
}

// Read layout metrics only for the logical atlas, never for a DPI-only reload.
font_metrics_load_darwin :: proc(bytes: []byte, font: ^rl.Font, pair_cache: ^Font_Pair_Cache = nil) -> (metrics: Font_Metrics) {
    cached := pair_cache != nil && pair_cache.base_size != 0
    ct_font, _, has_pairs := font_darwin_create(bytes, font.baseSize, !cached)
    if ct_font == nil do return
    defer CFRelease(ct_font)

    // Bound the quadratic load-time scan. Larger atlases retain ASCII pairs
    // and still get fractional advances for all directly mapped BMP glyphs.
    pair_limit :: 256
    Pair_Glyph :: struct { ch, glyph: u16, advance: f64 }
    candidates: [FONT_PAIR_COUNT + pair_limit]Pair_Glyph
    candidate_count := FONT_PAIR_COUNT
    metrics.advances = make([]f32, font.glyphCount)
    for i in 0..<font.glyphCount {
        value := font.glyphs[i].value
        metrics.advances[i] = font_atlas_advance(font, i)
        if value < 0 || value > 0xffff || (value >= 0xd800 && value <= 0xdfff) do continue
        ch := u16(value)
        glyph: u16
        if !CTFontGetGlyphsForCharacters(ct_font, &ch, &glyph, 1) || glyph == 0 do continue
        advance := CTFontGetAdvancesForGlyphs(ct_font, 0, &glyph, nil, 1)
        metrics.advances[i] = f32(advance)
        ascii := value - FONT_PAIR_FIRST
        if !has_pairs do continue
        if ascii >= 0 && ascii < FONT_PAIR_COUNT {
            candidates[ascii] = {ch, glyph, advance}
        } else if value >= 0xa0 && font.glyphCount <= pair_limit {
            candidates[candidate_count] = {ch, glyph, advance}
            candidate_count += 1
        }
    }
    if cached {
        metrics.pair_reference = &pair_cache.metrics
        metrics.pair_scale = f32(font.baseSize) / f32(pair_cache.base_size)
        return
    }
    if !has_pairs do return

    str := CFStringCreateMutable(nil, 2)
    if str == nil do return
    defer CFRelease(str)
    attributed := CFAttributedStringCreateMutable(nil, 2)
    if attributed == nil do return
    defer CFRelease(attributed)
    pair := [2]u16{' ', ' '}
    CFStringAppendCharacters(str, &pair[0], 2)
    CFAttributedStringReplaceString(attributed, {0, 0}, str)
    CFAttributedStringSetAttribute(attributed, {0, 2}, kCTFontAttributeName, ct_font)

    // Visit in codepoint order so sparse entries are already sorted for lookup.
    slice.sort_by(candidates[FONT_PAIR_COUNT:candidate_count], proc(a, b: Pair_Glyph) -> bool { return a.ch < b.ch })
    extended: [dynamic]Font_Extended_Pair
    defer delete(extended)
    for left, l in candidates[:candidate_count] {
        if left.glyph == 0 || (l > FONT_PAIR_COUNT && left.ch == candidates[l - 1].ch) do continue
        row: [FONT_PAIR_COUNT]f32
        pair[0] = left.ch
        for right, r in candidates[:candidate_count] {
            if right.glyph == 0 || (r > FONT_PAIR_COUNT && right.ch == candidates[r - 1].ch) do continue
            pair[1] = right.ch
            CFStringDelete(str, {0, 2})
            CFStringAppendCharacters(str, &pair[0], 2)
            CFAttributedStringReplaceString(attributed, {0, 2}, str)
            line := CTLineCreateWithAttributedString(attributed)
            if line == nil do continue
            delta := font_darwin_pair_delta(line, ct_font, {left.glyph, right.glyph}, left.advance, right.advance)
            CFRelease(line)
            if l < FONT_PAIR_COUNT && r < FONT_PAIR_COUNT {
                row[r] = delta
            } else if delta != 0 {
                append(&extended, Font_Extended_Pair{font_extended_pair_key(rune(left.ch), rune(right.ch)), delta})
            }
        }
        if l < FONT_PAIR_COUNT do font_metrics_append_row(&metrics, rune(left.ch), row[:])
    }
    if len(extended) != 0 do metrics.extended_pairs = slice.clone(extended[:])
    if pair_cache != nil {
        pair_cache.base_size = font.baseSize
        pair_cache.metrics.pair_rows = metrics.pair_rows
        pair_cache.metrics.pairs = metrics.pairs
        pair_cache.metrics.extended_pairs = metrics.extended_pairs
        metrics.pair_rows = {}
        metrics.pairs = nil
        metrics.extended_pairs = nil
        metrics.pair_reference = &pair_cache.metrics
        metrics.pair_scale = 1
    }
    return
}

@(private="file")
font_darwin_pair_delta :: proc(line, ct_font: rawptr, expected: [2]u16, left, right: f64) -> f32 {
    epsilon :: 0.0001
    delta := CTLineGetTypographicBounds(line, nil, nil, nil) - (left + right)
    if abs(delta) < epsilon do return 0
    runs := CTLineGetGlyphRuns(line)
    if CFArrayGetCount(runs) != 1 do return 0
    run := CFArrayGetValueAtIndex(runs, 0)
    if CTRunGetGlyphCount(run) != 2 do return 0
    glyphs: [2]u16
    CTRunGetGlyphs(run, {0, 2}, &glyphs[0])
    if glyphs != expected do return 0
    run_font := CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName)
    if run_font == nil || !CFEqual(run_font, ct_font) do return 0
    indices: [2]int
    CTRunGetStringIndices(run, {0, 2}, &indices[0])
    if indices != ([2]int{0, 1}) do return 0

    // Accept only adjustments expressible by moving the second pen origin;
    // this deliberately excludes ligatures and other contextual positioning.
    positions: [2]CG_Point
    CTRunGetPositions(run, {0, 2}, &positions[0])
    if positions[0] != (CG_Point{}) || positions[1].y != 0 do return 0
    if abs(positions[1].x - (left + delta)) > epsilon do return 0
    return f32(delta)
}
