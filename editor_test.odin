package main

import "core:strings"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_editor_loc :: proc(t: ^testing.T) {
    s := transmute([]byte) string("AAAA\nAAAA\nAAA")

    loc := byte_index_to_editor_loc(0, s)

    testing.expect_value(t, loc.row, 0)
    testing.expect_value(t, loc.col, 0)

    idx := editor_loc_to_byte_index(loc, s)

    testing.expect_value(t, idx, 0)

    loc = byte_index_to_editor_loc(4, s)

    testing.expect_value(t, loc.row, 0)
    testing.expect_value(t, loc.col, 4)

    idx = editor_loc_to_byte_index(loc, s)

    testing.expect_value(t, idx, 4)

    loc = byte_index_to_editor_loc(5, s)

    testing.expect_value(t, loc.row, 1)
    testing.expect_value(t, loc.col, 0)

    idx = editor_loc_to_byte_index(loc, s)

    testing.expect_value(t, idx, 5)

    idx = editor_loc_to_byte_index({5, 5}, s)

    testing.expect_value(t, idx, len(s))

    idx = editor_loc_to_byte_index({2, 2}, s)

    testing.expect_value(t, idx, 12)
}

@(test)
test_editor_local_line_indices_match_row_and_column :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)
    strings.write_string(&ed.sb, "\nalpha\n\né\nx\nend\n")
    buf := ed.sb.buf[:]
    for pos in 0..=len(buf) {
        ed.state.selection = {pos, pos}
        editor_update_state_indices(&ed)
        loc := byte_index_to_editor_loc(pos, buf)
        testing.expect_value(t, ed.state.line_start, editor_loc_to_byte_index({loc.row, 0}, buf))
        testing.expect_value(t, ed.state.up_index, editor_loc_to_byte_index({loc.row - 1, loc.col}, buf))
        testing.expect_value(t, ed.state.down_index, editor_loc_to_byte_index({loc.row + 1, loc.col}, buf))
    }
}

@(test)
test_open_line_below_or_above_current_line :: proc(t: ^testing.T) {
    cases := [?]struct {
        before, after: string,
        caret, want: int,
        mods: Editor_Key_Mod_State,
    }{
        {"top\nmiddle\nbottom", "top\nmiddle\n\nbottom", 6, len("top\nmiddle\n"), {}},
        {"top\nmiddle\nbottom", "top\n\nmiddle\nbottom", 6, len("top\n"), {.SHIFT}},
        {"top\nbottom", "top\nbottom\n", 5, len("top\nbottom\n"), {}},
        {"top\n", "top\n\n", 3, len("top\n"), {}},
        {"", "\n", 0, 1, {}},
    }
    for c in cases {
        ed: Editor
        editor_init(&ed)
        defer editor_destroy(&ed)
        strings.write_string(&ed.sb, c.before)
        ed.prev_frame_sel = {c.caret, c.caret}
        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)
        editor_handle_keypress(&ed, .O, c.mods)
        testing.expect_value(t, ed.mode, Editor_Mode.INSERT)
        testing.expect_value(t, editor_get_text(&ed), c.after)
        testing.expect_value(t, ed.state.selection, [2]int{c.want, c.want})
        editor_handle_keypress(&ed, .ESCAPE, {})
    }
}

@(test)
test_redo_shortcut_survives_navigation_and_empty_insert :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)
    strings.write_string(&ed.sb, "abc")
    ed.prev_frame_sel = {1, 1}
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)

    editor_handle_keypress(&ed, .X, {})
    editor_handle_keypress(&ed, .U, {})
    testing.expect_value(t, editor_get_text(&ed), "abc")
    editor_handle_keypress(&ed, .G, {.SHIFT})
    testing.expect_value(t, ed.state.selection[0], 3)
    editor_handle_keypress(&ed, .H, {})
    editor_handle_keypress(&ed, .A, {})
    editor_handle_keypress(&ed, .ESCAPE, {})
    testing.expect_value(t, ed.state.selection[0], 3)

    editor_handle_keypress(&ed, .R, {})
    testing.expect_value(t, ed.pending_action, Editor_Action.REPLACE)
    live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.R}, []rune{'r'}, {.CTRL}, false, false)
    testing.expect_value(t, ed.pending_action, Editor_Action.NONE)
    testing.expect_value(t, editor_get_text(&ed), "ac")
    testing.expect_value(t, ed.state.selection, [2]int{2, 2})

    editor_handle_keypress(&ed, .U, {})
    editor_handle_keypress(&ed, .I, {})
    editor_handle_charpress(&ed, 'z')
    editor_handle_keypress(&ed, .ESCAPE, {})
    editor_handle_keypress(&ed, .R, {.CTRL})
    testing.expect_value(t, editor_get_text(&ed), "abzc")
    testing.expect_value(t, len(ed.redos), 0)
    testing.expect_value(t, ed.pending_action, Editor_Action.NONE)
}

