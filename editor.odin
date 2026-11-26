package main

import "core:strings"
import "core:bytes"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:time"
import te "core:text/edit"
import rl "vendor:raylib"

Editor_Mode :: enum {
    NORMAL,
    INSERT,
    COMMAND,
    VISUAL,
}

Editor_Action :: enum {
    NONE,
    DELETE,
    CHANGE,
    CHANGE_GO,
    GO,
    REPLACE,
}

Editor_Key_Mod :: enum {
    CTRL,
    SHIFT,
    ALT,
    CMD,
}

Editor_Key_Mod_State :: bit_set[Editor_Key_Mod]

Editor_Loc :: struct {
    row, col: int,
}

// See https://rxi.github.io/a_simple_undo_system.html
// for how the undo system works
Editor_Undo_Tracker :: struct {
    orig_data: []byte,
    data: union #shared_nil {^[dynamic]byte, []byte}
    
    // If data and temp data differ at commit time, then we know there's stuff to undo
}

// NOTE(Apaar): A zero-valued (i.e. data == nil) undo item is used to delimit "batches" of undos.
// When somebody hits undo, we loop through all the undos until we hit a nil.
Editor_Undo_Item :: struct {
    // TODO(Apaar): Allow updating a portion of the destination

    data: []byte,
    dest: union #shared_nil {^[dynamic]byte, []byte},
}

