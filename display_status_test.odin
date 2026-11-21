package main

import "core:mem"
import "core:testing"
import rl "vendor:raylib"

@(private="file")
STATUS_TEST_GLYPHS := [?]rl.GlyphInfo{
    {value = '?', advanceX = 6},
    {value = ':', advanceX = 4},
    {value = 'i', advanceX = 3},
    {value = 'W', advanceX = 9},
}

@(private="file")
STATUS_TEST_RECS: [len(STATUS_TEST_GLYPHS)]rl.Rectangle

@(private="file")
status_test_font :: proc() -> rl.Font {
    return {
        baseSize = 24,
        glyphCount = len(STATUS_TEST_GLYPHS),
        recs = raw_data(STATUS_TEST_RECS[:]),
        glyphs = raw_data(STATUS_TEST_GLYPHS[:]),
    }
}

@(test)
test_editor_status_updates_in_input_frame :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)
    font := status_test_font()

    testing.expect_value(t, editor_status_layout(&ed, &font, 500).label, "NORMAL")
    editor_handle_keypress(&ed, .I, {})
    // Leaving insert mode clears the trackers but retains their backing array.
    defer delete(ed.undo_trackers)
    testing.expect_value(t, editor_status_layout(&ed, &font, 500).label, "INSERT")
    editor_handle_keypress(&ed, .ESCAPE, {})
    testing.expect_value(t, editor_status_layout(&ed, &font, 500).label, "NORMAL")

    editor_handle_keypress(&ed, .SEMICOLON, {.SHIFT})
    prompt := editor_status_layout(&ed, &font, 500)
    testing.expect_value(t, prompt.label, "COMMAND")
    testing.expect_value(t, prompt.command_tail, "")
    testing.expect_value(t, prompt.caret_x, prompt.prompt_x + 4)

    for ch in "aiW" do editor_handle_charpress(&ed, ch)
    typed := editor_status_layout(&ed, &font, 500)
    testing.expect_value(t, typed.command_tail, "aiW")
    testing.expect_value(t, typed.caret_x, prompt.caret_x + 18)

    editor_handle_keypress(&ed, .BACKSPACE, {})
    shorter := editor_status_layout(&ed, &font, 500)
    testing.expect_value(t, shorter.command_tail, "ai")
    testing.expect_value(t, shorter.caret_x, prompt.caret_x + 9)

    editor_handle_keypress(&ed, .ESCAPE, {})
    canceled := editor_status_layout(&ed, &font, 500)
    testing.expect_value(t, canceled.label, "NORMAL")
    testing.expect_value(t, canceled.command_tail, "")

    editor_handle_keypress(&ed, .SEMICOLON, {.SHIFT})
    reopened := editor_status_layout(&ed, &font, 500)
    testing.expect_value(t, reopened.command_tail, "")
    testing.expect_value(t, reopened.caret_x, prompt.caret_x)
    editor_handle_charpress(&ed, 'q')
    editor_handle_keypress(&ed, .ENTER, {})
    testing.expect_value(t, ed.exit_requested, true)
    testing.expect_value(t, editor_status_layout(&ed, &font, 500).label, "NORMAL")
}

@(private="file")
status_layout_without_allocation :: proc(ed: ^Editor, font: ^rl.Font, width: f32) -> Editor_Status_Layout {
    context.allocator = mem.panic_allocator()
    context.temp_allocator = mem.panic_allocator()
    return editor_status_layout(ed, font, width)
}

@(test)
test_editor_status_keeps_long_command_tail_visible :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)
    font := status_test_font()

    editor_handle_keypress(&ed, .SEMICOLON, {.SHIFT})
    for _ in 0..<4096 do editor_handle_charpress(&ed, 'x')
    for ch in "iW" do editor_handle_charpress(&ed, ch)

    wide := status_layout_without_allocation(&ed, &font, 96)
    testing.expect_value(t, wide.label, "COMMAND")
    testing.expect_value(t, wide.command_tail, "iW")
    testing.expect_value(t, wide.caret_x, wide.command_x + 12)
    testing.expect(t, wide.caret_x + INSERT_CARET_W <= 96 - STATUS_PAD_X)

    editor_handle_charpress(&ed, 'i')
    after_typing := status_layout_without_allocation(&ed, &font, 96)
    testing.expect_value(t, after_typing.command_tail, "iWi")
    testing.expect_value(t, after_typing.caret_x, wide.caret_x + 3)

    narrow := status_layout_without_allocation(&ed, &font, 30)
    testing.expect_value(t, narrow.badge_width, f32(0))
    testing.expect_value(t, narrow.command_tail, "iWi")
    testing.expect_value(t, narrow.command_x, narrow.prompt_x + 4)
    testing.expect(t, narrow.caret_x + INSERT_CARET_W <= 30)

    editor_handle_keypress(&ed, .BACKSPACE, {})
    after_backspace := status_layout_without_allocation(&ed, &font, 96)
    testing.expect_value(t, after_backspace.command_tail, wide.command_tail)
    testing.expect_value(t, after_backspace.caret_x, wide.caret_x)
    testing.expect_value(t, len(ed.command.buf), 4098)
}

