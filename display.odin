package main

import "core:strings"
import "core:time"
import "core:unicode/utf8"
import rl "vendor:raylib"

INSERT_CARET_W :: 2

Editor_Display_State :: struct {
    bounds: rl.Rectangle, // Window coordinates for hit testing and clipping.
    layout_size: [2]f32,
    zoom: f32,
    scroll_pos: [2]f32,
    checkpoints: [dynamic]Display_Checkpoint,
    checkpoint_width: f32,
    checkpoint_zoom: int,
}

STATUS_PAD_X :: 8
STATUS_PAD_Y :: 6

Editor_Status_Layout :: struct {
    label, command_tail: string,
    badge_width, prompt_x, command_x, caret_x, end_x, message_x: f32,
}

Status_Line :: struct {
    label, command, message: string,
    cursor: int,
    input, colon, selected, muted: bool,
}

editor_status_line :: proc(ed: ^Editor) -> (line: Status_Line) {
    switch ed.mode {
        case .NORMAL: line.label, line.muted = "NORMAL", true
        case .INSERT: line.label = "INSERT"
        case .COMMAND:
            line.label = "COMMAND"
            line.input, line.colon = true, true
            line.command, line.cursor = strings.to_string(ed.command), ed.command_cursor
        case .VISUAL: line.label = "VISUAL" if ed.visual_characterwise else "VISUAL LINE"
    }
    return
}

editor_status_layout :: proc(ed: ^Editor, font: ^rl.Font, width: f32, metrics: ^Font_Metrics = nil) -> Editor_Status_Layout {
    return status_line_layout(editor_status_line(ed), font, width, metrics)
}

status_line_layout :: proc(line: Status_Line, font: ^rl.Font, width: f32, metrics: ^Font_Metrics) -> (layout: Editor_Status_Layout) {
    layout.label = line.label
    layout.badge_width = display_text_width(font, layout.label, metrics) + 2 * STATUS_PAD_X
    layout.message_x = layout.badge_width + STATUS_PAD_X
    if !line.input do return

    prefix: rune = ':' if line.colon else 0
    colon_width := display_glyph_advance(font, prefix, metrics) if line.colon else 0
    layout.prompt_x = layout.badge_width + STATUS_PAD_X
    right := width - STATUS_PAD_X
    if line.message != "" && width >= 240 {
        right -= min(width * 0.45, display_text_width(font, line.message, metrics) + STATUS_PAD_X)
    }
    if layout.prompt_x + colon_width + INSERT_CARET_W > right {
        // In tiny windows prefer showing the prompt and caret to the badge.
        layout.badge_width = 0
        right = width
        layout.prompt_x = clamp(width - colon_width - INSERT_CARET_W, 0, STATUS_PAD_X)
    }
    layout.command_x = layout.prompt_x + colon_width

    // Keep the caret visible and measure only as much text as fits.
    command := line.command
    cursor := line.cursor
    start := cursor
    next: rune
    tail_width: f32
    available := right - layout.command_x - INSERT_CARET_W
    for start > 0 {
        ch, size := utf8.decode_last_rune(command[:start])
        advance := display_glyph_advance(font, ch, metrics)
        if start < cursor do advance += font_pair_delta(metrics, ch, next)
        // The prompt stays visible, so it pairs with the first visible byte,
        // not with any of the hidden prefix.
        first_delta := font_pair_delta(metrics, prefix, ch)
        if tail_width + advance + first_delta > available do break
        tail_width += advance
        start -= size
        next = ch
    }
    // Use the same forward pen as drawing, including the prompt pair.
    pen := Display_Pen{layout.command_x, prefix}
    for ch in command[start:cursor] do display_pen_step(&pen, font, metrics, ch)
    layout.caret_x = pen.x
    layout.end_x = pen.x
    end := cursor
    for end < len(command) {
        ch, size := utf8.decode_rune(command[end:])
        display_pen_step(&pen, font, metrics, ch)
        if pen.x > right do break
        end += size
        layout.end_x = pen.x
    }
    layout.command_tail = command[start:end]
    layout.message_x = max(layout.end_x, layout.caret_x + INSERT_CARET_W) + STATUS_PAD_X
    return
}