Editor :: struct {
    mode: Editor_Mode,

    sb: strings.Builder,
    state: te.State,

    prev_frame_sel: [2]int,
    visual_anchor: int,
    visual_characterwise: bool,
    visual_inclusive: bool,
    mouse_selecting: bool,
    mouse_selection_pos: [2]f32,
    clipboard_charwise_size: int,
    clipboard_charwise_hash: u64,

    pending_action: Editor_Action,

    command: strings.Builder,
    command_cursor: int,
    theme_request: Maybe(Theme_Choice),

    // The name of the file currently being edited
    filename: strings.Builder,

    undo_trackers: [dynamic]Editor_Undo_Tracker,

    undos: [dynamic]Editor_Undo_Item,
    redos: [dynamic]Editor_Undo_Item,

    // When the user moves the cursor, this gets set to true.
    // It remains true until the cursor comes into view.
    should_scroll_cursor_into_view: bool,

    // This field is used for drawing. They are only
    // guaranteed to be valid between editor_display_begin
    // and editor_display_end.
    display: Editor_Display_State,

    exit_requested: bool,
    canvas: ^Canvas,
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

editor_init :: proc(ed: ^Editor, system_clipboard := false) {
    te.init(
        &ed.state,
        context.allocator,
        context.allocator,
        // Opal owns undo. Suppress text/edit's additional full-buffer snapshots.
        undo_timeout = max(time.Duration),
    )
    if system_clipboard {
        ed.state.set_clipboard = editor_system_clipboard_set
        ed.state.get_clipboard = editor_system_clipboard_get
    }

    ed.sb = strings.builder_make()
    ed.command = strings.builder_make()
    ed.filename = strings.builder_make()
}

editor_clamp_cursor_to_buffer :: proc(ed: ^Editor) {
    ed.state.selection[0] = clamp(ed.state.selection[0], 0, len(ed.sb.buf))
    ed.state.selection[1] = ed.state.selection[0]
}

editor_get_text :: proc(ed: ^Editor) -> string {
    return strings.to_string(ed.sb)
}

editor_set_filename :: proc(ed: ^Editor, str: string) {
    strings.builder_reset(&ed.filename)
    strings.write_string(&ed.filename, str)
}

editor_destroy :: proc(ed: ^Editor) {
    for item in ed.undos do delete(item.data)
    for item in ed.redos do delete(item.data)
    for tracker in ed.undo_trackers do delete(tracker.orig_data)
    delete(ed.undos)
    delete(ed.redos)
    delete(ed.undo_trackers)
    strings.builder_destroy(&ed.sb)
    strings.builder_destroy(&ed.command)
    strings.builder_destroy(&ed.filename)
    delete(ed.display.checkpoints)

    te.destroy(&ed.state)
}

editor_begin_frame :: proc(ed: ^Editor) {
    te.begin(&ed.state, 0, &ed.sb)
    ed.state.selection = ed.prev_frame_sel
}

editor_end_frame :: proc(ed: ^Editor) {
    ed.prev_frame_sel = ed.state.selection
    te.end(&ed.state)
}

editor_update_state_indices :: proc(ed: ^Editor) {
    buf := ed.sb.buf[:]
    sel_pos := ed.state.selection[0]
    line_start := bytes.last_index_byte(buf[:sel_pos], '\n') + 1
    line_end := editor_find_line_end(buf, sel_pos)
    col := sel_pos - line_start

    ed.state.line_start = line_start
    ed.state.line_end = line_end
    ed.state.up_index = min(col, line_end)
    if line_start > 0 {
        prev_end := line_start - 1
        prev_start := bytes.last_index_byte(buf[:prev_end], '\n') + 1
        ed.state.up_index = min(prev_start + col, prev_end)
    }
    ed.state.down_index = len(buf)
    if line_end < len(buf) {
        next_start := line_end + 1
        ed.state.down_index = min(next_start + col, editor_find_line_end(buf, next_start))
    }
}

@(private="package")
editor_find_line_end :: proc(buf: []byte, start: int) -> int {
    end := bytes.index_byte(buf[start:], '\n')
    return len(buf) if end < 0 else start + end
}

@(private="package")
editor_insert_text :: proc(ed: ^Editor, text: string) {
    start, _ := te.sorted_selection(&ed.state)
    display_invalidate_from(ed, start)
    te.input_text(&ed.state, text)
}

@(private="file")
editor_insert_rune :: proc(ed: ^Editor, ch: rune) {
    start, _ := te.sorted_selection(&ed.state)
    display_invalidate_from(ed, start)
    te.input_rune(&ed.state, ch)
}

@(private="package")
editor_delete_selection :: proc(ed: ^Editor) {
    te.selection_delete(&ed.state)
    display_invalidate_from(ed, ed.state.selection[0])
}

@(private="file")
editor_delete_to :: proc(ed: ^Editor, translation: te.Translation) {
    te.delete_to(&ed.state, translation)
    display_invalidate_from(ed, ed.state.selection[0])
}

@(private="file")
next_empty_line_byte_index :: proc(ed: ^Editor, delta: int) -> int {
    sel_pos := ed.state.selection[0]

    loc := byte_index_to_editor_loc(sel_pos, ed.sb.buf[:])
    prev_pos := -1

    for {
        loc.row += delta

        pos := editor_loc_to_byte_index({loc.row, 0}, ed.sb.buf[:])

        // No more places to go
        if pos <= 0 || pos >= len(ed.sb.buf) || pos == prev_pos {
            return pos
        }

        // Skip runs of newlines
        if prev_pos >= 0 && (ed.sb.buf[prev_pos] == '\n' && ed.sb.buf[pos] != '\n') {
            return prev_pos
        }

        prev_pos = pos
    }

    return -1
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
        case .ZERO: t = .Soft_Line_Start
        case .FOUR: {
            valid = is_shift_pressed
            t = .Soft_Line_End
        }
        case: valid = false
    }

    return
}

@(private="package")
track_text_and_pos :: proc(ed: ^Editor) {
    editor_undo_track(ed, &ed.sb.buf)
    editor_undo_track(ed, mem.slice_to_bytes(ed.state.selection[:]))
}

editor_begin_change :: proc(ed: ^Editor, selection: [2]int) {
    track_text_and_pos(ed)
    ed.state.selection = selection
    if te.has_selection(&ed.state) do editor_delete_selection(ed)
    ed.mode = .INSERT
}