@(test)
test_editor_status_keeps_prompt_kerning_when_command_scrolls :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)
    editor_handle_keypress(&ed, .SEMICOLON, {.SHIFT})
    for ch in "WWiW" do editor_handle_charpress(&ed, ch)

    font := status_test_font()
    advances := [?]f32{6, 4.5, 3.25, 9.5}
    metrics := Font_Metrics{advances = advances[:]}
    metrics.pairs = make([dynamic]f32, 0, context.temp_allocator)
    row: [FONT_PAIR_COUNT]f32
    row['i' - FONT_PAIR_FIRST] = -1.25
    font_metrics_append_row(&metrics, ':', row[:])
    row = {}
    row['W' - FONT_PAIR_FIRST] = -1
    font_metrics_append_row(&metrics, 'i', row[:])
    row = {}
    row['i' - FONT_PAIR_FIRST] = -2
    font_metrics_append_row(&metrics, 'W', row[:])

    layout: Editor_Status_Layout
    {
        context.allocator = mem.panic_allocator()
        context.temp_allocator = mem.panic_allocator()
        layout = editor_status_layout(&ed, &font, 25, &metrics)
    }
    testing.expect_value(t, layout.badge_width, f32(0))
    testing.expect_value(t, layout.command_tail, "iW")
    testing.expect_value(t, layout.command_x, f32(12.5))
    testing.expect_value(t, layout.caret_x, f32(23))
    testing.expect_value(t, layout.caret_x, layout.prompt_x + display_text_width(&font, ":iW", &metrics))
}

@(test)
test_command_word_keys_edit_at_caret :: proc(t: ^testing.T) {
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)
    editor_handle_keypress(&ed, .SEMICOLON, {.SHIFT})
    for ch in "WW iW" do editor_handle_charpress(&ed, ch)

    live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.B}, []rune{'b'}, {.ALT}, false, false)
    testing.expect_value(t, ed.command_cursor, len("WW "))
    testing.expect_value(t, string(ed.command.buf[:]), "WW iW")
    live_editor_handle_input(&ed, nil, nil, []rune{'b'}, {.ALT}, false, true)
    testing.expect_value(t, string(ed.command.buf[:]), "WW iW")
    editor_handle_charpress(&ed, 'i')
    testing.expect_value(t, string(ed.command.buf[:]), "WW iiW")
    editor_handle_keypress(&ed, .W, {.CTRL})
    testing.expect_value(t, string(ed.command.buf[:]), "WW iW")

    font := status_test_font()
    layout := status_layout_without_allocation(&ed, &font, 500)
    testing.expect_value(t, layout.command_tail, "WW iW")
    testing.expect_value(t, layout.caret_x, layout.command_x + 24)
    editor_handle_keypress(&ed, .A, {.CTRL})
    layout = status_layout_without_allocation(&ed, &font, 30)
    testing.expect_value(t, layout.command_tail, "WW")
    testing.expect_value(t, layout.caret_x, layout.command_x)
    editor_handle_keypress(&ed, .DELETE, {.ALT})
    testing.expect_value(t, string(ed.command.buf[:]), " iW")
    editor_handle_keypress(&ed, .ESCAPE, {})

    editor_handle_keypress(&ed, .SEMICOLON, {.SHIFT})
    for ch in "xq" do editor_handle_charpress(&ed, ch)
    editor_handle_keypress(&ed, .HOME, {})
    editor_handle_keypress(&ed, .DELETE, {})
    editor_handle_keypress(&ed, .ENTER, {})
    testing.expect_value(t, ed.exit_requested, true)
    testing.expect_value(t, ed.command_cursor, 0)
}

when ODIN_OS == .Darwin {
    @(test)
    test_prompt_command_shortcuts_use_prompt_boundaries :: proc(t: ^testing.T) {
        ed: Editor
        editor_init(&ed)
        defer editor_destroy(&ed)
        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)
        editor_handle_keypress(&ed, .SEMICOLON, {.SHIFT})
        for ch in "before tail" do editor_handle_charpress(&ed, ch)
        editor_handle_keypress(&ed, .LEFT, {.ALT})
        live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.RIGHT_SUPER, .BACKSPACE}, nil, {}, true, false)
        testing.expect_value(t, string(ed.command.buf[:]), "tail")
        testing.expect_value(t, ed.command_cursor, 0)
        live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.DOWN}, nil, {}, true, false)
        testing.expect_value(t, ed.command_cursor, 4)
        live_editor_handle_input(&ed, nil, []rl.KeyboardKey{.UP, .DELETE}, nil, {}, true, false)
        testing.expect_value(t, string(ed.command.buf[:]), "")
        testing.expect_value(t, ed.command_cursor, 0)
    }
}
