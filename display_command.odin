package main

import "core:math"
import "core:unicode"
import "core:unicode/utf8"
import rlgl "vendor:raylib/rlgl"
import rl "vendor:raylib"

Display_Command_Text :: struct {
    text: string,
    font: ^rl.Font,
    color: rl.Color,
}

Display_Command_Rect :: struct {
    w, h: f32,
    color: rl.Color,
    floor_left: bool, // Keep a glyph's quantized left edge inside the block caret.
}

Display_Dash_Context :: struct {
    source: string,
    start: int, // Byte offset of this draw chunk in the source.
}

Display_Command :: struct {
    pos: [2]f32,
    previous: rune, // Carry same-font pair context into a separately emitted text chunk.
    dash_context: Display_Dash_Context,
    sub: union #no_nil {
        Display_Command_Text,
        Display_Command_Rect,
    }
}

// Advance in logical pixels; only final rendering snaps to the framebuffer.
Display_Pen :: struct {
    x: f32,
    previous: rune,
}

display_glyph_advance :: proc(font: ^rl.Font, ch: rune, metrics: ^Font_Metrics = nil) -> f32 {
    index := rl.GetGlyphIndex(font^, ch == '	' ? ' ' : ch)
    if metrics != nil && len(metrics.advances) != 0 do return metrics.advances[index]
    return font_atlas_advance(font, index)
}

display_pen_step :: proc(pen: ^Display_Pen, font: ^rl.Font, metrics: ^Font_Metrics, ch: rune) -> f32 {
    x := pen.x + font_pair_delta(metrics, pen.previous, ch)
    pen.x = x + display_glyph_advance(font, ch, metrics)
    pen.previous = ch
    return x
}

display_text_width :: proc(font: ^rl.Font, text: string, metrics: ^Font_Metrics = nil) -> f32 {
    pen: Display_Pen
    for ch in text do display_pen_step(&pen, font, metrics, ch)
    return pen.x
}

@(private="file")
display_font_variant :: proc(theme: ^Theme, font: ^rl.Font) -> (variant: Theme_Font_Variant, ok: bool) {
    for v in Theme_Font_Variant {
        if font == &theme.fonts[v] do return v, true
    }
    return
}

@(private="file")
display_raster_font :: proc(theme: ^Theme, font: ^rl.Font) -> ^rl.Font {
    if variant, ok := display_font_variant(theme, font); ok && theme.native_fonts[variant].texture.id != 0 {
        return &theme.native_fonts[variant]
    }
    return font
}

// At default body zoom Quartz uses the lower half-pixel bin at 1x and
// the lower whole-pixel bin at 2x. Only use this for complete native masks.
@(private="file")
display_glyph_placement :: proc(theme: ^Theme, font, raster: ^rl.Font, index: i32) -> (floor_x: bool, half_rows: i32) {
    when ODIN_OS == .Darwin {
        if font != &theme.fonts[.BODY] || index < 0 || index >= FONT_RASTER_PHASE_LIMIT do return
        if theme.pixel_scale == {1, 1} && raster == font {
            p := &theme.body_placement
            if p.half_rows > 0 && p.native[index] do return true, p.half_rows
        } else if theme.pixel_scale == {2, 2} && raster == &theme.native_fonts[.BODY] {
            return theme.native_body_placement.native[index], 0
        }
    }
    return
}

// Quantize only after the viewport offset is included. The fractional part
// selects a baked mask; destination coordinates remain device-pixel aligned.
display_glyph_phase :: proc(device_x: f32, half_rows: i32) -> (x: f32, rows: i32) {
    x = math.floor(device_x)
    if device_x - x >= 0.5 do rows = half_rows
    return
}

// Handle the spaced form of Inter's case alternate without a shaping call
// during drawing. Only look across up to two spaces, not other punctuation.
display_em_dash_in_case_context :: proc(before, after: string) -> bool {
    is_space :: proc(ch: rune) -> bool { return ch == ' ' || ch == '\t' || ch == 0xa0 }
    is_boundary :: proc(ch: rune) -> bool { return ch == 0 || ch == '\n' || is_space(ch) }
    is_cap :: proc(ch: rune) -> bool { return (ch <= 0xff && unicode.is_upper(ch)) || ('0' <= ch && ch <= '9') }

    left, l := utf8.decode_last_rune(before)
    right, r := utf8.decode_rune(after)
    if (len(before) != 0 && !is_boundary(left)) || (len(after) != 0 && !is_boundary(right)) do return false
    prefix, suffix := before, after
    for _ in 0..<2 {
        if is_space(left) {
            prefix = prefix[:len(prefix) - l]
            left, l = utf8.decode_last_rune(prefix)
        }
        if is_space(right) {
            suffix = suffix[r:]
            right, r = utf8.decode_rune(suffix)
        }
    }
    return is_cap(left) || is_cap(right)
}

