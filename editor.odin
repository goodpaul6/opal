package main

import rl "vendor:raylib"

Editor_Mode :: enum {
    NORMAL,
    INSERT,
}

Editor :: struct {
    mode: Editor_Mode,
    buf: Buffer,
    pos: Pos,
}

delete_editor :: proc(using ed: ^Editor) {
    delete_buffer(&buf)
}

handle_keypress :: proc(using ed: ^Editor, key: rl.KeyboardKey, is_ctrl_pressed: bool, is_shift_pressed: bool) {
    switch mode {
        case .NORMAL: {
            if key == .H {
                pos.col -= 1
            }

            if key == .L {
                pos.col += 1
            }

            if key == .K {
                pos.row -= 1
            }

            if key == .J {
                pos.row += 1
            }

            if key == .I {
                if is_shift_pressed {
                    pos.col = 0
                }

                mode = .INSERT
            }

            if key == .O {
                if is_shift_pressed {
                    insert_empty_line(&buf, pos)
                } else {
                    pos.row += 1
                    insert_empty_line(&buf, pos)
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
                if pos.col > 0 {
                    pos.col -= 1
                    remove_rune(&buf, pos)
                } else if pos.row > 0 {
                    pos = shift_line_up(&buf, pos)
                }
            }

            if key == .ENTER {
                inject_empty_line(&buf, pos)
                pos.row += 1
                pos.col = 0
            }
        }
    }

    clamp_pos_to_buffer(&pos, &buf)
}

handle_charpress :: proc(using ed: ^Editor, ch: rune) {
    switch mode {
        case .NORMAL: {
        }

        case .INSERT: {
            if ch < 32 || ch > 125 {
                break
            }

            insert_rune(&buf, pos, ch)
            pos.col += 1
        }
    }
}