@(private="file")
editor_change_motion :: proc(ed: ^Editor, key: rl.KeyboardKey, mods: Editor_Key_Mod_State) {
    go := ed.pending_action == .CHANGE_GO
    ed.pending_action = .NONE
    if mods - {.SHIFT} != {} do return

    buf := ed.sb.buf[:]
    start, end := ed.state.line_start, ed.state.line_end
    pos := word_caret_start(buf, ed.state.selection[0])
    if go {
        if key == .G && mods == {} do editor_begin_change(ed, {0, end})
        return
    }
    if motion, ok := key_to_word_motion(key); ok {
        selection := word_change_range(buf, pos, motion, .SHIFT in mods)
        if selection[0] != selection[1] || motion == .Next do editor_begin_change(ed, selection)
        return
    }
    if mods == {.SHIFT} {
        #partial switch key {
            case .FOUR: editor_begin_change(ed, {pos, end})
            case .G:
                last := len(buf)
                if last > start && buf[last - 1] == '\n' do last -= 1
                editor_begin_change(ed, {start, last})
            case .LEFT_BRACKET, .RIGHT_BRACKET:
                target := next_empty_line_byte_index(ed, -1 if key == .LEFT_BRACKET else 1)
                if target >= 0 && target != pos do editor_begin_change(ed, {min(pos, target), max(pos, target)})
        }
        return
    }
    #partial switch key {
        case .C: editor_begin_change(ed, {start, end})
        case .ZERO, .HOME: editor_begin_change(ed, {start, pos})
        case .END: editor_begin_change(ed, {pos, end})
        case .H, .LEFT:
            if pos > start do editor_begin_change(ed, {word_previous_char(buf, pos), pos})
        case .L, .RIGHT:
            if pos < end do editor_begin_change(ed, {pos, word_next_char(buf, pos)})
        case .J, .DOWN:
            if end + 1 < len(buf) do editor_begin_change(ed, {start, editor_find_line_end(buf, end + 1)})
        case .K, .UP:
            if start > 0 do editor_begin_change(ed, {bytes.last_index_byte(buf[:start - 1], '\n') + 1, end})
        case .G: ed.pending_action = .CHANGE_GO
    }
}

@(private="file")
editor_continue_list :: proc(ed: ^Editor) -> bool {
    // Keep selection replacement and mid-line splits as plain newlines.
    if te.has_selection(&ed.state) || ed.state.selection[0] != ed.state.line_end {
        return false
    }

    skip_space :: proc(line: []byte, start: int) -> int {
        i := start
        for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
            i += 1
        }
        return i
    }

    line := ed.sb.buf[ed.state.line_start:ed.state.line_end]
    indent := skip_space(line, 0)
    if indent == len(line) do return false

    marker := line[indent]
    bullet := marker == '-' || marker == '+' || marker == '*'
    marker_end := indent + 1
    number := 0
    if !bullet {
        i := indent
        for i < len(line) && line[i] >= '0' && line[i] <= '9' {
            // Markdown allows at most nine digits in an ordered list marker.
            if i - indent == 9 do return false
            number = number * 10 + int(line[i] - '0')
            i += 1
        }
        if i == indent || i == len(line) do return false

        marker = line[i]
        if marker != '.' && marker != ')' do return false
        marker_end = i + 1
    }

    content := skip_space(line, marker_end)
    if content == marker_end do return false

    task := false
    if bullet {
        rest := line[content:]
        if len(rest) >= 3 && rest[0] == '[' && rest[2] == ']' &&
           (rest[1] == ' ' || rest[1] == 'x' || rest[1] == 'X') {
            after_box := skip_space(line, content + 3)
            if after_box == len(line) || after_box > content + 3 {
                task = true
                content = after_box
            }
        }

        if !task {
            // A spaced run of at least three matching markers is a thematic break.
            i, count := content, 1
            for i < len(line) && line[i] == marker {
                i = skip_space(line, i + 1)
                count += 1
            }
            if i == len(line) && count >= 3 do return false
        }
    }

    if content == len(line) {
        ed.state.selection = {ed.state.line_start, ed.state.line_end}
        editor_delete_selection(ed)
        return true
    }

    if !bullet && number == 999_999_999 do return false

    digits: [9]byte
    next_number := ""
    if !bullet {
        next_number = strconv.write_int(digits[:], i64(number + 1), 10)
    }

    suffix := " "
    if task do suffix = " [ ] "

    // Copy out of the editor buffer before inserting: the insert can move it.
    local: [64]byte
    prefix_len := 1 + indent + len(next_number) + 1 + len(suffix)
    prefix := local[:]
    if prefix_len > len(local) {
        prefix = make([]byte, prefix_len)
    }
    defer if prefix_len > len(local) do delete(prefix)
    prefix[0] = '\n'
    copy(prefix[1:], line[:indent])
    pos := 1 + indent
    pos += copy(prefix[pos:], next_number)
    prefix[pos] = marker
    copy(prefix[pos + 1:], suffix)
    editor_insert_text(ed, string(prefix[:prefix_len]))
    return true
}