@(test)
test_insert_word_shortcuts_preserve_utf8_and_undo :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)
    src :: "one café.test"
    strings.write_string(&ed.sb, src)
    ed.prev_frame_sel = {len(src), len(src)}
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)
    editor_handle_keypress(&ed, .I, {})

    editor_handle_keypress(&ed, .LEFT, {.ALT})
    testing.expect_value(t, ed.state.selection[0], len("one café."))
    live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.B}, []rune{'b'}, {.ALT}, false, false)
    testing.expect_value(t, ed.state.selection[0], len("one café"))
    editor_handle_keypress(&ed, .RIGHT, {.ALT})
    testing.expect_value(t, ed.state.selection[0], len("one café."))

    live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.W}, []rune{'w'}, {.CTRL}, false, false)
    testing.expect_value(t, editor_get_text(&ed), "one cafétest")
    editor_handle_keypress(&ed, .W, {.CTRL})
    testing.expect_value(t, editor_get_text(&ed), "one test")
    testing.expect_value(t, ed.state.selection[0], len("one "))
    editor_handle_keypress(&ed, .DELETE, {.ALT})
    testing.expect_value(t, editor_get_text(&ed), "one ")
    editor_handle_keypress(&ed, .ESCAPE, {})
    editor_handle_keypress(&ed, .U, {})
    testing.expect_value(t, editor_get_text(&ed), src)
    testing.expect_value(t, ed.state.selection[0], len(src))
}

@(test)
test_insert_line_shortcuts_and_selected_deletion :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)
    strings.write_string(&ed.sb, "first\none two\nlast")
    ed.mode = .INSERT
    ed.prev_frame_sel = {len("first\none tw"), len("first\none tw")}
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)

    editor_handle_keypress(&ed, .A, {.CTRL})
    testing.expect_value(t, ed.state.selection[0], len("first\n"))
    editor_handle_keypress(&ed, .F, {.ALT})
    testing.expect_value(t, ed.state.selection[0], len("first\none"))
    editor_handle_keypress(&ed, .E, {.CTRL})
    testing.expect_value(t, ed.state.selection[0], len("first\none two"))
    editor_handle_keypress(&ed, .DOWN, {})
    testing.expect_value(t, ed.state.selection[0], len("first\none two\nlast"))
    ed.state.selection = {len("first\none two"), len("first\none ")}
    editor_handle_keypress(&ed, .W, {.CTRL})
    testing.expect_value(t, editor_get_text(&ed), "first\none \nlast")
}

when ODIN_OS == .Darwin {
    @(test)
    test_insert_command_shortcuts_use_line_and_document_boundaries :: proc(t: ^testing.T) {
        ed: Editor
        editor_init(&ed)
        defer editor_destroy(&ed)
        strings.write_string(&ed.sb, "before\nalpha    tail\nafter")
        ed.mode = .INSERT
        caret :: len("before\nalpha    ")
        ed.prev_frame_sel = {caret, caret}
        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)
        line_start :: len("before\n")

        live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.LEFT_SUPER, .BACKSPACE}, nil, {}, true, false)
        testing.expect_value(t, editor_get_text(&ed), "before\ntail\nafter")
        testing.expect_value(t, ed.state.selection, [2]int{line_start, line_start})
        live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.RIGHT}, nil, {}, true, false)
        testing.expect_value(t, ed.state.selection[0], len("before\ntail"))
        live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.LEFT}, nil, {}, true, false)
        testing.expect_value(t, ed.state.selection[0], line_start)

        live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.DELETE, .BACKSPACE}, nil, {}, true, false)
        testing.expect_value(t, editor_get_text(&ed), "before\n\nafter")
        testing.expect_value(t, ed.state.selection[0], line_start)
        live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.UP}, nil, {}, true, false)
        testing.expect_value(t, ed.state.selection[0], 0)
        live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.DOWN}, nil, {}, true, false)
        testing.expect_value(t, ed.state.selection[0], len("before\n\nafter"))
    }
}

