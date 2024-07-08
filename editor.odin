package main

import "core:strings"
import "core:bytes"
import te "core:text/edit"
import rl "vendor:raylib"

Editor_Mode :: enum {
    NORMAL,
    INSERT,
}

Editor_Loc :: struct {
    row, col: int
}

Editor :: struct {
    mode: Editor_Mode,
    sel: [2]int,
    sb: strings.Builder,
    state: te.State,
}

byte_index_to_editor_loc :: proc(idx: int, input_buf: []byte) -> Editor_Loc {
    buf := input_buf[:idx]
    row := 0

    for {
        next_pos := bytes.index_byte(buf, '\n')

        if next_pos < 0 {
            break
        }

        buf = buf[next_pos + 1:]
        row += 1
    }

    col := len(buf)

    return {row, col}
}

// Clamps the result to len(buf) inclusive
editor_loc_to_byte_index :: proc(loc: Editor_Loc, buf: []byte) -> int {
    buf := buf

    byte_idx := 0

    for row := 0; row < loc.row; row += 1 {
        line_end := bytes.index_byte(buf, '\n')
        if line_end < 0 do break

        buf = buf[line_end + 1:]
        byte_idx += line_end + 1
    }

    max_col := bytes.index_byte(buf, '\n')
    if max_col < 0 do max_col = len(buf)

    return byte_idx + min(loc.col, max_col)
}

editor_init :: proc(using ed: ^Editor) {
    te.init(
        &state,
        context.allocator,
        context.allocator,
    )

    sb = strings.builder_make()
}

editor_destroy :: proc(using ed: ^Editor) {
    strings.builder_destroy(&sb)

    te.destroy(&state)
}

editor_begin_frame :: proc(using ed: ^Editor) {
    te.begin(&state, 0, &sb)
    state.selection = sel
}

editor_end_frame :: proc(using ed: ^Editor) {
    sel = state.selection
    te.end(&state)
}

editor_update_state_indices :: proc(using ed: ^Editor) {
    sel_pos := state.selection[0]

    state.line_end = bytes.index_byte(sb.buf[sel_pos:], '\n')
    if state.line_end < 0 {
        state.line_end = len(sb.buf)
    } else {
        state.line_end += sel_pos
    }

    loc := byte_index_to_editor_loc(sel_pos, sb.buf[:])
    
    state.line_start = editor_loc_to_byte_index({loc.row, 0}, sb.buf[:])
    
    state.up_index = editor_loc_to_byte_index({loc.row - 1, loc.col}, sb.buf[:])
    state.down_index = editor_loc_to_byte_index({loc.row + 1, loc.col}, sb.buf[:])
}

editor_handle_keypress :: proc(using ed: ^Editor, key: rl.KeyboardKey, is_ctrl_pressed: bool, is_shift_pressed: bool) {
    editor_update_state_indices(ed)

    switch mode {
        case .NORMAL: {
            if key == .X {
                te.delete_to(&state, .Right)
            }

            if key == .H {
                te.move_to(&state, .Left)
            }

            if key == .L {
                te.move_to(&state, .Right)
            }

            if key == .K {
                te.move_to(&state, .Up)
            }

            if key == .J {
                te.move_to(&state, .Down)
            }

            if key == .I {
                if is_shift_pressed {
                    te.move_to(&state, .Soft_Line_Start)
                }

                mode = .INSERT
            }

            if key == .A {
                if is_shift_pressed {
                    te.move_to(&state, .Soft_Line_End)
                } else {
                    te.move_to(&state, .Right)
                }

                mode = .INSERT
            }

            if key == .O {
                if is_shift_pressed {
                    te.move_to(&state, .Soft_Line_Start)
                    te.input_text(&state, "\n")
                    te.move_to(&state, .Left)
                } else {
                    te.move_to(&state, .End)
                    te.input_text(&state, "\n")

                    editor_update_state_indices(ed)

                    te.move_to(&state, .Down)
                }

                mode = .INSERT
            }

            if key == .B {
                te.move_to(&state, .Word_Left)
            }

            if key == .E {
                te.move_to(&state, .Word_Right)
            }

            if key == .ZERO {
                te.move_to(&state, .Soft_Line_Start)
            }

            if key == .FOUR && is_shift_pressed {
                te.move_to(&state, .Soft_Line_End)
            }
        }
        
        case .INSERT: {
            // TODO(Apaar): Handle arrow keys in insert mode

            if key == .ESCAPE {
                mode = .NORMAL
            }

            if key == .LEFT_BRACKET && is_ctrl_pressed {
                mode = .NORMAL
            }

            if key == .BACKSPACE {
                sel_pos := sel[0]
                is_at_soft_tab := 
                    (sel_pos - 4) >= 0 && 
                    string(sb.buf[sel_pos - 4:sel_pos]) == "    "

                if is_ctrl_pressed {
                    te.delete_to(&state, .Word_Left)
                } else if !is_at_soft_tab {
                    te.delete_to(&state, .Left)
                } else {
                    state.selection[0] -= 4
                    te.selection_delete(&state)
                }
            }

            if key == .ENTER {
                te.input_text(&state, "\n")
            }
            
            if key == .TAB {
                te.input_text(&state, "    ")
            }
        }
    }
}

editor_handle_charpress :: proc(using ed: ^Editor, ch: rune) {
    switch mode {
        case .NORMAL: {
        }

        case .INSERT: {
            if ch < 32 || ch > 125 {
                break
            }

            te.input_rune(&state, ch)
        }
    }
}