display_draw_text :: proc(
    theme: ^Theme, font: ^rl.Font, text: string, pos: [2]f32, color: rl.Color,
    previous: rune = 0, origin: [2]f32 = {}, dash_context: Display_Dash_Context = {},
) {
    raster := display_raster_font(theme, font)
    metrics: ^Font_Metrics
    if variant, ok := display_font_variant(theme, font); ok do metrics = &theme.font_metrics[variant]
    pen := Display_Pen{pos.x, previous}
    case_y: i32
    dash := dash_context
    when ODIN_OS == .Darwin {
        if font == &theme.fonts[.BODY] {
            if theme.pixel_scale == {1, 1} && raster == font {
                case_y = theme.body_placement.em_dash_case_y
            } else if theme.pixel_scale == {2, 2} && raster == &theme.native_fonts[.BODY] {
                case_y = theme.native_body_placement.em_dash_case_y
            }
        }
        if dash.source == "" do dash = {text, 0}
    }
    for ch, offset in text {
        x := display_pen_step(&pen, font, metrics, ch)
        if ch != ' ' && ch != '	' {
            index := rl.GetGlyphIndex(raster^, ch)
            src := raster.recs[index]
            if src.width > 0 && src.height > 0 {
                p := [2]f32{x, pos.y} + origin
                dst := display_glyph_destination(theme.pixel_scale, p, src, raster.glyphs[index])
                if use_floor, half_rows := display_glyph_placement(theme, font, raster, index); use_floor {
                    device_x, rows := display_glyph_phase(p.x * theme.pixel_scale.x, half_rows)
                    dst.x = (device_x + f32(raster.glyphs[index].offsetX)) / theme.pixel_scale.x
                    src.y += f32(rows)
                }
                if ch == '—' && case_y != 0 {
                    at := dash.start + offset
                    if display_em_dash_in_case_context(dash.source[:at], dash.source[at + len("—"):]) {
                        dst.y += f32(case_y) / theme.pixel_scale.y
                    }
                }
                rl.DrawTexturePro(raster.texture, src, dst, {}, 0, color)
            }
        }
    }
}

// Only the rendered origin is rounded. Offsets and extents already belong to
// the native bitmap, so each atlas texel covers exactly one framebuffer pixel.
display_glyph_destination :: proc(scale, pos: [2]f32, src: rl.Rectangle, glyph: rl.GlyphInfo) -> rl.Rectangle {
    origin := display_round_pixel(pos * scale) + {f32(glyph.offsetX), f32(glyph.offsetY)}
    return {origin.x / scale.x, origin.y / scale.y, src.width / scale.x, src.height / scale.y}
}

@(private="file")
display_round_pixel :: proc(pos: [2]f32) -> [2]f32 {
    return {math.round(pos.x), math.round(pos.y)}
}

@(private="file")
display_rect_pixel_edges :: proc(scale: [2]f32, rect: rl.Rectangle) -> (top_left, bottom_right: [2]f32) {
    top_left = display_round_pixel([2]f32{rect.x, rect.y} * scale)
    bottom_right = display_round_pixel([2]f32{rect.x + rect.width, rect.y + rect.height} * scale)
    return
}

display_snap_rect :: proc(theme: ^Theme, rect: rl.Rectangle, floor_left := false) -> rl.Rectangle {
    scale := theme.pixel_scale
    top_left, bottom_right := display_rect_pixel_edges(scale, rect)
    if floor_left do top_left.x = math.floor(rect.x * scale.x)
    pos := top_left / scale
    size := (bottom_right - top_left) / scale
    return {pos.x, pos.y, size.x, size.y}
}

display_begin_scissor :: proc(theme: ^Theme, rect: rl.Rectangle, logical_height: i32) {
    top_left, bottom_right := display_rect_pixel_edges(theme.pixel_scale, rect)
    size := bottom_right - top_left
    framebuffer_height := math.round(f32(logical_height) * theme.pixel_scale.y)
    // Unlike BeginScissorMode, this takes native pixels for both a window and
    // a render texture, and doesn't consult the window DPI for an offscreen target.
    rlgl.DrawRenderBatchActive()
    rlgl.EnableScissorTest()
    rlgl.Scissor(i32(top_left.x), i32(framebuffer_height - bottom_right.y), i32(size.x), i32(size.y))
}

