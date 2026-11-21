package main

import "core:strings"
import "core:time"
import rl "vendor:raylib"

INSERT_CARET_W :: 2

Editor_Display_State :: struct {
    bounds: rl.Rectangle,
    scroll_pos: [2]f32,
    checkpoints: [dynamic]Display_Checkpoint,
    checkpoint_width: f32,
    checkpoint_zoom: int,
}

STATUS_PAD_X :: 8
STATUS_PAD_Y :: 6

Editor_Status_Layout :: struct {
    label, command_tail: string,
    badge_width, prompt_x, command_x, caret_x: f32,
}

// Read mode and command at draw time; the visible text borrows the editor buffer.
editor_status_layout :: proc(ed: ^Editor, font: ^rl.Font, width: f32, metrics: ^Font_Metrics = nil) -> (layout: Editor_Status_Layout) {
    switch ed.mode {
        case .NORMAL: layout.label = "NORMAL"
        case .INSERT: layout.label = "INSERT"
        case .COMMAND: layout.label = "COMMAND"
        case .VISUAL: layout.label = "VISUAL LINE"
    }
    layout.badge_width = display_text_width(font, layout.label, metrics) + 2 * STATUS_PAD_X
    if ed.mode != .COMMAND do return

    colon_width := display_glyph_advance(font, ':', metrics)
    layout.prompt_x = layout.badge_width + STATUS_PAD_X
    right := width - STATUS_PAD_X
    if layout.prompt_x + colon_width + INSERT_CARET_W > right {
        // In tiny windows prefer showing the prompt and caret to the badge.
        layout.badge_width = 0
        right = width
        layout.prompt_x = clamp(width - colon_width - INSERT_CARET_W, 0, STATUS_PAD_X)
    }
    layout.command_x = layout.prompt_x + colon_width

    // Command input is ASCII. Keep the caret visible and measure only as
    // much text on either side of it as fits.
    command := strings.to_string(ed.command)
    cursor := ed.command_cursor
    start := cursor
    tail_width: f32
    available := right - layout.command_x - INSERT_CARET_W
    for start > 0 {
        ch := rune(command[start - 1])
        advance := display_glyph_advance(font, ch, metrics)
        if start < cursor do advance += font_pair_delta(metrics, ch, rune(command[start]))
        // The prompt stays visible, so it pairs with the first visible byte,
        // not with any of the hidden prefix.
        first_delta := font_pair_delta(metrics, ':', ch)
        if tail_width + advance + first_delta > available do break
        tail_width += advance
        start -= 1
    }
    // Use the same forward pen as drawing, including the prompt pair.
    pen := Display_Pen{layout.command_x, ':'}
    for ch in command[start:cursor] do display_pen_step(&pen, font, metrics, ch)
    layout.caret_x = pen.x
    end := cursor
    for end < len(command) {
        display_pen_step(&pen, font, metrics, rune(command[end]))
        if pen.x > right do break
        end += 1
    }
    layout.command_tail = command[start:end]
    return
}

@(private="file")
editor_status_draw :: proc(ed: ^Editor, theme: ^Theme, width, height: i32) {
    font := &theme.fonts[.BODY]
    bar_h := min(f32(height), editor_status_line_height(theme))
    if width <= 0 || bar_h <= 0 do return
    bar := rl.Rectangle{0, f32(height) - bar_h, f32(width), bar_h}
    text_y := bar.y + max(0, (bar_h - f32(font.baseSize)) / 2)
    fg, bg := theme.data.fg_color, theme.data.bg_color
    layout := editor_status_layout(ed, font, bar.width, &theme.font_metrics[.BODY])

    display_begin_scissor(theme, bar, height)
    defer rl.EndScissorMode()
    rl.DrawRectangleRec(display_snap_rect(theme, bar), rl.ColorLerp(bg, fg, 0.04))
    if layout.badge_width > 0 {
        mode_color := theme.data.muted_color if ed.mode == .NORMAL else theme.data.accent_color
        rl.DrawRectangleRec(display_snap_rect(theme, {0, bar.y, layout.badge_width, bar_h}), rl.ColorLerp(bg, mode_color, 0.12))
        display_draw_text(theme, font, layout.label, {STATUS_PAD_X, text_y}, mode_color)
    }
    if ed.mode == .COMMAND {
        display_draw_text(theme, font, ":", {layout.prompt_x, text_y}, fg)
        display_draw_text(theme, font, layout.command_tail, {layout.command_x, text_y}, fg, ':')
        rl.DrawRectangleRec(
            display_snap_rect(theme, {layout.caret_x, text_y, INSERT_CARET_W, f32(font.baseSize)}),
            theme.data.accent_color,
        )
    }
}

// Sets up display state that will use used throughout display calls
editor_display_begin :: proc(
    ed: ^Editor,
    theme: ^Theme, 
    bounds: rl.Rectangle,
) {
    if ed.display.bounds != bounds || ed.display.checkpoint_zoom != theme.zoom_level {
        ed.should_scroll_cursor_into_view = true
    }
    ed.display.bounds = bounds
}

// Cleans up display state
editor_display_end :: proc(ed: ^Editor) {
    // TODO(Apaar): Maybe clean up wrapped_lines?
}

editor_status_line_height :: proc(theme: ^Theme) -> f32 {
    return f32(theme.fonts[.BODY].baseSize) + 2 * STATUS_PAD_Y
}

editor_display_draw :: proc(ed: ^Editor, theme: ^Theme, width, height: i32, trace: ^Input_Frame_Trace = nil) {
    tick: time.Tick
    bounds_size := [2]f32{ed.display.bounds.width, ed.display.bounds.height}
    if bounds_size.x > 0 && bounds_size.y > 0 {
        if ed.should_scroll_cursor_into_view || ed.prev_frame_sel != ed.state.selection {
            when OPAL_TRACE_INPUT {
                if trace != nil do tick = time.tick_now()
            }
            caret := display_command_gen(ed, theme, bounds_size, viewport_top = ed.display.scroll_pos.y)
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
        display_begin_scissor(theme, ed.display.bounds, height)
        viewport := Display_Viewport{
            theme = theme,
            origin = [2]f32{ed.display.bounds.x, ed.display.bounds.y} - ed.display.scroll_pos,
            top = ed.display.bounds.y,
            bottom = ed.display.bounds.y + bounds_size.y,
        }
        display_command_gen(ed, theme, bounds_size, display_command_draw, &viewport,
                            viewport.bottom - viewport.origin.y, ed.display.scroll_pos.y)
        rl.EndScissorMode()
        when OPAL_TRACE_INPUT {
            if trace != nil do trace.page = time.tick_since(tick)
        }
    }

    when OPAL_TRACE_INPUT {
        if trace != nil do tick = time.tick_now()
    }
    editor_status_draw(ed, theme, width, height)
    when OPAL_TRACE_INPUT {
        if trace != nil do trace.status = time.tick_since(tick)
    }
}
