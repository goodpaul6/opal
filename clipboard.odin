package main

import "core:bytes"
import "core:strings"
import te "core:text/edit"
import rl "vendor:raylib"

editor_system_clipboard_set :: proc(_: rawptr, text: string) -> bool {
    if strings.index_byte(text, 0) >= 0 do return false
    value, err := strings.clone_to_cstring(text, context.temp_allocator)
    if err != nil do return false
    rl.SetClipboardText(value)
    return true
}

editor_system_clipboard_get :: proc(_: rawptr) -> (string, bool) {
    value := rl.GetClipboardText()
    if value == nil do return "", false
    return string(value), true
}

// Keep the caret separate from the linewise selection so ordinary motions
// and undo can still use the editor's existing caret state.
editor_visual_lines :: proc(ed: ^Editor) -> [2]int {
    buf := ed.sb.buf[:]
    head := clamp(ed.state.selection[0], 0, len(buf))
    line_start := bytes.last_index_byte(buf[:head], '\n') + 1
    return {min(ed.visual_anchor, line_start), max(ed.visual_anchor, line_start)}
}

@(private="file")
editor_visual_range :: proc(ed: ^Editor) -> [2]int {
    lines := editor_visual_lines(ed)
    end := editor_find_line_end(ed.sb.buf[:], lines[1])
    return {lines[0], min(end + 1, len(ed.sb.buf))}
}

@(private="file")
editor_copy_lines :: proc(ed: ^Editor, selection: [2]int) -> bool {
    if ed.state.set_clipboard == nil do return false
    text := string(ed.sb.buf[selection[0]:selection[1]])
    if len(text) == 0 || text[len(text) - 1] != '\n' {
        with_newline, err := strings.concatenate({text, "\n"}, context.temp_allocator)
        if err != nil do return false
        text = with_newline
    }
    return ed.state.set_clipboard(ed.state.clipboard_user_data, text)
}

editor_yank_lines :: proc(ed: ^Editor) {
    selection := editor_visual_range(ed)
    if editor_copy_lines(ed, selection) {
        ed.state.selection = {selection[0], selection[0]}
        ed.mode = .NORMAL
    }
}

editor_delete_visual_lines :: proc(ed: ^Editor) {
    selected := editor_visual_range(ed)
    selection := selected
    ed.mode = .NORMAL

    buf := ed.sb.buf[:]
    through_end := selection[1] == len(buf)
    // When the last line has no terminator, delete its preceding separator.
    if through_end && selection[0] > 0 && (selection[0] == selection[1] || buf[len(buf) - 1] != '\n') {
        selection[0] -= 1
    }
    if selection[0] == selection[1] do return

    editor_copy_lines(ed, selected)
    track_text_and_pos(ed)
    defer editor_undo_commit(ed)
    ed.state.selection = selection
    editor_delete_selection(ed)
    if through_end && len(ed.sb.buf) > 0 {
        // Put the caret on the last surviving line.
        end := len(ed.sb.buf)
        if ed.sb.buf[end - 1] == '\n' do end -= 1
        pos := bytes.last_index_byte(ed.sb.buf[:end], '\n') + 1
        ed.state.selection = {pos, pos}
    }
}

editor_paste :: proc(ed: ^Editor, before := false) {
    if ed.state.get_clipboard == nil do return
    text, ok := ed.state.get_clipboard(ed.state.clipboard_user_data)
    if !ok || len(text) == 0 do return
    text, _ = strings.replace_all(text, "\r\n", "\n", context.temp_allocator)
    if len(text) == 0 do return

    size := len(ed.sb.buf)
    selection := ed.state.selection
    linewise := text[len(text) - 1] == '\n'
    caret := selection[0]
    if ed.mode == .VISUAL {
        selection = editor_visual_range(ed)
        caret = selection[0]
        keeps_terminator := selection[1] < size ||
            (selection[1] > selection[0] && ed.sb.buf[selection[1] - 1] == '\n')
        if keeps_terminator && !linewise {
            with_newline, err := strings.concatenate({text, "\n"}, context.temp_allocator)
            if err != nil do return
            text = with_newline
        }
    } else if ed.mode == .NORMAL {
        if linewise {
            pos := ed.state.line_start
            if !before {
                pos = min(ed.state.line_end + 1, size)
            }
            caret = pos
            if !before && ed.state.line_end == size && size > 0 {
                with_newline, err := strings.concatenate({"\n", text}, context.temp_allocator)
                if err != nil do return
                text = with_newline
                caret += 1
            }
            selection = {pos, pos}
        } else {
            pos := word_caret_start(ed.sb.buf[:], selection[0])
            if !before do pos = min(ed.state.line_end, te.translate_position(&ed.state, .Right))
            selection = {pos, pos}
        }
    } else {
        for &pos in selection do pos = word_caret_start(ed.sb.buf[:], pos)
    }

    // Reserve before replacing a selection so an allocation failure leaves it intact.
    remaining := size - abs(selection[0] - selection[1])
    if len(text) > max(int) - remaining || reserve(&ed.sb.buf, remaining + len(text)) != nil do return
    if ed.mode == .INSERT {
        ed.state.selection = selection
        editor_insert_text(ed, text)
        return
    }

    track_text_and_pos(ed)
    defer editor_undo_commit(ed)
    visual := ed.mode == .VISUAL
    ed.mode = .NORMAL
    ed.state.selection = selection
    editor_insert_text(ed, text)
    if visual || linewise {
        ed.state.selection = {caret, caret}
    } else {
        te.move_to(&ed.state, .Left)
    }
}