@(private="file")
display_line_variant :: proc(line: Markdown_Line) -> Theme_Font_Variant {
    if line.fenced do return .PRE
    variants := THEME_HEADING_VARIANTS
    if 1 <= line.heading_level && line.heading_level <= len(variants) {
        return variants[line.heading_level - 1]
    }
    return .BODY
}

@(private="file")
display_blank_caret :: proc(font: ^rl.Font, metrics: ^Font_Metrics, normal: bool, pos: [2]f32, height: f32) -> rl.Rectangle {
    width: f32 = INSERT_CARET_W
    if normal do width = max(width, display_glyph_advance(font, ' ', metrics))
    return {pos.x, pos.y, width, height}
}

@(private="file")
display_block_bounds :: proc(theme: ^Theme, font: ^rl.Font, ch: rune, pos: [2]f32, advance: f32) -> (rect: rl.Rectangle, has_ink: bool) {
    rect = {pos.x, pos.y, max(f32(INSERT_CARET_W), advance), f32(font.baseSize)}
    if ch == ' ' || ch == '\t' do return

    raster := display_raster_font(theme, font)
    index := rl.GetGlyphIndex(raster^, ch)
    src := raster.recs[index]
    if src.width <= 0 || src.height <= 0 do return

    // Include the native bitmap's overhang relative to the pen. Leave origin
    // snapping until draw time, when the viewport offset is known.
    ink := display_glyph_destination(theme.pixel_scale, {}, src, raster.glyphs[index])
    left, top := min(0, ink.x), min(0, ink.y)
    right, bottom := max(rect.width, ink.x + ink.width), max(rect.height, ink.y + ink.height)
    return {pos.x + left, pos.y + top, right - left, bottom - top}, true
}

// Layout emits one stack value at a time. A nil sink measures only the caret.
Display_Emit :: proc(data: rawptr, cmd: Display_Command)

@(private="file")
display_line_height :: proc(theme: ^Theme, variant: Theme_Font_Variant) -> f32 {
    return math.round(f32(theme.fonts[variant].baseSize) * max(1, theme.data.line_spacing))
}

@(private="file")
display_block_inset :: proc(theme: ^Theme, line: Markdown_Line, width: f32) -> f32 {
    if (line.fenced && theme.data.code_background.a != 0) ||
       (line.quoted && theme.data.accent_color.a != 0) {
        return min(width / 4, f32(theme.fonts[.BODY].baseSize) / 2)
    }
    return 0
}

@(private="file")
display_emit_block_row :: proc(emit: Display_Emit, emit_data: rawptr, theme: ^Theme, line: Markdown_Line, y, width, height: f32) {
    if line.fenced && theme.data.code_background.a != 0 {
        emit(emit_data, Display_Command{pos = {0, y}, sub = Display_Command_Rect{w = width, h = height, color = theme.data.code_background}})
    } else if line.quoted && theme.data.accent_color.a != 0 {
        emit(emit_data, Display_Command{pos = {0, y}, sub = Display_Command_Rect{w = 2, h = height, color = theme.data.accent_color}})
    }
}

// A checkpoint starts a physical line, before the parser classifies it.
DISPLAY_CHECKPOINT_SPACING :: 1024
Display_Checkpoint :: struct {
    offset: int,
    y: f32,
    fence_length: int,
    fence_marker: byte,
}

display_invalidate_from :: proc(ed: ^Editor, offset: int) {
    checkpoints := &ed.display.checkpoints
    for len(checkpoints) > 0 && checkpoints[len(checkpoints) - 1].offset > offset {
        pop(checkpoints)
    }
    ed.should_scroll_cursor_into_view = true
}

@(private="file")
display_find_checkpoint :: proc(checkpoints: []Display_Checkpoint, offset: int, y: f32) -> Display_Checkpoint {
    lo, hi := 0, len(checkpoints)
    for lo < hi {
        mid := lo + (hi - lo) / 2
        checkpoint := checkpoints[mid]
        if checkpoint.offset <= offset && checkpoint.y <= y do lo = mid + 1
        else do hi = mid
    }
    return checkpoints[lo - 1] if lo > 0 else {}
}