editor_status_draw :: proc(ed: ^Editor, theme: ^Theme, width, height: i32) {
    status_line_draw(editor_status_line(ed), theme, width, height)
}

status_line_draw :: proc(line: Status_Line, theme: ^Theme, width, height: i32) {
    font := &theme.fonts[.BODY]
    bar_h := min(f32(height), editor_status_line_height(theme))
    if width <= 0 || bar_h <= 0 do return
    bar := rl.Rectangle{0, f32(height) - bar_h, f32(width), bar_h}
    text_y := bar.y + max(0, (bar_h - f32(font.baseSize)) / 2)
    fg, bg := theme.data.fg_color, theme.data.bg_color
    layout := status_line_layout(line, font, bar.width, &theme.font_metrics[.BODY])

    display_begin_scissor(theme, bar, height)
    defer rl.EndScissorMode()
    rl.DrawRectangleRec(display_snap_rect(theme, bar), rl.ColorLerp(bg, fg, 0.04))
    if layout.badge_width > 0 {
        mode_color := theme.data.muted_color if line.muted else theme.data.accent_color
        rl.DrawRectangleRec(display_snap_rect(theme, {0, bar.y, layout.badge_width, bar_h}), rl.ColorLerp(bg, mode_color, 0.12))
        display_draw_text(theme, font, layout.label, {STATUS_PAD_X, text_y}, mode_color)
    }
    if line.input {
        if line.colon do display_draw_text(theme, font, ":", {layout.prompt_x, text_y}, fg)
        if line.selected {
            rl.DrawRectangleRec(display_snap_rect(theme, {layout.command_x, text_y, layout.end_x - layout.command_x, f32(font.baseSize)}),
                                display_selection_color(theme))
        }
        display_draw_text(theme, font, layout.command_tail, {layout.command_x, text_y}, fg, ':' if line.colon else 0)
        if !line.selected do rl.DrawRectangleRec(
            display_snap_rect(theme, {layout.caret_x, text_y, INSERT_CARET_W, f32(font.baseSize)}),
            theme.data.accent_color,
        )
    }
    if line.message != "" do display_draw_text(theme, font, line.message, {layout.message_x, text_y}, fg)
}

// Sets up display state that will use used throughout display calls
display_view_rect :: proc(rect: rl.Rectangle, origin: [2]f32, zoom: f32) -> rl.Rectangle {
    return {origin.x + rect.x * zoom, origin.y + rect.y * zoom, rect.width * zoom, rect.height * zoom}
}

editor_display_begin :: proc(
    ed: ^Editor,
    theme: ^Theme, 
    bounds: rl.Rectangle,
    zoom: f32 = 1,
    origin: [2]f32 = {},
) {
    layout_size := [2]f32{bounds.width, bounds.height}
    if ed.display.layout_size != layout_size || ed.display.checkpoint_zoom != theme.zoom_level {
        ed.should_scroll_cursor_into_view = true
    }
    ed.display.layout_size = layout_size
    ed.display.zoom = zoom
    ed.display.bounds = display_view_rect(bounds, origin, zoom)
}

// Cleans up display state
editor_display_end :: proc(ed: ^Editor) {
    // TODO(Apaar): Maybe clean up wrapped_lines?
}

