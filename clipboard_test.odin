package main

import "core:strings"
import "core:testing"
import rl "vendor:raylib"

@(private="file")
set_test_clipboard :: proc(ed: ^Editor, clip: ^strings.Builder) {
    ed.state.clipboard_user_data = clip
    ed.state.set_clipboard = proc(data: rawptr, text: string) -> bool {
        builder := cast(^strings.Builder)data
        strings.builder_reset(builder)
        _, err := strings.write_string(builder, text)
        return err == nil
    }
    ed.state.get_clipboard = proc(data: rawptr) -> (string, bool) {
        return strings.to_string((cast(^strings.Builder)data)^), true
    }
}

@(private="file")
test_clipboard_destroy_editor :: proc(ed: ^Editor) {
    for item in ed.undos do delete(item.data)
    for item in ed.redos do delete(item.data)
    for tracker in ed.undo_trackers do delete(tracker.orig_data)
    delete(ed.undos)
    delete(ed.redos)
    delete(ed.undo_trackers)
    editor_destroy(ed)
}

@(test)
test_visual_line_yank_and_linewise_put :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer test_clipboard_destroy_editor(&ed)
    clip := strings.builder_make()
    defer strings.builder_destroy(&clip)
    set_test_clipboard(&ed, &clip)
    src :: "one\ncafé\nthree"
    strings.write_string(&ed.sb, src)
    caret :: len("one\ncafé\nth")
    ed.prev_frame_sel = {caret, caret}
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)

    editor_handle_keypress(&ed, .V, {.SHIFT})
    editor_handle_keypress(&ed, .K, {})
    testing.expect_value(t, ed.mode, Editor_Mode.VISUAL)
    testing.expect_value(t, editor_visual_lines(&ed), [2]int{len("one\n"), len("one\ncafé\n")})
    editor_handle_keypress(&ed, .Y, {})
    testing.expect_value(t, ed.mode, Editor_Mode.NORMAL)
    testing.expect_value(t, strings.to_string(clip), "café\nthree\n")
    testing.expect_value(t, editor_get_text(&ed), src)
    testing.expect_value(t, len(ed.undos), 0)

    editor_handle_keypress(&ed, .P, {.SHIFT})
    testing.expect_value(t, editor_get_text(&ed), "one\ncafé\nthree\ncafé\nthree")
    editor_handle_keypress(&ed, .U, {})
    testing.expect_value(t, editor_get_text(&ed), src)

    editor_handle_keypress(&ed, .G, {.SHIFT})
    editor_handle_keypress(&ed, .P, {})
    testing.expect_value(t, editor_get_text(&ed), "one\ncafé\nthree\ncafé\nthree\n")
    testing.expect_value(t, ed.state.selection[0], len(src) + 1)
    editor_handle_keypress(&ed, .U, {})
    testing.expect_value(t, editor_get_text(&ed), src)
    editor_handle_keypress(&ed, .R, {.CTRL})
    testing.expect_value(t, editor_get_text(&ed), "one\ncafé\nthree\ncafé\nthree\n")
}

@(test)
test_clipboard_shortcuts_replace_visual_lines_and_paste_in_insert :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer test_clipboard_destroy_editor(&ed)
    clip := strings.builder_make()
    defer strings.builder_destroy(&clip)
    set_test_clipboard(&ed, &clip)
    strings.write_string(&ed.sb, "one\ntwo\n")
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)
    editor_handle_keypress(&ed, .V, {.SHIFT})
    live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.C}, []rune{'c'}, {.CTRL}, false, false)
    testing.expect_value(t, strings.to_string(clip), "one\n")

    editor_handle_keypress(&ed, .V, {.SHIFT})
    strings.builder_reset(&clip)
    strings.write_string(&clip, "café")
    editor_handle_keypress(&ed, .P, {})
    testing.expect_value(t, editor_get_text(&ed), "café\ntwo\n")
    testing.expect_value(t, ed.mode, Editor_Mode.NORMAL)
    editor_handle_keypress(&ed, .U, {})
    testing.expect_value(t, editor_get_text(&ed), "one\ntwo\n")

    strings.builder_reset(&clip)
    strings.write_string(&clip, "a\r\nb")
    editor_handle_keypress(&ed, .I, {})
    live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.V}, []rune{'v'}, {.CTRL}, false, false)
    testing.expect_value(t, editor_get_text(&ed), "a\nbone\ntwo\n")
    editor_handle_keypress(&ed, .ESCAPE, {})
    editor_handle_keypress(&ed, .U, {})
    testing.expect_value(t, editor_get_text(&ed), "one\ntwo\n")
}

@(test)
test_visual_d_cuts_whole_lines_and_can_be_undone :: proc(t: ^testing.T) {
    cases := [?]struct {
        before, after, copied: string,
        start, moves, caret: int,
    }{
        {"one\ntwo\nthree\nfour\n", "one\nfour\n", "two\nthree\n", 5, 1, 4},
        {"one\ntwo", "one", "two\n", 5, 0, 0},
        {"one\ntwo\n", "one\n", "two\n", 5, 0, 0},
        {"one\n", "one", "\n", 4, 0, 0},
        {"one\ntwo\n", "", "one\ntwo\n", 0, 1, 0},
    }
    for c in cases {
        ed: Editor
        editor_init(&ed)
        defer test_clipboard_destroy_editor(&ed)
        clip := strings.builder_make()
        defer strings.builder_destroy(&clip)
        set_test_clipboard(&ed, &clip)
        strings.write_string(&ed.sb, c.before)
        ed.prev_frame_sel = {c.start, c.start}
        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)

        editor_handle_keypress(&ed, .V, {.SHIFT})
        for _ in 0..<c.moves do editor_handle_keypress(&ed, .J, {})
        editor_handle_keypress(&ed, .D, {})
        testing.expect_value(t, ed.mode, Editor_Mode.NORMAL)
        testing.expect_value(t, editor_get_text(&ed), c.after)
        testing.expect_value(t, strings.to_string(clip), c.copied)
        testing.expect_value(t, ed.state.selection, [2]int{c.caret, c.caret})
        editor_handle_keypress(&ed, .U, {})
        testing.expect_value(t, editor_get_text(&ed), c.before)
        editor_handle_keypress(&ed, .R, {.CTRL})
        testing.expect_value(t, editor_get_text(&ed), c.after)
    }
}