Editor_Text_Key :: struct {
    translation: te.Translation,
    deletes: bool,
}

editor_text_letter_shortcut :: proc(key: rl.KeyboardKey, mods: Editor_Key_Mod_State) -> (Editor_Text_Key, bool) {
    if .CTRL in mods && .ALT not_in mods {
        #partial switch key {
            case .W: return {.Word_Left, true}, true
            case .A: return {.Soft_Line_Start, false}, true
            case .E: return {.Soft_Line_End, false}, true
        }
    }
    if .ALT in mods && .CTRL not_in mods {
        #partial switch key {
            case .B: return {.Word_Left, false}, true
            case .F: return {.Word_Right, false}, true
        }
    }
    return {}, false
}

@(private="file")
editor_text_key :: proc(key: rl.KeyboardKey, mods: Editor_Key_Mod_State) -> (Editor_Text_Key, bool) {
    if .CMD in mods {
        #partial switch key {
            case .LEFT: return {.Soft_Line_Start, false}, true
            case .RIGHT: return {.Soft_Line_End, false}, true
            case .UP: return {.Start, false}, true
            case .DOWN: return {.End, false}, true
            case .BACKSPACE: return {.Soft_Line_Start, true}, true
            case .DELETE: return {.Soft_Line_End, true}, true
        }
    }
    word := .ALT in mods || .CTRL in mods
    #partial switch key {
        case .LEFT: return {word ? .Word_Left : .Left, false}, true
        case .RIGHT: return {word ? .Word_Right : .Right, false}, true
        case .BACKSPACE: return {word ? .Word_Left : .Left, true}, true
        case .DELETE: return {word ? .Word_Right : .Right, true}, true
        case .HOME: return {.Soft_Line_Start, false}, true
        case .END: return {.Soft_Line_End, false}, true
    }
    return editor_text_letter_shortcut(key, mods)
}

@(private="file")
editor_handle_insert_text_key :: proc(ed: ^Editor, key: rl.KeyboardKey, mods: Editor_Key_Mod_State, action: Editor_Text_Key) {
    translation := action.translation
    has_selection := te.has_selection(&ed.state)
    if action.deletes && has_selection {
        editor_delete_selection(ed)
        return
    }
    if translation == .Word_Left || translation == .Word_Right {
        if key == .BACKSPACE && .CTRL in mods {
            editor_delete_to(ed, .Word_Left)
            return
        }
        buf := ed.sb.buf[:]
        pos := word_caret_start(buf, ed.state.selection[0])
        target := word_edit_target(buf, pos, translation == .Word_Left)
        if action.deletes && target != pos {
            ed.state.selection = {target, pos}
            editor_delete_selection(ed)
        } else {
            ed.state.selection = {target, target}
        }
    } else if action.deletes {
        pos := ed.state.selection[0]
        if translation == .Left && pos >= 4 && string(ed.sb.buf[pos - 4:pos]) == "    " {
            ed.state.selection = {pos - 4, pos}
            editor_delete_selection(ed)
        } else {
            editor_delete_to(ed, translation)
        }
    } else {
        te.move_to(&ed.state, translation)
    }
}

