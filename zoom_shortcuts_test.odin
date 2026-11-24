package main

import "core:strings"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_live_zoom_shortcut_delta :: proc(t: ^testing.T) {
    keys := [?]rl.KeyboardKey{.EQUAL, .MINUS}
    for key, i in keys {
        want := 1 - 2 * i
        testing.expect_value(t, live_zoom_shortcut_delta(key, {}, false), 0)
        testing.expect_value(t, live_zoom_shortcut_delta(key, {.SHIFT}, false), 0)
        testing.expect_value(t, live_zoom_shortcut_delta(key, {.CTRL}, false), want)
        testing.expect_value(t, live_zoom_shortcut_delta(key, {.CTRL, .SHIFT}, false), want)
        command_want := want if ODIN_OS == .Darwin else 0
        testing.expect_value(t, live_zoom_shortcut_delta(key, {}, true), command_want)
        testing.expect_value(t, live_zoom_shortcut_delta(key, {.SHIFT}, true), command_want)
    }
    testing.expect_value(t, live_zoom_shortcut_delta(.ZERO, {.CTRL}, true), 0)
    testing.expect_value(t, live_editor_consumes_key(.W, {}, true), false)
    testing.expect_value(t, live_editor_consumes_key(.LEFT_SUPER, {}, true), ODIN_OS == .Darwin)
    testing.expect_value(t, live_editor_consumes_key(.RIGHT_SUPER, {}, true), ODIN_OS == .Darwin)
}

@(test)
test_live_zoom_preserves_document_and_prompt :: proc(t: ^testing.T) {
    // A one-level theme lets us exercise dispatch and bounds without a GL context.
    sizes := [1]Theme_Font_Sizes{}
    data := Theme_Data{zoom_level_to_font_sizes = sizes[:]}
    theme := Theme{data = &data}

    modes := [?]Editor_Mode{.INSERT, .COMMAND}
    for mode in modes {
        ed := Editor{}
        editor_init(&ed)
        defer editor_destroy(&ed)
        ed.mode = mode
        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)
        live_editor_handle_input(&ed, &theme, []rl.KeyboardKey{.EQUAL}, []rune{'+'}, {.CTRL, .SHIFT}, false, false)
        live_editor_handle_input(&ed, &theme, []rl.KeyboardKey{.MINUS}, []rune{'-'}, {.CTRL}, false, false)
        live_editor_handle_input(&ed, &theme, nil, []rune{'-'}, {.CTRL}, false, true)
        when ODIN_OS == .Darwin {
            live_editor_handle_input(&ed, &theme, []rl.KeyboardKey{.LEFT_SUPER, .EQUAL}, nil, {.SHIFT}, true, false)
            live_editor_handle_input(&ed, &theme, []rl.KeyboardKey{.RIGHT_SUPER, .MINUS}, nil, {}, true, false)
        }
        testing.expect_value(t, editor_get_text(&ed), "")
        testing.expect_value(t, strings.to_string(ed.command), "")

        live_editor_handle_input(&ed, &theme, []rl.KeyboardKey{.EQUAL, .MINUS}, []rune{'=', '-'}, {}, false, false)
        testing.expect_value(t, editor_get_text(&ed), "=-" if mode == .INSERT else "")
        testing.expect_value(t, strings.to_string(ed.command), "=-" if mode == .COMMAND else "")
    }
}

@(test)
test_live_zoom_preserves_pending_replace :: proc(t: ^testing.T) {
    ed := Editor{}
    editor_init(&ed)
    defer editor_destroy(&ed)
    strings.write_string(&ed.sb, "a")
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)

    sizes := [1]Theme_Font_Sizes{}
    data := Theme_Data{zoom_level_to_font_sizes = sizes[:]}
    theme := Theme{data = &data}

    editor_handle_keypress(&ed, .R, {})
    when ODIN_OS == .Darwin {
        // The Cocoa char queue has no text for these Command-modified keys.
        live_editor_handle_input(&ed, &theme, []rl.KeyboardKey{.LEFT_SUPER, .EQUAL}, nil, {.SHIFT}, true, false)
        live_editor_handle_input(&ed, &theme, []rl.KeyboardKey{.RIGHT_SUPER, .MINUS}, nil, {}, true, false)
    }
    live_editor_handle_input(&ed, &theme, []rl.KeyboardKey{.EQUAL}, []rune{'='}, {.CTRL}, false, false)
    testing.expect_value(t, editor_get_text(&ed), "a")
    testing.expect_value(t, ed.pending_action, Editor_Action.REPLACE)

    live_editor_handle_input(&ed, &theme, []rl.KeyboardKey{.MINUS}, []rune{'-'}, {}, false, false)
    testing.expect_value(t, editor_get_text(&ed), "-")
    testing.expect_value(t, ed.pending_action, Editor_Action.NONE)
}
