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

@(private="file")
wrapped_lines_and_loc :: proc(using ed: ^Editor, theme: ^Theme, wrap_w: f32) -> ([dynamic]string, Editor_Loc) {
    font := theme.fonts[.BODY]
    font_size := f32(font.baseSize)

    orig_loc := byte_index_to_editor_loc(state.selection[0], sb.buf[:])
    orig_lines := strings.split_lines(string(sb.buf[:]), context.temp_allocator)
    
    loc := orig_loc
    lines := make([dynamic]string, 0, len(orig_lines), context.temp_allocator)

    line_builder := strings.builder_make(context.temp_allocator)

    for orig_line, orig_line_idx in orig_lines {
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
                // TODO(Apaar): Do not allocate here, re-use a buffer
                strings.clone_to_cstring(string(line_builder.buf[:]), context.temp_allocator),
                fontSize=font_size, 
                spacing=0
            )

            if line_size.x < wrap_w {
                continue
            }

            // This is the first token. It's already longer than the wrap_w, so don't bother breaking it.
            //
            // TODO(Apaar): Break the token in half or something and repeat
            if prev_len == 0 {
                continue
            }

            // TODO(Apaar): If orig_line_idx == orig_loc.row then
            // when we do this break, we need to check if we're before or
            // after the loc.col (not orig_loc). If we're before, we need to......

            prev_line_count := len(lines)

            // Reset the line builder and tokenized string to before the token was added
            resize(&line_builder.buf, prev_len)

            discarded_spaces := 0

            if _, is_space := token.(Space_Tokenizer_Token_Spaces); is_space {
                // Discard the space token if it is the cause of a line break.
                discarded_spaces = len(token_str)
            } else {
                s = prev_s
            }

            // Push this line back
            append(&lines, strings.clone(string(line_builder.buf[:]), context.temp_allocator))

            if loc.row > prev_line_count {
                // In adding this line, we've pushed down the cursor
                loc.row += 1
            } else if loc.row == prev_line_count {
                // If column is before where we broke, then leave it alone, but if it's after
                // then subtract the length of the line we just pushed and push the row down by
                // one.
                //
                // TODO(Apaar): Is this off by one?
                if loc.col >= len(line_builder.buf) {
                    loc.row += 1
                    loc.col -= len(line_builder.buf) + discarded_spaces
                }
            }

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
editor_display_begin :: proc(using ed: ^Editor, theme: ^Theme, wrap_w: f32) {
    wrapped_lines, wrapped_loc = wrapped_lines_and_loc(ed, theme, wrap_w)
}

// Cleans up display state
editor_display_end :: proc(using ed: ^Editor) {
    // TODO(Apaar): Maybe clean up wrapped_lines?
}

editor_display_scroll_cursor_into_view :: proc(using ed: ^Editor, theme: ^Theme) {
    font := theme.fonts[.BODY]
    font_size := f32(font.baseSize)

    if wrapped_loc.row < scroll_row {
        scroll_row = wrapped_loc.row
        return
    }

    lpp := lines_per_page(font_size)

    if wrapped_loc.row >= scroll_row + lpp - 1 {
        scroll_row = wrapped_loc.row - lpp + 1
    }
}

editor_display_draw :: proc(using ed: ^Editor, theme: ^Theme) {
    font := theme.fonts[.BODY]
    font_size := f32(font.baseSize)

    lpp := lines_per_page(font_size)

    blink := (cast (int) (rl.GetTime() * 1000 / 300)) % 2 == 0

    {
        // Draw text lines

        y_pos: f32 = 0

        text := strings.to_string(sb)

        for line, line_idx in wrapped_lines {
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

            if mode != .COMMAND && blink && line_idx == wrapped_loc.row {
                caret_pos = wrapped_loc.col
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