editor_mouse_select :: proc(ed: ^Editor, theme: ^Theme, point: [2]f32, pressed, down, released: bool) -> bool {
    if ed.mode == .COMMAND {
        ed.mouse_selecting = false
        return false
    }
    bounds := ed.display.bounds
    if bounds.width <= 0 || bounds.height <= 0 do return false
    if pressed {
        ed.mouse_selecting = rl.CheckCollisionPointRec(point, bounds)
        if !ed.mouse_selecting do return false
    } else {
        if !ed.mouse_selecting do return false
        if !down do ed.mouse_selecting = false
        if (!down && !released) || point == ed.mouse_selection_pos do return false
    }
    ed.mouse_selection_pos = point

    local := (point - [2]f32{bounds.x, bounds.y}) / ed.display.zoom
    layout_size := ed.display.layout_size
    hit := Display_Hit_Test{
        point = {
            local.x + ed.display.scroll_pos.x,
            max(0, ed.display.scroll_pos.y + clamp(local.y, 0, max(0, layout_size.y - 1))),
        },
        offset = len(ed.sb.buf),
    }
    display_command_gen(ed, theme, layout_size, viewport_top = ed.display.scroll_pos.y, hit = &hit)
    pos := word_caret_start(ed.sb.buf[:], hit.offset)
    if pressed {
        if ed.mode == .VISUAL do ed.mode = .NORMAL
        ed.visual_anchor = pos
        ed.pending_action = .NONE
    } else {
        if ed.state.selection[0] == pos do return false
        if ed.mode == .INSERT do editor_undo_commit(ed)
        ed.mode = .VISUAL if pos != ed.visual_anchor else .NORMAL
        ed.visual_characterwise = true
        ed.visual_inclusive = false
    }
    ed.state.selection = {pos, pos}
    return true
}

editor_status_line_height :: proc(theme: ^Theme) -> f32 {
    return f32(theme.fonts[.BODY].baseSize) + 2 * STATUS_PAD_Y
}

editor_display_draw :: proc(
    ed: ^Editor, theme: ^Theme, width, height: i32, trace: ^Input_Frame_Trace = nil, show_status := true,
    rasters: ^Canvas_Font_Rasters = nil,
) {
    tick: time.Tick
    bounds_size := ed.display.layout_size
    if bounds_size.x > 0 && bounds_size.y > 0 {
        if ed.should_scroll_cursor_into_view || ed.prev_frame_sel != ed.state.selection {
            when OPAL_TRACE_INPUT {
                if trace != nil do tick = time.tick_now()
            }
            caret := display_command_gen(ed, theme, bounds_size, viewport_top = ed.display.scroll_pos.y, rasters = rasters)
            top, bottom := caret.y, caret.y + caret.height
            if top < ed.display.scroll_pos.y {
                ed.display.scroll_pos.y = top
            } else if bottom > ed.display.scroll_pos.y + bounds_size.y {
                // A tiny window can't show the full caret; keep its top visible.
                ed.display.scroll_pos.y = min(top, bottom - bounds_size.y)
            }
            ed.should_scroll_cursor_into_view = false
            when OPAL_TRACE_INPUT {
                if trace != nil do trace.caret = time.tick_since(tick)
            }
        }

        when OPAL_TRACE_INPUT {
            if trace != nil do tick = time.tick_now()
        }
        bounds := ed.display.bounds
        zoom := ed.display.zoom
        display_begin_scissor(theme, bounds, height)
        viewport := Display_Viewport{
            theme = theme,
            origin = [2]f32{bounds.x, bounds.y} - ed.display.scroll_pos * zoom,
            top = bounds.y,
            bottom = bounds.y + bounds.height,
            zoom = zoom,
            rasters = rasters,
        }
        display_command_gen(ed, theme, bounds_size, display_command_draw, &viewport,
                            ed.display.scroll_pos.y + bounds_size.y, ed.display.scroll_pos.y, rasters = rasters)
        rl.EndScissorMode()
        when OPAL_TRACE_INPUT {
            if trace != nil do trace.page = time.tick_since(tick)
        }
    }

    when OPAL_TRACE_INPUT {
        if trace != nil do tick = time.tick_now()
    }
    if show_status do editor_status_draw(ed, theme, width, height)
    when OPAL_TRACE_INPUT {
        if trace != nil do trace.status = time.tick_since(tick)
    }
}
