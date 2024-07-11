package main

import "core:strings"
import "core:bytes"
import "core:fmt"
import te "core:text/edit"
import rl "vendor:raylib"

Editor_Mode :: enum {
    NORMAL,
    INSERT,
    COMMAND,
}

Editor_Action :: enum {
    NONE,
    DELETE,
}

Editor_Loc :: struct {
    row, col: int,
}

Editor :: struct {
    mode: Editor_Mode,
    sel: [2]int,
    sb: strings.Builder,
    state: te.State,

    pending_action: Editor_Action,

    // TODO(Apaar): We could technically use a fixed backing array for this string builder
    status: strings.Builder,

    // TODO(Apaar): Perhaps this should be managed via a text/edit state too?
    command: strings.Builder,
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
    status = strings.builder_make()
    command = strings.builder_make()
}

editor_set_status_to_string :: proc(using ed: ^Editor, str: string) {
    strings.builder_reset(&status)
    strings.write_string(&status, str)
}

editor_destroy :: proc(using ed: ^Editor) {
    strings.builder_destroy(&sb)
    strings.builder_destroy(&status)
    strings.builder_destroy(&command)

    te.destroy(&state)
}

editor_begin_frame :: proc(using ed: ^Editor) {
    te.begin(&state, 0, &sb)
    state.selection = sel

    switch(mode) {
        case .INSERT: {
            editor_set_status_to_string(ed, "-- INSERT --")
        }

        case .NORMAL: {
            editor_set_status_to_string(ed, "")
        }

        case .COMMAND: {
            // HACK(Apaar): Not necessarily a good idea to hijack the status for this but ok
            editor_set_status_to_string(ed, fmt.tprintf(":%s", strings.to_string(command)))
        }
    }
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

@(private="file")
key_to_translation :: proc(key: rl.KeyboardKey, is_shift_pressed: bool) -> (t: te.Translation, valid: bool) {
    // For most cases we don't want shift to be pressed
    valid = !is_shift_pressed

    #partial switch(key) {
        case .H: t = .Left
        case .L: t = .Right
        case .K: t = .Up
        case .J: t = .Down
        case .B: t = .Word_Left
        // TODO(Apaar): Handle going to the end of the word, end of next word, etc
        case .W, .E: t = .Word_Right
        case .ZERO: t = .Soft_Line_Start
        case .FOUR: {
            valid = is_shift_pressed
            t = .Soft_Line_End
        }
        case: valid = false
    }

    return
}

editor_handle_keypress :: proc(using ed: ^Editor, key: rl.KeyboardKey, is_ctrl_pressed: bool, is_shift_pressed: bool) {
    if key == .LEFT_SHIFT || key == .RIGHT_SHIFT {
        // This should do nothing
        return
    }

    editor_update_state_indices(ed)

    switch mode {
        case .NORMAL: {
            if pending_action == .DELETE {
                pending_action = .NONE

                if key == .D {
                    // Delete the line
                    te.move_to(&state, .Soft_Line_End)
                    te.delete_to(&state, .Soft_Line_Start)
                    te.delete_to(&state, .Left)
                    break
                }

                translation, valid := key_to_translation(key, is_shift_pressed)
                
                if !valid {
                    break
                }

                te.delete_to(&state, translation)
                break
            }

            if key == .X {
                te.delete_to(&state, .Right)
            }

            if key == .I {
                if is_shift_pressed {
                    te.move_to(&state, .Soft_Line_Start)
                }

                mode = .INSERT
            }

            if key == .SEMICOLON && is_shift_pressed {
                mode = .COMMAND
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

            if key == .D {
                pending_action = .DELETE
                break
            }

            translation, valid := key_to_translation(key, is_shift_pressed)

            if valid {
                te.move_to(&state, translation)
            }
        }
        
        case .INSERT: {
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

        case .COMMAND: {
            if key == .BACKSPACE {
                // TODO(Apaar): Handle ctrl + backspace
                strings.pop_rune(&command)
            }

            if key == .ESCAPE {
                strings.builder_reset(&command)
                mode = .NORMAL
            }

            if key == .ENTER {
                // TODO(Apaar): Run command

                strings.builder_reset(&command)
                mode = .NORMAL
            }
        }
    }
}

@(private="file")
is_ascii :: proc(ch: rune) -> bool {
    return ch >= 32 && ch <= 125
}

editor_handle_charpress :: proc(using ed: ^Editor, ch: rune) {
    switch mode {
        case .NORMAL: {
        }

        case .INSERT: {
            // TODO(Apaar): Allow non-ascii input
            if !is_ascii(ch) {
                break
            }

            te.input_rune(&state, ch)
        }
        
        case .COMMAND: {
            if !is_ascii(ch) {
                break
            }

            strings.write_rune(&command, ch)
        }
    }
}
