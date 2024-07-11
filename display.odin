package main

import "core:strings"
import rl "vendor:raylib"

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

editor_draw :: proc (using ed: ^Editor, theme: ^Theme) {
    font := theme.fonts[.BODY]
    font_size := f32(font.baseSize)

    blink := (cast (int) (rl.GetTime() * 1000 / 300)) % 2 == 0

    y_pos: f32 = 0

    text := strings.to_string(sb)
    lines := strings.split_lines(text, context.temp_allocator)

    line_start_byte_index := 0

    for line in lines {
        // + 1 for newline char
        next_line_start_byte_index := line_start_byte_index + len(line) + 1

        defer {
            y_pos += font_size
            line_start_byte_index = next_line_start_byte_index
        }

        // No caret by default
        caret_pos := -1
        
        if mode != .COMMAND && blink && sel[0] >= line_start_byte_index && sel[0] < next_line_start_byte_index {
            caret_pos = sel[0] - line_start_byte_index
        }

        draw_line(ed, theme, line, {20.0, 20.0 + y_pos}, caret_pos, fixed_caret_w=mode == .INSERT ? 2 : 0, chop_caret=pending_action != .NONE)
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

        draw_line(ed, theme, strings.to_string(status), {0, ren_size.y - font_size}, caret_pos, fixed_caret_w=2, chop_caret=false)
    }
}
