package main

import "core:strings"
import rl "vendor:raylib"

INSERT_CARET_W :: 2

Editor_Display_State :: struct {
    bounds: rl.Rectangle,
    scroll_pos: [2]f32,
    prev_caret_rect: rl.Rectangle,
}

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

to_cstring :: proc(builder: ^strings.Builder) -> cstring {
    strings.write_byte(builder, 0)
    strings.pop_byte(builder)
    return cstring(raw_data(builder.buf))
}

// Sets up display state that will use used throughout display calls
editor_display_begin :: proc(
    using ed: ^Editor, 
    theme: ^Theme, 
    bounds: rl.Rectangle,
) {
    display.bounds = bounds
}

// Cleans up display state
editor_display_end :: proc(using ed: ^Editor) {
    // TODO(Apaar): Maybe clean up wrapped_lines?
}

editor_status_line_height :: proc(theme: ^Theme) -> f32{
    return f32(theme.fonts[.BODY].baseSize)
}

editor_display_draw :: proc(using ed: ^Editor, theme: ^Theme) {
    font := theme.fonts[.BODY]
    font_size := f32(font.baseSize)

    blink := int(rl.GetTime() * 1000 / 300) % 2 == 0

    commands := make([dynamic]Display_Command, context.temp_allocator)

    _, caret_rect := display_command_gen(
        ed, 
        theme, 
        {display.bounds.width, display.bounds.height}, 
        &commands,
    )

    if should_scroll_cursor_into_view {
        top := caret_rect.y
        bottom := caret_rect.y + caret_rect.height

        // TODO(Apaar): Handle horiz scroll
        if (top - display.scroll_pos.y) < 0 {
            display.scroll_pos.y = top
        } else if (bottom - display.scroll_pos.y) > display.bounds.height {
            display.scroll_pos.y = bottom - display.bounds.height
        } else {
            // In bounds, don't need to scroll anymore
            should_scroll_cursor_into_view = false
        }
    }

    {
        rl.BeginScissorMode(
            i32(display.bounds.x), 
            i32(display.bounds.y),
            i32(display.bounds.width),
            i32(display.bounds.height),
        )
        defer rl.EndScissorMode()

        display_command_run_all(
            commands[:], 
            {display.bounds.x, display.bounds.y}, 
            display.scroll_pos,
        )
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
