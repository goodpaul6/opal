package main

import "base:intrinsics"
import rl "vendor:raylib"

FONT_PAIR_FIRST :: ' '
FONT_PAIR_COUNT :: 95 // Printable ASCII fast path.

Font_Extended_Pair :: struct {
    key: u32, // Two BMP codepoints in reading order.
    delta: f32,
}

Font_Pair_Row :: struct {
    bits: [2]u64,
    offset: [2]u16,
}

Font_Metrics :: struct {
    advances: []f32, // Indexed by logical atlas glyph index.
    pair_rows: [FONT_PAIR_COUNT]Font_Pair_Row,
    pairs: [dynamic]f32, // Store only nonzero deltas.
    extended_pairs: []Font_Extended_Pair, // Sorted by key; at least one rune is outside ASCII.
    pair_reference: ^Font_Metrics,
    pair_scale: f32,
}

Font_Pair_Cache :: struct {
    base_size: i32,
    metrics: Font_Metrics,
}

font_metrics_destroy :: proc(metrics: ^Font_Metrics) {
    delete(metrics.advances)
    delete(metrics.pairs)
    delete(metrics.extended_pairs)
    metrics^ = {}
}

// Install each row once at load. Offsets index the packed deltas by bitmap rank.
font_metrics_append_row :: proc(metrics: ^Font_Metrics, left: rune, deltas: []f32) {
    row := &metrics.pair_rows[left - FONT_PAIR_FIRST]
    for delta, right in deltas {
        if delta == 0 do continue
        block := right / 64
        if row.bits[block] == 0 do row.offset[block] = u16(len(metrics.pairs))
        row.bits[block] |= u64(1) << uint(right % 64)
        append(&metrics.pairs, delta)
    }
}

font_extended_pair_key :: proc(left, right: rune) -> u32 {
    return (u32(left) << 16) | u32(right)
}

font_pair_delta :: proc(metrics: ^Font_Metrics, left, right: rune) -> f32 {
    if metrics == nil do return 0
    if metrics.pair_reference != nil {
        return font_pair_lookup(metrics.pair_reference, left, right) * metrics.pair_scale
    }
    return font_pair_lookup(metrics, left, right)
}

@(private="file")
font_pair_lookup :: proc(metrics: ^Font_Metrics, left, right: rune) -> f32 {
    l, r := left - FONT_PAIR_FIRST, right - FONT_PAIR_FIRST
    if l < 0 || l >= FONT_PAIR_COUNT || r < 0 || r >= FONT_PAIR_COUNT {
        if left < FONT_PAIR_FIRST || left > 0xffff || right < FONT_PAIR_FIRST || right > 0xffff do return 0
        key := font_extended_pair_key(left, right)
        lo, hi := 0, len(metrics.extended_pairs)
        for lo < hi {
            mid := lo + (hi - lo) / 2
            entry := metrics.extended_pairs[mid]
            if key == entry.key do return entry.delta
            if key < entry.key do hi = mid
            else do lo = mid + 1
        }
        return 0
    }
    row := &metrics.pair_rows[l]
    block := r / 64
    bit := u64(1) << uint(r % 64)
    bits := row.bits[block]
    if bits & bit == 0 do return 0
    rank := intrinsics.count_ones(bits & (bit - 1))
    return metrics.pairs[int(row.offset[block]) + int(rank)]
}

font_atlas_advance :: proc(font: ^rl.Font, index: i32) -> f32 {
    advance := font.glyphs[index].advanceX
    return advance != 0 ? f32(advance) : font.recs[index].width
}
