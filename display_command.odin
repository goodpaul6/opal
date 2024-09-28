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

// HACK(Apaar): I return the caret rectangle from this for smoothly scrolling
// the cursor into the bounds
display_command_gen :: proc(
    ed: ^Editor, 
    theme: ^Theme,
    bounds_size: [2]f32,
    commands: ^[dynamic]Display_Command,
) -> (ok: bool, caret_rect: rl.Rectangle) {
    // TODO(Apaar): Handle selection
    sel_pos := ed.state.selection[0]
    sel_loc := byte_index_to_editor_loc(sel_pos, ed.sb.buf[:])

    // TODO(Apaar): Handle horizontal scroll
    draw_pos := [?]f32{0, 0}

    cur_line_text_w: f32
    cur_line_max_text_h: f32

    src := string(ed.sb.buf[:])

    // Used to restore state when doing wrapping

    nodes := parser_parse_string(string(ed.sb.buf[:]))
    nodes_iter := list_iterator_make(nodes)

    min_line_height := f32(theme.fonts[.BODY].baseSize)

    loop: for node in list_iterator_iterate(&nodes_iter) {
        contains_caret := node.extents[0] <= sel_pos && sel_pos <= node.extents[1]
        
        caret_idx := contains_caret ? sel_pos - node.extents[0] : -1

        font: ^rl.Font
        all_spaces := false

        #partial switch sub in node.sub {
            case Node_Newline:
                line_height := max(cur_line_max_text_h, min_line_height)

                // Nothing else to draw, just reset
                draw_pos.x = 0
                draw_pos.y += line_height

                cur_line_text_w = 0
                cur_line_max_text_h = 0

                if contains_caret {
                    caret_rect = {draw_pos.x, draw_pos.y, 2, line_height}
                }

                continue loop
            
            case Node_Text:
                if sub.pre do font = &theme.fonts[.PRE]
                else do font = &theme.fonts[.BODY]

                all_spaces = sub.all_spaces
        }

        font_size := f32(font.baseSize)

        token_str := node_edit_string(node^)

        token_size := rl.MeasureTextEx(
            font^,
            strings.clone_to_cstring(token_str, context.temp_allocator),
            font_size,
            spacing=0,
        )

        if cur_line_text_w + token_size.x > bounds_size.x {
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

                draw_pos.x = 0
                draw_pos.y += max(cur_line_max_text_h, font_size)

                cur_line_text_w = 0
                cur_line_max_text_h = 0

                continue
            }

            // Reset back to the left
            draw_pos.x = 0

            // In case this is the first token, it will hit the font_size case
            draw_pos.y += max(cur_line_max_text_h, font_size)

            cur_line_text_w = 0
            cur_line_max_text_h = 0

            if all_spaces {
                // If the spaces cause a line break, just skip em
                continue
            }

            // Move back to before this token, go down a line, and continue
            list_iterator_move_back_to_prev_once(&nodes_iter)

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
    }

    append(commands, Display_Command{
        pos = {caret_rect.x, caret_rect.y},
        sub = Display_Command_Rect{
            w = caret_rect.width,
            h = caret_rect.height,
            color = theme.data.fg_color,
        },
    })

    return true, caret_rect
}

display_command_run_all :: proc(
    commands: []Display_Command, 
    top_left: [2]f32, 
    scroll_pos: [2]f32,
) {
    for &cmd in commands {
        pos := cmd.pos + top_left - scroll_pos

        switch sub in cmd.sub {
            case Display_Command_Text: {
                rl.DrawTextEx(
                    sub.font^,
                    strings.clone_to_cstring(sub.text, context.temp_allocator),
                    position=pos,
                    fontSize=f32(sub.font.baseSize),
                    spacing=0,
                    tint=sub.color,
                )
            }

            case Display_Command_Rect: {
                rl.DrawRectangleRec(
                    rl.Rectangle{
                        pos.x,
                        pos.y,
                        sub.w,
                        sub.h,
                    },
                    sub.color,
                )
            }
        }
    }
}