@(private="file")
editor_handle_command_text_key :: proc(ed: ^Editor, action: Editor_Text_Key) {
    buf := ed.command.buf[:]
    cursor := ed.command_cursor
    target := cursor
    #partial switch action.translation {
        case .Word_Left, .Word_Right:
            target = word_edit_target(buf, cursor, action.translation == .Word_Left)
        case .Left: target = max(0, cursor - 1)
        case .Right: target = min(len(buf), cursor + 1)
        case .Start, .Soft_Line_Start: target = 0
        case .End, .Soft_Line_End: target = len(buf)
    }
    if action.deletes && target != cursor {
        low, high := min(cursor, target), max(cursor, target)
        copy(buf[low:], buf[high:])
        resize(&ed.command.buf, len(buf) - (high - low))
        target = low
    }
    ed.command_cursor = target
}

editor_is_modifier_key :: proc(key: rl.KeyboardKey) -> bool {
    #partial switch key {
        case .LEFT_SHIFT, .RIGHT_SHIFT, .LEFT_CONTROL, .RIGHT_CONTROL, .LEFT_ALT, .RIGHT_ALT,
             .LEFT_SUPER, .RIGHT_SUPER:
            return true
    }
    return false
}

editor_handle_keypress :: proc(ed: ^Editor, key: rl.KeyboardKey, mods: Editor_Key_Mod_State) {
    if editor_is_modifier_key(key) do return
    ed.mouse_selecting = false

    editor_update_state_indices(ed)

    if .CTRL in mods || .CMD in mods {
        if key == .V && ed.mode != .COMMAND {
            ed.pending_action = .NONE
            editor_paste(ed)
            return
        }
        if key == .C && ed.mode == .VISUAL {
            ed.pending_action = .NONE
            editor_yank_visual(ed)
            return
        }
    }

    outer_switch: switch ed.mode {
        case .NORMAL: {
            if key == .R && .CTRL in mods {
                ed.pending_action = .NONE
                editor_redo(ed)
                break
            }

            switch ed.pending_action {
                case .CHANGE, .CHANGE_GO:
                    editor_change_motion(ed, key, mods)
                    break outer_switch

                case .GO: {
                    if key == .G {
                        te.move_to(&ed.state, .Start)
                    }

                    ed.pending_action = .NONE
                    break outer_switch
                }

                case .DELETE: {
                    track_text_and_pos(ed)
                    defer editor_undo_commit(ed)

                    ed.pending_action = .NONE

                    if key == .D {
                        // Delete the line
                        te.move_to(&ed.state, .Soft_Line_End)
                        editor_delete_to(ed, .Soft_Line_Start)
                        editor_delete_to(ed, .Left)
                        break outer_switch
                    }

                    if motion, ok := key_to_word_motion(key); ok {
                        if !te.has_selection(&ed.state) {
                            ed.state.selection = word_delete_range(ed.sb.buf[:], ed.state.selection[0], motion, .SHIFT in mods)
                        }
                        if te.has_selection(&ed.state) {
                            editor_delete_selection(ed)
                        }
                        break outer_switch
                    }

                    translation, valid := key_to_translation(key, .SHIFT in mods)

                    if !valid {
                        break outer_switch
                    }

                    editor_delete_to(ed, translation)
                    break outer_switch
                }

                case .REPLACE: {
                    // Whatever key was pressed should've been handled as a charpress
                    ed.pending_action = .NONE
                    break outer_switch
                }

                case .NONE:
            }

            if key == .ESCAPE && ed.canvas != nil {
                ed.canvas.finish_editing = true
                break
            }

            if key == .LEFT_BRACKET && .SHIFT in mods {
                ed.state.selection[0] = next_empty_line_byte_index(ed, -1)
            }

            if key == .RIGHT_BRACKET && .SHIFT in mods {
                ed.state.selection[0] = next_empty_line_byte_index(ed, 1)
            }

            if key == .V && mods - {.SHIFT} == {} {
                ed.visual_characterwise = .SHIFT not_in mods
                ed.visual_inclusive = ed.visual_characterwise
                ed.visual_anchor = ed.state.line_start
                if ed.visual_characterwise {
                    ed.visual_anchor = word_caret_start(ed.sb.buf[:], ed.state.selection[0])
                    ed.state.selection = {ed.visual_anchor, ed.visual_anchor}
                }
                ed.mode = .VISUAL
                break
            }
            if key == .P && mods - {.SHIFT} == {} {
                editor_paste(ed, before = .SHIFT in mods)
                break
            }

            if key == .R {
                ed.pending_action = .REPLACE

                break
            }

            if key == .G {
                if .SHIFT in mods {
                    te.move_to(&ed.state, .End)
                } else {
                    ed.pending_action = .GO
                }

                break
            }

            if key == .U {
                editor_undo(ed)
            }

            if key == .X {
                editor_undo_track(ed, &ed.sb.buf)
                defer editor_undo_commit(ed)

                editor_delete_to(ed, .Right)
            }

            if key == .I {
                if .SHIFT in mods {
                    te.move_to(&ed.state, .Soft_Line_Start)
                }

                ed.mode = .INSERT

                // Start tracking now and don't commit until we exit insert mode
                track_text_and_pos(ed)
            }

            if key == .SEMICOLON && .SHIFT in mods {
                ed.mode = .COMMAND
            }

            if key == .A {
                track_text_and_pos(ed)

                if .SHIFT in mods {
                    te.move_to(&ed.state, .Soft_Line_End)
                } else {
                    te.move_to(&ed.state, .Right)
                }

                ed.mode = .INSERT
            }

            if key == .O {
                track_text_and_pos(ed)

                if .SHIFT in mods {
                    te.move_to(&ed.state, .Soft_Line_Start)
                    editor_insert_text(ed, "\n")
                    te.move_to(&ed.state, .Left)
                } else {
                    te.move_to(&ed.state, .Soft_Line_End)
                    editor_insert_text(ed, "\n")
                }

                ed.mode = .INSERT
            }

            if key == .D {
                ed.pending_action = .DELETE
                break
            }

            if key == .C && mods - {.SHIFT} == {} {
                if .SHIFT in mods {
                    pos := word_caret_start(ed.sb.buf[:], ed.state.selection[0])
                    editor_begin_change(ed, {pos, ed.state.line_end})
                } else {
                    ed.pending_action = .CHANGE
                }
                break
            }

            if motion, ok := key_to_word_motion(key); ok {
                pos := word_motion_target(ed.sb.buf[:], ed.state.selection[0], motion, .SHIFT in mods)
                ed.state.selection = {pos, pos}
                break
            }

            translation, valid := key_to_translation(key, .SHIFT in mods)

            if valid {
                te.move_to(&ed.state, translation)
            }
        }
        
        case .INSERT: {
            if key == .ESCAPE {
                editor_undo_commit(ed)
                ed.mode = .NORMAL
            }

            if key == .LEFT_BRACKET && .CTRL in mods {
                editor_undo_commit(ed)
                ed.mode = .NORMAL
            }

            if action, ok := editor_text_key(key, mods); ok {
                editor_handle_insert_text_key(ed, key, mods, action)
                break
            }
            if key == .UP do te.move_to(&ed.state, .Up)
            if key == .DOWN do te.move_to(&ed.state, .Down)

            if key == .ENTER && (mods != {} || !editor_continue_list(ed)) {
                editor_insert_text(ed, "\n")
            }
            
            if key == .TAB {
                editor_insert_text(ed, "    ")
            }
        }

        case .VISUAL: {
            was_go := ed.pending_action == .GO
            ed.pending_action = .NONE
            if ed.visual_characterwise && mods - {.SHIFT} == {} {
                if motion, ok := key_to_word_motion(key); ok {
                    pos := word_motion_target(ed.sb.buf[:], ed.state.selection[0], motion, .SHIFT in mods)
                    ed.state.selection = {pos, pos}
                    break
                }
            }
            #partial switch key {
                case .ESCAPE: ed.mode = .NORMAL
                case .V:
                    if mods - {.SHIFT} == {} {
                        characterwise := .SHIFT not_in mods
                        if characterwise == ed.visual_characterwise {
                            ed.mode = .NORMAL
                        } else {
                            if !characterwise {
                                ed.visual_anchor = bytes.last_index_byte(ed.sb.buf[:ed.visual_anchor], '\n') + 1
                            }
                            ed.visual_characterwise = characterwise
                            ed.visual_inclusive = characterwise
                        }
                    }
                case .LEFT_BRACKET:
                    if .CTRL in mods do ed.mode = .NORMAL
                case .J, .DOWN: te.move_to(&ed.state, .Down)
                case .K, .UP: te.move_to(&ed.state, .Up)
                case .H, .LEFT, .L, .RIGHT:
                    if ed.visual_characterwise {
                        buf := ed.sb.buf[:]
                        pos := word_caret_start(buf, ed.state.selection[0])
                        if key == .H || key == .LEFT {
                            pos = word_previous_char(buf, pos)
                        } else if pos < len(buf) {
                            pos = word_next_char(buf, pos)
                        }
                        ed.state.selection = {pos, pos}
                    }
                case .ZERO:
                    if ed.visual_characterwise && mods == {} do te.move_to(&ed.state, .Soft_Line_Start)
                case .FOUR:
                    if ed.visual_characterwise && mods == {.SHIFT} do te.move_to(&ed.state, .Soft_Line_End)
                case .G:
                    if .SHIFT in mods do te.move_to(&ed.state, .End)
                    else if was_go do te.move_to(&ed.state, .Start)
                    else do ed.pending_action = .GO
                case .Y: if mods - {.SHIFT} == {} do editor_yank_visual(ed)
                case .D: if mods == {} do editor_delete_visual(ed)
                case .C: if mods == {} do editor_change_visual(ed)
                case .P: if mods - {.SHIFT} == {} do editor_paste(ed)
            }
        }

        case .COMMAND: {
            if action, ok := editor_text_key(key, mods); ok {
                editor_handle_command_text_key(ed, action)
                break
            }

            if key == .ESCAPE {
                strings.builder_reset(&ed.command)
                ed.command_cursor = 0
                ed.mode = .NORMAL
            }

            if key == .ENTER {
                src := strings.to_string(ed.command)
                cmd, ok := command_parse(&src)

                if ok {
                    command_run(&cmd, ed)
                } else {
                    // TODO(Apaar): Show status in bar (cleared after some time)
                    fmt.println("Command failed")
                }

                strings.builder_reset(&ed.command)
                ed.command_cursor = 0
                ed.mode = .NORMAL
            }
        }
    }
}

@(private="file")
is_ascii :: proc(ch: rune) -> bool {
    return ch >= 32 && ch <= 125
}

editor_handle_charpress :: proc(ed: ^Editor, ch: rune) {
    switch ed.mode {
        case .VISUAL: // Visual mode uses key bindings rather than text input.
        case .NORMAL: {
            if ed.pending_action == .REPLACE {
                track_text_and_pos(ed)
                editor_delete_to(ed, .Right)
                editor_insert_rune(ed, ch)
                te.move_to(&ed.state, .Left)

                editor_undo_commit(ed)

                // FIXME(Apaar): Don't know why but I can't move the cursor back to orig pos
                // otherwise the edit doesn't happen????

                break
            }
        }

        case .INSERT: {
            if ch < ' ' || ch == 127 {
                break
            }

            editor_insert_rune(ed, ch)
        }
        
        case .COMMAND: {
            if !is_ascii(ch) {
                break
            }

            if ok, _ := inject_at(&ed.command.buf, ed.command_cursor, byte(ch)); ok {
                ed.command_cursor += 1
            }
        }
    }
}
