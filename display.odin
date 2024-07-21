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

@(private="file")
wrapped_lines_and_loc :: proc(using ed: ^Editor, theme: ^Theme, wrap_w: f32) -> ([dynamic]string, Editor_Loc) {
    font := theme.fonts[.BODY]
    font_size := f32(font.baseSize)

    orig_loc := byte_index_to_editor_loc(state.selection[0], sb.buf[:])
    orig_lines := strings.split_lines(string(sb.buf[:]), context.temp_allocator)

    loc := orig_loc
    lines := make([dynamic]string, 0, len(orig_lines), context.temp_allocator)

    line_builder := strings.builder_make(context.temp_allocator)

    // discarded_chars is for if you toss away any characters in between the line break position
    // and the 'loc' (assuming the loc is after the 
    append_broken_line :: proc(
        lines: ^[dynamic]string, 
        loc: ^Editor_Loc, 
        broken_line: string, 
        break_pos: int, 
        discarded_chars: int
    ) {
        prev_line_count := len(lines^)

        append(lines, strings.clone(broken_line, context.temp_allocator))

        if loc.row > prev_line_count {
            // In adding this line, we've pushed down the cursor
            loc.row += 1
        } else if loc.row == prev_line_count {
            // If column is before where we broke, then leave it alone, but if it's after
            // then subtract the length of the line we just pushed and push the row down by
            // one.
            //
            // TODO(Apaar): Is this off by one?
            if loc.col >= break_pos {
                loc.row += 1
                loc.col -= break_pos + discarded_chars
            }
        }
    }

    for orig_line, orig_line_idx in orig_lines {
        if len(orig_line) == 0 {
            // Special case, empty line, just shift
            append(&lines, "")
            continue
        }

        s := orig_line

        // Append tokens to the line builder until it doesn't fit wrap_w
        for len(s) > 0 {
            prev_s := s
            prev_len := len(line_builder.buf)

            token := space_tokenizer_next_token(&s)
            token_str := ""

            switch v in token {
                case Space_Tokenizer_Token_Word: token_str = string(v)
                case Space_Tokenizer_Token_Spaces: token_str = string(v)
                case: break
            }

            strings.write_string(&line_builder, token_str)

            line_size := rl.MeasureTextEx(
                font, 
                to_cstring(&line_builder),
                fontSize=font_size, 
                spacing=0,
            )

            if line_size.x < wrap_w {
                continue
            }

            // This is the first token and its already longer than the max wrap width.
            // Break it at the character level.
            if prev_len == 0 {
                // FIXME(Apaar): What happens if a single character is larger than the max line w?

                strings.builder_reset(&line_builder)

                // Push bytes back until we reach a breaking point
                for ch, idx in token_str {
                    strings.write_rune(&line_builder, ch)

                    line_size := rl.MeasureTextEx(
                        font,
                        to_cstring(&line_builder),
                        fontSize=font_size,
                        spacing=0,
                    )

                    if line_size.x < wrap_w {
                        continue
                    }

                    strings.pop_rune(&line_builder)

                    append_broken_line(
                        &lines,
                        &loc,
                        string(line_builder.buf[:]),
                        break_pos=len(line_builder.buf),
                        discarded_chars=0,
                    )

                    strings.builder_reset(&line_builder)
                    s = prev_s[idx:]
                    break
                }

                continue
            }

            // TODO(Apaar): If orig_line_idx == orig_loc.row then
            // when we do this break, we need to check if we're before or
            // after the loc.col (not orig_loc). If we're before, we need to......

            // Reset the line builder and tokenized string to before the token was added
            resize(&line_builder.buf, prev_len)

            discarded_spaces := 0

            if _, is_space := token.(Space_Tokenizer_Token_Spaces); is_space {
                // Discard the space token if it is the cause of a line break.
                discarded_spaces = len(token_str)
            } else {
                s = prev_s
            }

            append_broken_line(
                &lines, 
                &loc,
                string(line_builder.buf[:]),
                break_pos=len(line_builder.buf),
                discarded_chars=discarded_spaces,
            )

            strings.builder_reset(&line_builder)
        }

        if len(line_builder.buf) == 0 {
            continue
        }

        // Push whatevers remaining in the buffer into the lines. The wrapping has already
        // been accounted for in the loc changes above.
        append(&lines, strings.clone(string(line_builder.buf[:]), context.temp_allocator))
        strings.builder_reset(&line_builder)
    }

    // Just append a space char to get the user started in terms
    // of showing a caret
    append(&lines, strings.clone(" ", context.temp_allocator))

    return lines, loc
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

    /*
    {
        // Draw text lines

        text := strings.to_string(sb)

        y_off := f32(0)

        for line, line_idx in display.wrapped_lines {
            // Skip the scrolled lines
            if line_idx < display.scroll_row {
                continue
            }

            y_pos := display.bounds.y + y_off

            if y_pos < display.bounds.y {
                continue
            }

            if y_pos >= display.bounds.y + display.bounds.height {
                break
            }

            // No caret by default
            caret_pos := -1

            if mode != .COMMAND && blink && line_idx == display.wrapped_loc.row {
                caret_pos = display.wrapped_loc.col
            }

            draw_line(
                ed, 
                theme, 
                line, 
                {display.bounds.x, y_pos}, 
                caret_pos, 
                fixed_caret_w=mode == .INSERT ? INSERT_CARET_W : 0, 
                chop_caret=pending_action != .NONE,
            )

            y_off += font_size
        }
    }
    */

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
