package main

import "core:strings"
import "core:fmt"
import nvg "vendor:nanovg"

Display_Command_Text :: struct {
    text: string,
    font: Theme_Font_ID,
    color: nvg.Color,
}

Display_Command_Rect :: struct {
    w, h: f32,
    color: nvg.Color,
}

Display_Command :: struct {
    pos: [2]f32,
    sub: union #no_nil {
        Display_Command_Text,
        Display_Command_Rect,
    }
}

@(private="file")
measure_text :: proc(nvc: ^nvg.Context, text: string) -> [2]f32 {
    bounds := [4]f32{}

    nvg.TextBounds(nvc, 0, 0, text, &bounds)

    return {bounds[2] - bounds[0], bounds[3] - bounds[1]}
}

// HACK(Apaar): I return the caret rectangle from this for smoothly scrolling
// the cursor into the bounds
display_command_gen :: proc(
    ed: ^Editor, 
    theme: ^Theme,
    nvc: ^nvg.Context,
    bounds_size: [2]f32,
    commands: ^[dynamic]Display_Command,
) -> (ok: bool, caret_rect: Rect) {
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

    _, _, min_line_height := nvg.TextMetrics(nvc)

    loop: for node in list_iterator_iterate(&nodes_iter) {
        contains_caret := node.extents[0] <= sel_pos && sel_pos <= node.extents[1]
        
        caret_idx := contains_caret ? sel_pos - node.extents[0] : -1

        font: Theme_Font_ID
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
                if sub.pre do font = theme.fonts[.PRE]
                else do font = theme.fonts[.BODY]

                all_spaces = sub.all_spaces
        }

        nvg.FontFaceId(nvc, font)

        token_str := node_literal_string(node^)
        token_size := measure_text(nvc, token_str)

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
                draw_pos.y += max(cur_line_max_text_h, min_line_height)

                cur_line_text_w = 0
                cur_line_max_text_h = 0

                continue
            }

            // Reset back to the left
            draw_pos.x = 0

            // In case this is the first token, it will hit the font_size case
            draw_pos.y += max(cur_line_max_text_h, min_line_height)

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
            sub_text_size := measure_text(nvc, sub_text)

            caret_rect = {draw_pos.x + sub_text_size.x, draw_pos.y, 2, sub_text_size.y}
        }

        draw_pos.x += token_size.x
    }

    append(commands, Display_Command{
        pos = {caret_rect.x, caret_rect.y},
        sub = Display_Command_Rect{
            w = caret_rect.w,
            h = caret_rect.h,
            color = theme.data.fg_color,
        },
    })

    return true, caret_rect
}

display_command_run_all :: proc(
    commands: []Display_Command, 
    nvc: ^nvg.Context,
    top_left: [2]f32, 
    scroll_pos: [2]f32,
) {
    for &cmd in commands {
        pos := cmd.pos + top_left - scroll_pos

        switch sub in cmd.sub {
            case Display_Command_Text: {
                nvg.StrokeColor(nvc, sub.color)
                nvg.Text(nvc, pos.x, pos.y, sub.text)
            }

            case Display_Command_Rect: {
                nvg.BeginPath(nvc)

                nvg.FillColor(nvc, sub.color)
                nvg.Rect(nvc, pos.x, pos.y, sub.w, sub.h)

                nvg.Fill(nvc)
            }
        }
    }
}
