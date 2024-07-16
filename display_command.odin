package main

import "core:strings"
import "core:fmt"
import rl "vendor:raylib"

Display_Command_Text :: struct {
    text: string,
    font: ^rl.Font,
    color: rl.Color,
}

Display_Command_Rect :: struct {
    w, h: f32,
    color: rl.Color,
}

Display_Command :: struct {
    pos: [2]f32,
    sub: union #no_nil {
        Display_Command_Text,
        Display_Command_Rect,
    }
}

display_command_gen :: proc(
    ed: ^Editor, 
    theme: ^Theme,
    bounds: rl.Rectangle,
    commands: ^[dynamic]Display_Command,
) -> bool {
    start_cmd_count := len(commands^)

    src := string(ed.sb.buf[:])
    src_pos := 0

    // TODO(Apaar): Handle selection
    sel_pos := ed.state.selection[0]
    sel_loc := byte_index_to_editor_loc(sel_pos, ed.sb.buf[:])

    draw_pos := [2]f32{bounds.x, bounds.y}

    cur_line_text_w: f32
    cur_line_max_text_h: f32

    prev_src: string
    prev_src_pos: int

    caret_rect: rl.Rectangle

    for token in parser_next_token(&src, &src_pos) {
        contains_caret := token.extents[0] <= sel_pos && sel_pos < token.extents[1]
        
        caret_idx := contains_caret ? sel_pos - token.extents[0] : -1

        font: ^rl.Font

        is_newline := false
        is_spaces := false

        switch sub in token.sub {
            case Parser_Token_Newline: {
                font = &theme.fonts[.BODY]
                is_newline = true
            }

            case Parser_Token_Spaces: {
                font = &theme.fonts[.BODY]
                is_spaces = true
            }

            case Parser_Token_Word: font = &theme.fonts[.BODY]
            case Parser_Token_Pre: font = &theme.fonts[.PRE]
        }

        font_size := f32(font.baseSize)

        if is_newline {
            if contains_caret {
                caret_rect = {draw_pos.x, draw_pos.y, 2, font_size}
            }

            // Nothing else to draw, just reset
            draw_pos.x = bounds.x
            draw_pos.y += max(cur_line_max_text_h, font_size)

            cur_line_text_w = 0
            cur_line_max_text_h = 0

            continue
        }

        token_str := parser_token_string(token)

        token_size := rl.MeasureTextEx(
            font^,
            strings.clone_to_cstring(token_str, context.temp_allocator),
            font_size,
            spacing=0,
        )

        if cur_line_text_w + token_size.x > bounds.width {
            // TODO(Apaar): Split individual tokens longer than wrap_w. Right now we just draw.
            if cur_line_text_w == 0 {
                append(commands, Display_Command{
                    pos = draw_pos,
                    sub = Display_Command_Text{
                        text = token_str,
                        font = font,
                        color = theme.data.fg_color,
                    },
                })

                draw_pos.x = bounds.x
                draw_pos.y += max(cur_line_max_text_h, font_size)

                cur_line_text_w = 0
                cur_line_max_text_h = 0

                continue
            }

            // Reset back to the left
            draw_pos.x = bounds.x

            // In case this is the first token, it will hit the font_size case
            draw_pos.y += max(cur_line_max_text_h, font_size)

            cur_line_text_w = 0
            cur_line_max_text_h = 0

            if is_spaces {
                // If the spaces cause a line break, just skip em
                continue
            }

            // Move back to before this token, go down a line, and continue
            src = prev_src
            src_pos = prev_src_pos

            continue
        }

        cur_line_text_w += token_size.x

        if token_size.y > cur_line_max_text_h {
            cur_line_max_text_h = token_size.y
        }

        append(commands, Display_Command{
            pos = draw_pos,
            sub = Display_Command_Text{
                text = token_str,
                font = font,
                color = theme.data.fg_color,
            }
        })

        if caret_idx >= 0 {
            sub_text := token_str[:caret_idx]
            sub_text_size := rl.MeasureTextEx(
                font^,
                strings.clone_to_cstring(sub_text, context.temp_allocator),
                font_size,
                spacing=0,
            )

            caret_rect = {draw_pos.x + sub_text_size.x, draw_pos.y, 2, sub_text_size.y}
        }

        draw_pos.x += token_size.x

        prev_src = src
        prev_src_pos = src_pos
    }

    append(commands, Display_Command{
        pos = {caret_rect.x, caret_rect.y},
        sub = Display_Command_Rect{
            w = caret_rect.width,
            h = caret_rect.height,
            color = theme.data.fg_color,
        },
    })

    return true
}

display_command_run_all :: proc(commands: []Display_Command) {
    for &cmd in commands {
        switch sub in cmd.sub {
            case Display_Command_Text: {
                rl.DrawTextEx(
                    sub.font^,
                    strings.clone_to_cstring(sub.text, context.temp_allocator),
                    cmd.pos,
                    fontSize=f32(sub.font.baseSize),
                    spacing=0,
                    tint=sub.color,
                )
            }

            case Display_Command_Rect: {
                rl.DrawRectangleRec(
                    rl.Rectangle{
                        cmd.pos.x,
                        cmd.pos.y,
                        sub.w,
                        sub.h,
                    },
                    sub.color,
                )
            }
        }
    }
}
