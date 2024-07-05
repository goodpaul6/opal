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

handle_keypress :: proc(using ed: ^Editor, key: rl.KeyboardKey) {
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
                mode = .INSERT
            }
        }
        
        case .INSERT: {
            // TODO(Apaar): Handle arrow keys in insert mode

            if key == .ESCAPE {
                mode = .NORMAL
            }

            if key == .BACKSPACE && pos.col > 0 {
                pos.col -= 1
                remove_rune(&buf, pos)
            }

            if key == .ENTER {
                insert_empty_line_below(&buf, pos)
                pos.row += 1
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
