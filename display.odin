package main

import "core:strings"
import rl "vendor:raylib"

INSERT_CARET_W :: 2

@(private="file")
draw_line :: proc(
    using ed: ^Editor, 
    theme: ^Theme, 
    line: string, 
    pos: [2]f32, 
    caret_pos: int, 
    fixed_caret_w: f32, 
    chop_caret: bool
) {
    font := theme.fonts[.BODY]
    font_size := f32(font.baseSize)

    text := strings.clone_to_cstring(line, context.temp_allocator)
 
    rl.DrawTextEx(
        font=font,
        text=text,
        position=pos,
        fontSize=font_size,
        spacing=0,
        tint=theme.data.fg_color,
    )

    if caret_pos < 0 {
        return
    }

    // Draw caret
    sub_len := caret_pos

    sub_text := strings.clone_to_cstring(line[:sub_len], context.temp_allocator)

    // HACK(Apaar): We subtract the size of e.g. "abc" from "ab" to get the caret size over "c"
    sub_text_plus_current := sub_len < len(line) ? strings.clone_to_cstring(line[:sub_len+1], context.temp_allocator) : sub_text

    // Place the caret right after this
    sub_text_size := rl.MeasureTextEx(font, sub_text, fontSize=font_size, spacing=0)
    sub_text_plus_current_size := rl.MeasureTextEx(font, sub_text_plus_current, fontSize=font_size, spacing=0)

    calc_caret_w := sub_text_plus_current_size.x - sub_text_size.x

    if calc_caret_w == 0 {
        calc_caret_w = 5
    }

    rl.DrawRectangleRec(
        rl.Rectangle{
            x = pos.x + sub_text_size.x,
            y = pos.y + (chop_caret ? sub_text_size.y / 2 : 0),
            width = fixed_caret_w > 0 ? fixed_caret_w : calc_caret_w,
            height = chop_caret ? sub_text_size.y / 2 : sub_text_size.y,
        },
        theme.data.fg_color,
    )
}

@(private="file")
lines_per_page :: proc(font_size: f32) -> int {
    // Subtract font_size for the status bar
    rh := f32(rl.GetRenderHeight()) - font_size

    return int(rh / font_size)
}

editor_scroll_cursor_into_view :: proc(using ed: ^Editor, theme: ^Theme) {
    font := theme.fonts[.BODY]
    font_size := f32(font.baseSize)

    loc := byte_index_to_editor_loc(state.selection[0], sb.buf[:])

    if loc.row < scroll_row {
        scroll_row = loc.row
        return
    }

    lpp := lines_per_page(font_size)

    if loc.row >= scroll_row + lpp {
        scroll_row = loc.row - lpp + 1
    }
}

editor_draw :: proc(using ed: ^Editor, theme: ^Theme) {
    font := theme.fonts[.BODY]
    font_size := f32(font.baseSize)

    lpp := lines_per_page(font_size)

    blink := (cast (int) (rl.GetTime() * 1000 / 300)) % 2 == 0

    {
        // Draw text lines

        y_pos: f32 = 0

        text := strings.to_string(sb)
        lines := strings.split_lines(text, context.temp_allocator)

        line_start_byte_index := 0

        for line, line_idx in lines {
            // + 1 for newline char
            next_line_start_byte_index := line_start_byte_index + len(line) + 1
            defer line_start_byte_index = next_line_start_byte_index

            // TODO(Apaar): Compute lines per page and don't render anything below.
            if line_idx < scroll_row {
                continue
            }

            if line_idx >= scroll_row + lpp {
                break
            }

            defer y_pos += font_size

            // No caret by default
            caret_pos := -1

            if mode != .COMMAND && blink && state.selection[0] >= line_start_byte_index && state.selection[0] < next_line_start_byte_index {
                caret_pos = state.selection[0] - line_start_byte_index
            }

            draw_line(
                ed, 
                theme, 
                line, 
                {20.0, 20.0 + y_pos}, 
                caret_pos, 
                fixed_caret_w=mode == .INSERT ? INSERT_CARET_W : 0, 
                chop_caret=pending_action != .NONE,
            )
        }
    }

    {
        // Draw status bar

        ren_size := [?]f32{
            f32(rl.GetRenderWidth()), 
            f32(rl.GetRenderHeight()),
        }

        rl.DrawRectangleRec(
            {
                x = 0,
                y = ren_size.y - font_size,
                width = ren_size.x,
                height = font_size
            }, 
            theme.data.bg_color
        )

        // Only draw caret if in command mode
        caret_pos := mode == .COMMAND ? len(status.buf) : -1

        draw_line(
            ed, 
            theme, 
            strings.to_string(status), 
            {0, ren_size.y - font_size}, 
            caret_pos, 
            fixed_caret_w=INSERT_CARET_W, 
            chop_caret=false
        )
    }
}
