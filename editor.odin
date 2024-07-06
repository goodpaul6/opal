package main

import "core:strings"
import "core:bytes"
import "core:fmt"
import te "core:text/edit"
import rl "vendor:raylib"

Editor_Mode :: enum {
    NORMAL,
    INSERT,
}

Editor :: struct {
    mode: Editor_Mode,
    sel: [2]int,
    sb: strings.Builder,
    state: te.State,
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

    prev_line_end := bytes.last_index_byte(sb.buf[:sel_pos], '\n')

    state.line_start = prev_line_end < 0 ? 0 : prev_line_end + 1

    if sel_pos >= strings.builder_len(sb) {
        state.line_end = sel_pos
        state.down_index = sel_pos
    }

    if prev_line_end < 0 {
        state.up_index = 0
        return
    }

    prev_prev_line_end := max(bytes.last_index_byte(sb.buf[:prev_line_end], '\n'), 0)

    bytes_from_start_of_line := sel_pos - prev_line_end
    state.up_index = prev_prev_line_end + bytes_from_start_of_line
}

editor_handle_keypress :: proc(using ed: ^Editor, key: rl.KeyboardKey, is_ctrl_pressed: bool, is_shift_pressed: bool) {
    editor_update_state_indices(ed)

    switch mode {
        case .NORMAL: {
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
                    te.move_to(&state, .Start)
                }

                mode = .INSERT
            }

            if key == .O {
                if is_shift_pressed {
                    te.input_text(&state, "\n")
                } else {
                    te.move_to(&state, .End)
                    te.input_text(&state, "\n")
                    te.move_to(&state, .Down)
                }

                mode = .INSERT
            }
        }
        
        case .INSERT: {
            // TODO(Apaar): Handle arrow keys in insert mode

            if key == .ESCAPE {
                mode = .NORMAL
            }

            if key == .BACKSPACE {
                if is_ctrl_pressed {
                    te.delete_to(&state, .Word_Left)
                } else {
                    te.delete_to(&state, .Left)
                }
            }

            if key == .ENTER {
                te.input_text(&state, "\n")
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
