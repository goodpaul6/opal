package main

import "core:strings"
import nvg "vendor:nanovg"
import sdl "vendor:sdl2"

INSERT_CARET_W :: 2

Editor_Display_State :: struct {
    bounds: Rect,
    scroll_pos: [2]f32,
    prev_caret_rect: Rect,
}

// Assumes fill and stroke color is set up correctly
@(private="file")
draw_line :: proc(
    using ed: ^Editor, 
    nvc: ^nvg.Context,
    line: string, 
    pos: [2]f32, 
    caret_pos: int, 
    fixed_caret_w: f32, 
    chop_caret: bool,
) {
    nvg.Text(nvc, pos.x, pos.y, line)

    if caret_pos < 0 {
        return
    }

    // Draw caret
    sub_len := caret_pos
    sub_text := line[:sub_len]

    // HACK(Apaar): We subtract the size of e.g. "abc" from "ab" to get the caret size over "c"
    sub_text_plus_current := sub_len < len(line) ? line[:sub_len+1] : sub_text

    // Place the caret right after this
    sub_text_bounds := [4]f32{}
    sub_text_plus_current_bounds := [4]f32{}

    _ = nvg.TextBounds(nvc, pos.x, pos.y, line, &sub_text_bounds)
    _ = nvg.TextBounds(nvc, pos.x, pos.y, line, &sub_text_plus_current_bounds)

    sub_text_w := sub_text_bounds[2] - sub_text_bounds[0]
    sub_text_plus_current_w := sub_text_plus_current_bounds[2] - sub_text_plus_current_bounds[0]

    sub_text_h := sub_text_bounds[3] - sub_text_bounds[1]

    calc_caret_w := sub_text_plus_current_w - sub_text_w

    if calc_caret_w == 0 {
        calc_caret_w = 5
    }

    caret_w := fixed_caret_w > 0 ? fixed_caret_w : calc_caret_w

    nvg.BeginPath(nvc)

    nvg.Rect(nvc, pos.x + sub_text_w, pos.y, caret_w, sub_text_h)

    nvg.Fill(nvc)
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
    bounds: Rect,
) {
    display.bounds = bounds
}

// Cleans up display state
editor_display_end :: proc(using ed: ^Editor) {
    // TODO(Apaar): Maybe clean up wrapped_lines?
}

editor_status_line_height :: proc(theme: ^Theme) -> f32{
    return f32(theme_font_variant_size(theme, .BODY))
}

editor_display_draw :: proc(using ed: ^Editor, theme: ^Theme, nvc: ^nvg.Context) {
    font := theme.fonts[.BODY]
    font_size := f32(theme_font_variant_size(theme, .BODY))

    blink := int(sdl.GetTicks() / 300) % 2 == 0

    commands := make([dynamic]Display_Command, context.temp_allocator)

    _, caret_rect := display_command_gen(
        ed, 
        theme, 
        nvc,
        {display.bounds.w, display.bounds.h},  
        &commands,
    )

    if should_scroll_cursor_into_view {
        top := caret_rect.y
        bottom := caret_rect.y + caret_rect.h

        // TODO(Apaar): Handle horiz scroll
        if (top - display.scroll_pos.y) < 0 {
            display.scroll_pos.y = top
        } else if (bottom - display.scroll_pos.y) > display.bounds.h {
            display.scroll_pos.y = bottom - display.bounds.h
        } else {
            // In bounds, don't need to scroll anymore
            should_scroll_cursor_into_view = false
        }
    }

    {
        nvg.SaveScoped(nvc)
        nvg.Scissor(
            nvc, 
            display.bounds.x, 
            display.bounds.y, 
            display.bounds.w, 
            display.bounds.h,
        )

        display_command_run_all(
            commands[:], 
            theme,
            nvc,
            {display.bounds.x, display.bounds.y}, 
            display.scroll_pos,
        )
    }

    {
        // Draw status bar
        /*

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
            nvc,
            strings.to_string(status), 
            {0, ren_size.y - font_size}, 
            caret_pos, 
            fixed_caret_w=INSERT_CARET_W, 
            chop_caret=false
        )
        */
    }
}