@(test)
test_editor_list_enter :: proc(t: ^testing.T) {
    deep_indent :: "                                                                "
    cases := [?]struct {
        before, after: string,
        selection, expected_cursor: int,
        mods: Editor_Key_Mod_State,
    }{
        {"- one", "- one\n- ", 5, 8, {}},
        {" \t* one\nnext", " \t* one\n \t* \nnext", 7, 12, {}},
        {"+\tone", "+\tone\n+ ", 5, 8, {}},
        {"- [ ] open", "- [ ] open\n- [ ] ", 10, 17, {}},
        {"  + [x] done", "  + [x] done\n  + [ ] ", 12, 21, {}},
        {"* [X] done", "* [X] done\n* [ ] ", 10, 17, {}},
        {"- [x]literal", "- [x]literal\n- ", 12, 15, {}},
        {"9. last", "9. last\n10. ", 7, 12, {}},
        {"999999998. item", "999999998. item\n999999999. ", 15, 27, {}},
        {deep_indent + "- item", deep_indent + "- item\n" + deep_indent + "- ", len(deep_indent) + 6, 2 * len(deep_indent) + 9, {}},
        {"\t41) next", "\t41) next\n\t42) ", 9, 15, {}},
        {"- ", "", 2, 0, {}},
        {"- [ ]", "", 5, 0, {}},
        {"- first\n  - [x] \t\nnext", "- first\n\nnext", 17, 8, {}},
        {"  2) \t", "", 6, 0, {}},
        {"999999999. last", "999999999. last\n", 15, 16, {}},
        {"1234567890. text", "1234567890. text\n", 16, 17, {}},
        {"2.no space", "2.no space\n", 10, 11, {}},
        {"-word", "-word\n", 5, 6, {}},
        {"- - -", "- - -\n", 5, 6, {}},
        {"hello", "hello\n", 5, 6, {}},
        {"- one", "- o\nne", 3, 4, {}},
        {"- one", "- one\n", 5, 6, {.SHIFT}},
    }

    for c in cases {
        ed: Editor
        editor_init(&ed)
        defer editor_destroy(&ed)

        strings.write_string(&ed.sb, c.before)
        ed.mode = .INSERT
        ed.prev_frame_sel = {c.selection, c.selection}
        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)

        editor_handle_keypress(&ed, .ENTER, c.mods)
        testing.expect_value(t, editor_get_text(&ed), c.after)
        testing.expect_value(t, ed.state.selection, [2]int{c.expected_cursor, c.expected_cursor})
    }
}

@(test)
test_editor_list_enter_replaces_selection :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)

    strings.write_string(&ed.sb, "- item")
    ed.mode = .INSERT
    ed.prev_frame_sel = {6, 2}
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)

    editor_handle_keypress(&ed, .ENTER, {})
    testing.expect_value(t, editor_get_text(&ed), "- \n")
    testing.expect_value(t, ed.state.selection, [2]int{3, 3})
}

@(test)
test_editor_list_enter_undo_batch :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)

    strings.write_string(&ed.sb, "- first")
    ed.prev_frame_sel = {7, 7}
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)

    editor_handle_keypress(&ed, .I, {})
    editor_handle_keypress(&ed, .ENTER, {})
    editor_handle_charpress(&ed, 'a')
    editor_handle_keypress(&ed, .ENTER, {})
    editor_handle_keypress(&ed, .ENTER, {})
    editor_handle_keypress(&ed, .ESCAPE, {})
    testing.expect_value(t, editor_get_text(&ed), "- first\n- a\n")
    testing.expect_value(t, ed.state.selection, [2]int{12, 12})

    editor_handle_keypress(&ed, .U, {})
    testing.expect_value(t, editor_get_text(&ed), "- first")
    testing.expect_value(t, ed.state.selection, [2]int{7, 7})

    editor_redo(&ed)
    testing.expect_value(t, editor_get_text(&ed), "- first\n- a\n")
    testing.expect_value(t, ed.state.selection, [2]int{12, 12})
}
