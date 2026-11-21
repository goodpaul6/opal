package main

import "core:strings"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_editor_word_motions :: proc(t: ^testing.T) {
    // Vim 9.1 defaults, with positions expressed as zero-based UTF-8 byte offsets.
    cases := [?]struct {
        text: string,
        start: int,
        key: rl.KeyboardKey,
        mods: Editor_Key_Mod_State,
        want: []int,
    }{
        {"aa..bb _z9", 9, .B, {}, {7, 4, 2, 0, 0}},
        {"aa..bb _z9", 0, .E, {}, {1, 3, 5, 9, 9}},
        {"aa..bb _z9", 0, .W, {}, {2, 4, 7, 9, 9}},
        {"aa..bb _z9", 5, .B, {.SHIFT}, {0, 0}},
        {"aa..bb _z9", 0, .E, {.SHIFT}, {5, 9, 9}},
        {"aa..bb _z9", 0, .W, {.SHIFT}, {7, 9}},
        {"ab	 \n \n\ncd", 9, .B, {}, {8, 7, 0}},
        {"ab	 \n \n\ncd", 0, .E, {}, {1, 9, 9}},
        {"ab	 \n \n\ncd", 0, .W, {}, {7, 8, 9}},
        {"  foo	bar", 0, .E, {}, {4, 8}},
        {"  foo	bar", 5, .B, {}, {2, 0}},
        {"ab  ", 1, .E, {}, {3, 3}},
        {"ab\n\n", 1, .E, {}, {4, 4}},
        {"", 0, .E, {}, {0}},
        {"", 0, .B, {}, {0}},
        {"éé…🙂🙂中日カナa", 0, .E, {}, {2, 4, 11, 18, 24, 27}},
        {"éé…🙂🙂中日カナa", 27, .B, {}, {21, 15, 7, 4, 0}},
        {"ab\u0301!", 0, .E, {}, {1, 4, 4}},
        // Opal permits insertion carets at EOF and can inherit interior byte columns.
        {"éé", 4, .E, {}, {4}},
        {"éé", 4, .B, {}, {0}},
        {"éé", 1, .E, {}, {2}},
    }

    for c in cases {
        ed: Editor
        editor_init(&ed)
        defer editor_destroy(&ed)
        strings.write_string(&ed.sb, c.text)
        ed.prev_frame_sel = {c.start, c.start}
        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)

        for want in c.want {
            editor_handle_keypress(&ed, c.key, c.mods)
            testing.expect_value(t, ed.state.selection, [2]int{want, want})
        }
        testing.expect_value(t, editor_get_text(&ed), c.text)
        testing.expect_value(t, len(ed.undos), 0)
    }
}

@(test)
test_editor_word_delete_and_undo :: proc(t: ^testing.T) {
    cases := [?]struct {
        text: string,
        start: int,
        key: rl.KeyboardKey,
        mods: Editor_Key_Mod_State,
        after: string,
        caret: int,
    }{
        {"aa..bb _z9", 4, .B, {}, "aabb _z9", 2},
        {"aa..bb _z9", 1, .E, {}, "abb _z9", 1},
        {"aa..bb _z9", 4, .W, {}, "aa.._z9", 4},
        {"aa..bb _z9", 4, .B, {.SHIFT}, "bb _z9", 0},
        {"éé… 🙂", 0, .E, {.SHIFT}, " 🙂", 0},
        {"aa..bb _z9", 0, .W, {.SHIFT}, "_z9", 0},
        {"aé 🙂", 0, .E, {}, " 🙂", 0},
        {"ab\u0301!", 0, .E, {}, "!", 0},
        {"a\n\ncd!", 0, .E, {}, "!", 0},
        {"ab\n  a\ncd  \nrest", 5, .E, {}, "ab\nrest", 3},
        {"ab\n  a\ncd  ", 5, .E, {}, "ab", 2},
        {"ab\n  \n\nfoo", 4, .B, {}, "\nfoo", 0},
        {"ab  \n  cd", 1, .W, {}, "a\n  cd", 1},
        {"\n  cd", 0, .W, {}, "  cd", 0},
        {"  ab\nx", 5, .B, {}, "x", 0},
        {"ab!cd\nx", 6, .B, {}, "ab!\nx", 3},
        {"ab🙂", 2, .E, {}, "ab", 2},
        {"ab🙂", 2, .W, {}, "ab", 2},
        {"ab", 0, .B, {}, "ab", 0},
        {"ab", 2, .E, {}, "ab", 2},
        {"", 0, .E, {}, "", 0},
    }

    for c in cases {
        ed: Editor
        editor_init(&ed)
        defer editor_destroy(&ed)
        defer {
            for item in ed.undos do delete(item.data)
            for item in ed.redos do delete(item.data)
            delete(ed.undos)
            delete(ed.redos)
            delete(ed.undo_trackers)
        }
        strings.write_string(&ed.sb, c.text)
        ed.prev_frame_sel = {c.start, c.start}
        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)

        editor_handle_keypress(&ed, .D, {})
        editor_handle_keypress(&ed, c.key, c.mods)
        testing.expect_value(t, ed.pending_action, Editor_Action.NONE)
        testing.expect_value(t, editor_get_text(&ed), c.after)
        testing.expect_value(t, ed.state.selection, [2]int{c.caret, c.caret})
        if c.text == c.after {
            testing.expect_value(t, len(ed.undos), 0)
            continue
        }

        editor_handle_keypress(&ed, .U, {})
        testing.expect_value(t, editor_get_text(&ed), c.text)
        testing.expect_value(t, ed.state.selection, [2]int{c.start, c.start})
        testing.expect_value(t, len(ed.undos), 0)

        editor_redo(&ed)
        testing.expect_value(t, editor_get_text(&ed), c.after)
        testing.expect_value(t, ed.state.selection, [2]int{c.caret, c.caret})
    }
}