// Return the caret rectangle for scrolling the cursor into view.
display_command_gen :: proc(
    ed: ^Editor,
    theme: ^Theme,
    bounds_size: [2]f32,
    emit: Display_Emit = nil,
    emit_data: rawptr = nil,
    stop_y: f32 = -1,
    viewport_top: f32 = -max(f32),
) -> (caret_rect: rl.Rectangle) {
    // TODO(Apaar): Handle selection and horizontal scroll
    src := string(ed.sb.buf[:])
    sel_pos := ed.state.selection[0]
    normal := ed.mode == .NORMAL
    cursor_glyph: Display_Command_Text
    cursor_glyph_pos: [2]f32
    cursor_dash_context: Display_Dash_Context

    draw_pos: [2]f32
    body_height := display_line_height(theme, .BODY)
    checkpoint: Display_Checkpoint
    last_checkpoint_offset := 0
    use_checkpoints := viewport_top != -max(f32)
    if use_checkpoints {
        if ed.display.checkpoint_width != bounds_size.x || ed.display.checkpoint_zoom != theme.zoom_level {
            clear(&ed.display.checkpoints)
            ed.display.checkpoint_width = bounds_size.x
            ed.display.checkpoint_zoom = theme.zoom_level
        }
        if len(ed.display.checkpoints) > 0 {
            last_checkpoint_offset = ed.display.checkpoints[len(ed.display.checkpoints) - 1].offset
        }
        if emit == nil {
            checkpoint = display_find_checkpoint(ed.display.checkpoints[:], sel_pos, max(f32))
        } else {
            // Keep the same glyph overhang allowance as display_command_draw.
            max_height := max(body_height, f32(theme.fonts[.PRE].baseSize), f32(theme.fonts[.H1].baseSize))
            if theme.zoom_level < len(theme.data.zoom_level_to_font_sizes) {
                sizes := theme.data.zoom_level_to_font_sizes[theme.zoom_level]
                max_height = max(max_height, f32(sizes[.PRE]), f32(sizes[.H1]))
            }
            slack := 2 * max_height
            checkpoint = display_find_checkpoint(ed.display.checkpoints[:], len(src), viewport_top - slack)
        }
    }
    p := Parser{
        lex = {src[checkpoint.offset:], checkpoint.offset},
        line_start = checkpoint.offset,
        fence_length = checkpoint.fence_length,
        fence_marker = checkpoint.fence_marker,
    }
    draw_pos.y = checkpoint.y
    line_height := body_height
    line_variant := Theme_Font_Variant.BODY
    if p.fence_length != 0 {
        line_variant = .PRE
        theme_ensure_font(theme, .PRE)
        line_height = max(body_height, display_line_height(theme, .PRE))
    }
    previous_variant := line_variant
    previous: rune
    decorated := false

    layout: for node in parser_next_node(&p) {
        if emit == nil && caret_rect.height > 0 do break
        if stop_y >= 0 && draw_pos.y >= stop_y do break
        line_variant = display_line_variant(p.line)
        theme_ensure_font(theme, line_variant)
        min_line_height := max(body_height, display_line_height(theme, line_variant))
        line_height = max(line_height, min_line_height)
        inset := display_block_inset(theme, p.line, bounds_size.x)
        text_width := bounds_size.x - inset * 2
        start, end := node.extents[0], node.extents[1]
        // Half-open extents assign each caret offset once. A newline owns
        // the caret before it, not the caret at the start of the next line.
        contains_caret := start <= sel_pos && sel_pos < end

        #partial switch sub in node.sub {
            case Node_Newline:
                if emit != nil && !decorated {
                    display_emit_block_row(emit, emit_data, theme, p.line, draw_pos.y, bounds_size.x, line_height)
                }
                if contains_caret {
                    caret_rect = display_blank_caret(&theme.fonts[line_variant], &theme.font_metrics[line_variant], normal,
                                                     {draw_pos.x + inset, draw_pos.y}, line_height)
                }
                draw_pos = {0, draw_pos.y + line_height}
                decorated = false
                // The parser classifies the next physical line on demand. At
                // EOF, a trailing newline leaves an empty row in the fence (if open).
                line_variant = p.fence_length != 0 ? .PRE : .BODY
                line_height = body_height
                if p.fence_length != 0 do line_height = max(body_height, display_line_height(theme, .PRE))
                previous = 0
                if use_checkpoints && end - last_checkpoint_offset >= DISPLAY_CHECKPOINT_SPACING {
                    append(&ed.display.checkpoints, Display_Checkpoint{end, draw_pos.y, p.fence_length, p.fence_marker})
                    last_checkpoint_offset = end
                }

            case Node_Text:
                variant := sub.pre ? Theme_Font_Variant.PRE : line_variant
                heading_code := sub.pre && !p.line.fenced && p.line.heading_level > 0
                if heading_code {
                    code_variants := THEME_HEADING_CODE_VARIANTS
                    variant = code_variants[p.line.heading_level - 1]
                }
                if variant != line_variant do theme_ensure_font(theme, variant)
                prose_height := f32(theme.fonts[line_variant].baseSize)
                row_top := (min_line_height - prose_height) / 2 if theme.data.line_spacing > 1 else 0
                offset_y := row_top
                if heading_code || (sub.pre && !p.line.fenced && theme.data.line_spacing > 1) {
                    offset_y += theme_code_offset(theme, line_variant, variant)
                }
                font := &theme.fonts[variant]
                metrics := &theme.font_metrics[variant]
                font_height := f32(font.baseSize)
                text := sub.text
                if variant != previous_variant do previous = 0
                previous_variant = variant

                pen := Display_Pen{draw_pos.x, previous}
                for ch in text do display_pen_step(&pen, font, metrics, ch)
                if draw_pos.x > 0 && pen.x > text_width {
                    // Drop whitespace at a soft wrap. If the logical line
                    // ends here, don't add an extra visual line before it.
                    if !sub.all_spaces || (end < len(src) && src[end] != '\n') {
                        draw_pos = {0, draw_pos.y + line_height}
                        line_height = min_line_height
                        previous = 0
                        decorated = false
                    }
                    if sub.all_spaces {
                        if contains_caret {
                            caret_rect = display_blank_caret(&theme.fonts[line_variant], &theme.font_metrics[line_variant], normal,
                                                             {draw_pos.x + inset, draw_pos.y}, line_height)
                        }
                        continue
                    }
                    // The first pair on the new row no longer has a predecessor.
                    pen = {}
                    for ch in text do display_pen_step(&pen, font, metrics, ch)
                }

                // Most tokens fit unchanged. Split oversized ones at rune
                // boundaries and always allow at least one glyph per row.
                split_token := pen.x > text_width
                chunk_start := 0
                for chunk_start < len(text) {
                    if stop_y >= 0 && draw_pos.y >= stop_y do break layout
                    chunk_end := len(text)
                    if split_token {
                        pen = {draw_pos.x, previous}
                        for ch, offset in text[chunk_start:] {
                            next_pen := pen
                            display_pen_step(&next_pen, font, metrics, ch)
                            if offset > 0 && next_pen.x > text_width {
                                chunk_end = chunk_start + offset
                                break
                            }
                            pen = next_pen
                        }
                    }

                    if emit != nil {
                        if !decorated {
                            display_emit_block_row(emit, emit_data, theme, p.line, draw_pos.y, bounds_size.x, line_height)
                            decorated = true
                        }
                        color := theme.data.fg_color
                        if p.line.quoted && theme.data.accent_color.a == 0 {
                            color = rl.ColorLerp(color, theme.data.bg_color, 0.25)
                        }
                        if p.line.heading_level > 0 && theme.data.heading_color.a != 0 do color = theme.data.heading_color
                        if sub.pre && theme.data.code_color.a != 0 do color = theme.data.code_color
                        if theme.data.muted_color.a != 0 {
                            marker := p.fence_delimiter || (text == "`" && !p.line.fenced)
                            if start - p.line_start <= 3 {
                                marker = marker || (p.line.quoted && text == ">") ||
                                    (p.line.heading_level > 0 && len(text) == p.line.heading_level && text[0] == '#')
                                if !p.line.fenced && (text == "-" || text == "+" || text == "*") &&
                                    end < len(src) && (src[end] == ' ' || src[end] == '\t') {
                                    bullet := true
                                    for byte in src[p.line_start:start] {
                                        if byte != ' ' do bullet = false
                                    }
                                    marker = marker || bullet
                                }
                            }
                            if marker do color = theme.data.muted_color
                        }
                        emit(emit_data, Display_Command{
                            pos = {draw_pos.x + inset, draw_pos.y + offset_y},
                            previous = previous,
                            dash_context = {src, start + chunk_start},
                            sub = Display_Command_Text{
                                text = text[chunk_start:chunk_end],
                                font = font,
                                color = color,
                            },
                        })
                    }

                    if start + chunk_start <= sel_pos && sel_pos < start + chunk_end {
                        caret_pen := Display_Pen{draw_pos.x, previous}
                        offset := chunk_start
                        // The selection is a byte offset and may land inside a rune.
                        for offset < chunk_end {
                            ch, size := utf8.decode_rune(text[offset:chunk_end])
                            x := display_pen_step(&caret_pen, font, metrics, ch)
                            if sel_pos - start < offset + size {
                                pos := [2]f32{x + inset, draw_pos.y + row_top}
                                caret_rect = {pos.x, pos.y, INSERT_CARET_W, font_height}
                                if heading_code do caret_rect.height = prose_height
                                if normal {
                                    pos.y = draw_pos.y + offset_y
                                    has_ink: bool
                                    caret_rect, has_ink = display_block_bounds(theme, font, ch, pos, caret_pen.x - x)
                                    if has_ink {
                                        cursor_glyph_pos = pos
                                        cursor_glyph = {text[offset:offset+size], font, theme.data.bg_color}
                                        cursor_dash_context = {src, start + offset}
                                    }
                                }
                                break
                            }
                            offset += size
                        }
                    }

                    draw_pos.x = pen.x
                    previous = pen.previous
                    line_height = max(line_height, font_height)
                    chunk_start = chunk_end
                    if emit == nil && caret_rect.height > 0 do break layout
                    if chunk_start < len(text) {
                        draw_pos = {0, draw_pos.y + line_height}
                        line_height = min_line_height
                        previous = 0
                        decorated = false
                    }
                }
        }
    }

    if sel_pos == len(src) && (stop_y < 0 || draw_pos.y < stop_y) {
        eof_line := p.line
        if p.line_start == len(src) do eof_line = {fenced = p.fence_length != 0}
        if emit != nil && !decorated {
            display_emit_block_row(emit, emit_data, theme, eof_line, draw_pos.y, bounds_size.x, line_height)
        }
        inset := display_block_inset(theme, eof_line, bounds_size.x)
        caret_rect = display_blank_caret(&theme.fonts[line_variant], &theme.font_metrics[line_variant], normal,
                                         {draw_pos.x + inset, draw_pos.y}, line_height)
    }
    if caret_rect.height <= 0 do return caret_rect
    if cursor_glyph.text != "" && caret_rect.x < bounds_size.x {
        // Clip ink overhang instead of shifting the block away from its glyph.
        right := min(bounds_size.x, caret_rect.x + caret_rect.width)
        caret_rect.x = max(0, caret_rect.x)
        caret_rect.width = right - caret_rect.x
    } else {
        // At an exactly filled edge, keep the blank or thin caret visible.
        if normal do caret_rect.width = min(caret_rect.width, bounds_size.x)
        caret_rect.x = min(caret_rect.x, max(f32(0), bounds_size.x - caret_rect.width))
    }

    if emit != nil {
        floor_left := false
        if cursor_glyph.text != "" {
            raster := display_raster_font(theme, cursor_glyph.font)
            ch, _ := utf8.decode_rune(cursor_glyph.text)
            floor_left, _ = display_glyph_placement(theme, cursor_glyph.font, raster, rl.GetGlyphIndex(raster^, ch))
        }
        emit(emit_data, Display_Command{
            pos = {caret_rect.x, caret_rect.y},
            sub = Display_Command_Rect{
                w = caret_rect.width,
                h = caret_rect.height,
                color = theme.data.accent_color if theme.data.accent_color.a != 0 else theme.data.fg_color,
                floor_left = floor_left,
            },
        })
        // Paint the block after the page text, then invert just the selected rune.
        if cursor_glyph.text != "" {
            emit(emit_data, Display_Command{pos = cursor_glyph_pos, dash_context = cursor_dash_context, sub = cursor_glyph})
        }
    }

    return caret_rect
}

Display_Viewport :: struct {
    theme: ^Theme,
    origin: [2]f32,
    top, bottom: f32,
}

display_command_draw :: proc(data: rawptr, cmd: Display_Command) {
    viewport := cast(^Display_Viewport)data
    pos := cmd.pos + viewport.origin
    if pos.y >= viewport.bottom do return

    switch sub in cmd.sub {
        case Display_Command_Text:
            // Include a row of slack for font ascenders/descenders and padding.
            if pos.y + 2 * f32(sub.font.baseSize) <= viewport.top do return
            display_draw_text(viewport.theme, sub.font, sub.text, cmd.pos, sub.color, cmd.previous, viewport.origin, cmd.dash_context)

        case Display_Command_Rect:
            if pos.y + sub.h <= viewport.top do return
            rl.DrawRectangleRec(display_snap_rect(viewport.theme, {pos.x, pos.y, sub.w, sub.h}, sub.floor_left), sub.color)
    }
}
