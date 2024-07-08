package main

import "core:strings"
import rl "vendor:raylib"

editor_draw :: proc (using ed: ^Editor, theme: ^Theme) {
    y_pos : f32 = 0.0
    blink := (cast (int) (rl.GetTime() * 1000 / 300)) % 2 == 0

    text := strings.to_string(sb)
    lines := strings.split_lines(text, context.temp_allocator)

    line_start_byte_index := 0

    for line in lines {
        text := strings.clone_to_cstring(line, context.temp_allocator)

        // + 1 for newline char
        next_line_start_byte_index := line_start_byte_index + len(line) + 1

        defer {
            y_pos += 22        
            line_start_byte_index = next_line_start_byte_index
        }

        font := theme.fonts[.BODY]
        font_size := f32(font.baseSize)
        
        rl.DrawTextEx(
            font=font,
            text=text,
            position={20.0, 20.0 + y_pos},
            fontSize=font_size,
            spacing=0,
            tint=theme.fg_color,
        )

        if !blink || sel[0] < line_start_byte_index || sel[0] >= next_line_start_byte_index {
            continue
        }

        // Draw caret
        sub_len := sel[0] - line_start_byte_index

        sub_text := strings.clone_to_cstring(line[:sub_len], context.temp_allocator)

        // HACK(Apaar): We subtract the size of e.g. "abc" from "ab" to get the caret size over "c"
        sub_text_plus_current := sub_len < len(line) ? strings.clone_to_cstring(line[:sub_len+1], context.temp_allocator) : sub_text

        // Place the caret right after this
        sub_text_size := rl.MeasureTextEx(font, sub_text, fontSize=font_size, spacing=0)
        sub_text_plus_current_size := rl.MeasureTextEx(font, sub_text_plus_current, fontSize=font_size, spacing=0)

        caret_w := sub_text_plus_current_size.x - sub_text_size.x

        if caret_w == 0 {
            caret_w = 5
        }

        rl.DrawRectangleRec(
            rl.Rectangle{
                x = 20.0 + sub_text_size.x,
                y = 20.0 + y_pos,
                width = mode == .NORMAL ? caret_w : 2,
                height = sub_text_size.y,
            },
            theme.fg_color,
        )
    }
}
