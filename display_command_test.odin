package main

import "core:mem"
import "core:strings"
import "core:testing"
import rl "vendor:raylib"

// Real glyph metrics without a window or texture. Unknown letters use '?'.
@(private="file")
make_display_test_theme :: proc(data: ^Theme_Data) -> Theme {
    @(static) glyphs := [?]rl.GlyphInfo{
        {value = '?', advanceX = 6},
        {value = 'é', advanceX = 7},
        {value = ' '},
    }
    @(static) recs := [?]rl.Rectangle{{width = 5, height = 8}, {width = 6, height = 8}, {width = 3}}
    theme := Theme{data = data, pixel_scale = {1, 1}}
    sizes := theme_font_sizes({18, 17, 15, 14, 13, 11}, 10, 10)
    for variant in Theme_Font_Variant {
        theme.fonts[variant] = rl.Font{
            baseSize = sizes[variant],
            glyphCount = len(glyphs),
            glyphs = raw_data(glyphs[:]),
            recs = raw_data(recs[:]),
        }
    }
    return theme
}

@(private="file")
make_display_test_layout :: proc(
    theme: ^Theme, src: string, caret: int, width: f32, mode: Editor_Mode = .INSERT,
) -> (commands: []Display_Command, rect: rl.Rectangle) {
    ed := Editor{mode = mode}
    ed.sb = strings.builder_make(context.temp_allocator)
    strings.write_string(&ed.sb, src)
    ed.state.selection[0] = caret
    cmds := make([dynamic]Display_Command, context.temp_allocator)
    collect :: proc(data: rawptr, cmd: Display_Command) {
        append(cast(^[dynamic]Display_Command)data, cmd)
    }
    rect = display_command_gen(&ed, theme, {width, 100}, collect, &cmds)
    return cmds[:], rect
}

@(test)
test_display_markdown_preview_uses_headings_without_caret :: proc(t: ^testing.T) {
    data := Theme_Data{fg_color = rl.WHITE, accent_color = rl.GOLD}
    theme := make_display_test_theme(&data)
    preview := "# Idea"
    commands := make([dynamic]Display_Command, context.temp_allocator)
    collect :: proc(data: rawptr, cmd: Display_Command) { append(cast(^[dynamic]Display_Command)data, cmd) }
    caret := display_command_gen(nil, &theme, {200, 100}, collect, &commands, preview = &preview)
    testing.expect_value(t, caret.height, f32(0))
    if !testing.expect(t, len(commands) > 0) do return
    command := commands[len(commands) - 1].sub.(Display_Command_Text)
    testing.expect_value(t, command.text, "Idea")
    testing.expect(t, command.font == &theme.fonts[.H1])
}

@(test)
test_display_em_dash_case_context :: proc(t: ^testing.T) {
    data := Theme_Data{fg_color = rl.WHITE}
    theme := make_display_test_theme(&data)
    src :: "ÉTÉ À VÉLO — déjà vu."
    dash_at :: len("ÉTÉ À VÉLO ")
    commands, _ := make_display_test_layout(&theme, src, dash_at, 400, .NORMAL)
    found := 0
    for cmd in commands {
        if text, ok := cmd.sub.(Display_Command_Text); ok && text.text == "—" {
            found += 1
            testing.expect_value(t, cmd.dash_context.start, dash_at)
            source := cmd.dash_context.source
            if testing.expect_value(t, source, src) {
                testing.expect(t, display_em_dash_in_case_context(source[:dash_at], source[dash_at + len("—"):]))
            }
        }
    }
    testing.expect_value(t, found, 2) // Both the page glyph and the inverted caret glyph.
    testing.expect(t, display_em_dash_in_case_context("abc ", "  ÉTÉ"))
    testing.expect(t, !display_em_dash_in_case_context("abc ", " déjà"))
    testing.expect(t, !display_em_dash_in_case_context("ABC\n ", " déjà"))
    testing.expect(t, !display_em_dash_in_case_context("ABC. ", " déjà"))
    testing.expect(t, !display_em_dash_in_case_context("ABC", "déjà"))
}

@(test)
test_display_caret_newline_and_empty_document :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    cases := [?]struct {
        src: string,
        caret: int,
        rect: rl.Rectangle,
    }{
        {"", 0, {0, 0, 2, 10}},
        {"abc\nxyz", 3, {18, 0, 2, 10}},
        {"abc\nxyz", 4, {0, 10, 2, 10}},
        {"abc\n", 4, {0, 10, 2, 10}},
        {"\n\n", 1, {0, 10, 2, 10}},
        {"\n\n", 2, {0, 20, 2, 10}},
        {"abc   \n", 6, {18, 0, 2, 10}},
        {"abc   \n", 7, {0, 10, 2, 10}},
    }
    for c in cases {
        commands, rect := make_display_test_layout(&theme, c.src, c.caret, 24)
        testing.expect_value(t, rect, c.rect)
        if !testing.expect(t, len(commands) > 0) do continue
        cmd := commands[len(commands) - 1]
        testing.expect_value(t, cmd.pos, [2]f32{c.rect.x, c.rect.y})
        testing.expect_value(t, cmd.sub.(Display_Command_Rect).h, c.rect.height)
    }
}

@(test)
test_display_caret_in_dropped_wrap_whitespace :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    for caret in 3..=6 {
        commands, rect := make_display_test_layout(&theme, "abc   d", caret, 24)
        testing.expect_value(t, rect, rl.Rectangle{0, 10, 2, 10})
        if !testing.expect_value(t, len(commands), 3) do continue
        testing.expect_value(t, commands[0].sub.(Display_Command_Text).text, "abc")
        testing.expect_value(t, commands[1].sub.(Display_Command_Text).text, "d")
        testing.expect_value(t, commands[1].pos, [2]f32{0, 10})
    }
}

@(test)
test_display_wrap_long_utf8_token :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    expected := [?]rl.Rectangle{
        {0, 0, 2, 10}, // Before the first rune.
        {0, 0, 2, 10}, // Within a rune; snap to its start visually.
        {7, 0, 2, 10},
        {7, 0, 2, 10},
        {0, 10, 2, 10}, // First byte on the wrapped line.
        {0, 10, 2, 10},
        {7, 10, 2, 10}, // EOF stays on the last occupied line.
    }
    for want, caret in expected {
        commands, rect := make_display_test_layout(&theme, "ééé", caret, 14)
        testing.expect_value(t, rect, want)
        if !testing.expect_value(t, len(commands), 3) do continue
        testing.expect_value(t, commands[0].sub.(Display_Command_Text).text, "éé")
        testing.expect_value(t, commands[1].sub.(Display_Command_Text).text, "é")
        testing.expect_value(t, commands[1].pos, [2]f32{0, 10})
    }
    commands, rect := make_display_test_layout(&theme, "éé\n", 4, 3)
    if !testing.expect_value(t, len(commands), 3) do return
    testing.expect_value(t, commands[1].pos, [2]f32{0, 10})
    testing.expect_value(t, rect, rl.Rectangle{1, 10, 2, 10})
}

@(test)
test_theme_heading_sizes :: proc(t: ^testing.T) {
    data := theme_data_make_default()
    defer theme_data_destroy(&data)
    body_sizes := [?]i32{20, 23, 27, 32, 38}
    if !testing.expect_value(t, len(data.zoom_level_to_font_sizes), len(body_sizes)) do return
    for sizes, i in data.zoom_level_to_font_sizes {
        testing.expect_value(t, sizes[.BODY], body_sizes[i])
        testing.expect(t, sizes[.PRE] < sizes[.BODY])
        prev := sizes[.H1] + 1
        for variant in THEME_HEADING_VARIANTS {
            testing.expect(t, sizes[variant] < prev)
            prev = sizes[variant]
        }
        testing.expect(t, prev < sizes[.BODY])
    }
    defaults := data.zoom_level_to_font_sizes[0]
    testing.expect_value(t, [6]i32{defaults[.H1], defaults[.H2], defaults[.H3], defaults[.H4], defaults[.H5], defaults[.H6]},
                         [6]i32{33, 27, 24, 22, 20, 19})
    testing.expect_value(t, theme_font_sizes({18, 17, 16, 15, 14, 13}, 12, 14), Theme_Font_Sizes{
        .H1 = 18, .H2 = 17, .H3 = 16, .H4 = 15, .H5 = 14, .H6 = 13, .BODY = 12, .PRE = 14,
        .H1_CODE = 17, .H2_CODE = 16, .H3_CODE = 15, .H4_CODE = 14, .H5_CODE = 13, .H6_CODE = 12,
    })

    for variant in THEME_HEADING_VARIANTS {
        testing.expect(t, raw_data(data.font_data[variant]) == raw_data(data.font_data[.BODY]))
    }
    for variant in THEME_HEADING_CODE_VARIANTS {
        testing.expect(t, raw_data(data.font_data[variant]) == raw_data(data.font_data[.PRE]))
    }
    testing.expect(t, len(data.font_data[.BODY]) > 0 && len(data.font_data[.PRE]) > 0)
    testing.expect(t, raw_data(data.font_data[.PRE]) != raw_data(data.font_data[.BODY]))
}

@(test)
test_display_heading_levels_wrap_with_source_offsets :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    cases := [?]struct {marker: string, variant: Theme_Font_Variant, height: f32}{
        {"#", .H1, 18}, {"##", .H2, 17}, {"###", .H3, 15},
        {"####", .H4, 14}, {"#####", .H5, 13}, {"######", .H6, 11},
    }
    for c in cases {
        src := strings.concatenate({c.marker, " ééééééé\nbody"}, context.temp_allocator)
        caret := len(c.marker) + len(" ééééé") + 1 // Inside the first rune on visual row three.
        commands, rect := make_display_test_layout(&theme, src, caret, 40)
        testing.expect_value(t, rect, rl.Rectangle{0, 2 * c.height, INSERT_CARET_W, c.height})
        if !testing.expect_value(t, len(commands), 6) do continue
        texts := [?]string{c.marker, " ", "ééééé", "éé", "body"}
        rows := [?]f32{0, 0, 1, 2, 3}
        for want, i in texts {
            cmd := commands[i]
            text := cmd.sub.(Display_Command_Text)
            variant := i == len(texts) - 1 ? Theme_Font_Variant.BODY : c.variant
            testing.expect_value(t, text.text, want)
            testing.expect(t, text.font == &theme.fonts[variant])
            testing.expect_value(t, cmd.pos.y, rows[i] * c.height)
            testing.expect_value(t, cmd.dash_context.source, src)
            testing.expect_value(t, cmd.dash_context.start, strings.index(src, want) + (i == 3 ? len("ééééé") : 0))
        }
    }
}

@(test)
test_display_heading_keeps_source_and_resets_style :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    commands, rect := make_display_test_layout(&theme, "# `open\nbody", 8, 100)
    if !testing.expect_value(t, len(commands), 6) do return
    marker := commands[0].sub.(Display_Command_Text)
    testing.expect_value(t, marker.text, "#")
    testing.expect(t, marker.font == &theme.fonts[.H1])
    testing.expect(t, commands[3].sub.(Display_Command_Text).font == &theme.fonts[.H1_CODE])
    testing.expect(t, commands[4].sub.(Display_Command_Text).font == &theme.fonts[.BODY])
    testing.expect_value(t, commands[4].pos, [2]f32{0, 18})
    testing.expect_value(t, rect, rl.Rectangle{0, 18, 2, 10})
}

@(test)
test_display_heading_code_wraps_with_heading_baseline :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    src :: "# `ééé`\nbody"
    caret :: len("# `é")
    commands, insert_rect := make_display_test_layout(&theme, src, caret, 30)
    if !testing.expect_value(t, len(commands), 7) do return
    for i in 2..=4 {
        run := commands[i].sub.(Display_Command_Text)
        testing.expect(t, run.font == &theme.fonts[.H1_CODE])
    }
    testing.expect_value(t, commands[3].pos, [2]f32{0, 19})
    testing.expect_value(t, commands[5].pos, [2]f32{0, 36})
    testing.expect_value(t, insert_rect, rl.Rectangle{7, 18, 2, 18})

    normal_commands, block := make_display_test_layout(&theme, src, caret, 30, .NORMAL)
    if !testing.expect_value(t, len(normal_commands), 8) do return
    testing.expect_value(t, block, rl.Rectangle{7, 19, 7, 17})
    inverted := normal_commands[len(normal_commands) - 1]
    testing.expect_value(t, inverted.pos, [2]f32{7, 19})
    testing.expect(t, inverted.sub.(Display_Command_Text).font == &theme.fonts[.H1_CODE])
}

@(test)
test_display_markdown_blocks_keep_source_and_caret_geometry :: proc(t: ^testing.T) {
    data := Theme_Data{fg_color = rl.WHITE, bg_color = rl.BLACK}
    theme := make_display_test_theme(&data)
    theme.fonts[.PRE].baseSize = 12
    src := " ###### é ##\n>é `x`\n ~~~ lang\n#é\n\n ~~~~\nbody"
    caret := strings.index(src, "#é") + len("#é") - 1 // Inside the fenced rune.
    commands, rect := make_display_test_layout(&theme, src, caret, 100, .NORMAL)
    testing.expect_value(t, rect, rl.Rectangle{6, 35, 7, 12})
    if !testing.expect(t, len(commands) >= 2) do return
    ink := commands[len(commands)-1].sub.(Display_Command_Text)
    testing.expect_value(t, ink, Display_Command_Text{"é", &theme.fonts[.PRE], data.bg_color})

    runs := [?]struct {
        text: string,
        variant: Theme_Font_Variant,
        y: f32,
        quoted: bool,
    }{
        {" ", .H6, 0, false}, {"######", .H6, 0, false}, {" ", .H6, 0, false},
        {"é", .H6, 0, false}, {" ", .H6, 0, false}, {"##", .H6, 0, false},
        {">é", .BODY, 11, true}, {" ", .BODY, 11, true},
        {"`", .PRE, 11, true}, {"x", .PRE, 11, true}, {"`", .PRE, 11, true},
        {" ", .PRE, 23, false}, {"~~~", .PRE, 23, false}, {" ", .PRE, 23, false}, {"lang", .PRE, 23, false},
        {"#é", .PRE, 35, false}, {" ", .PRE, 59, false}, {"~~~~", .PRE, 59, false},
        {"body", .BODY, 71, false},
    }
    if !testing.expect_value(t, len(commands), len(runs) + 2) do return
    quote_color := rl.ColorLerp(data.fg_color, data.bg_color, 0.25)
    for want, i in runs {
        text := commands[i].sub.(Display_Command_Text)
        testing.expect_value(t, text, Display_Command_Text{want.text, &theme.fonts[want.variant], want.quoted ? quote_color : data.fg_color})
        testing.expect_value(t, commands[i].pos.y, want.y)
    }
}

@(test)
test_display_note_theme_keeps_hierarchy_and_block_insets :: proc(t: ^testing.T) {
    data := theme_data_make_default()
    defer theme_data_destroy(&data)
    theme := make_display_test_theme(&data)
    src :: "# Title\n> Quote\n~~~\ncode\n~~~\n"
    commands, _ := make_display_test_layout(&theme, src, len(src), 100)
    rails, code_rows: int
    for cmd in commands {
        switch part in cmd.sub {
            case Display_Command_Rect:
                if part.color == data.code_background {
                    code_rows += 1
                    testing.expect_value(t, part.w, f32(100))
                    testing.expect_value(t, part.h, f32(14))
                } else if part.color == data.accent_color && part.w == 2 && cmd.pos.y == 24 {
                    rails += 1
                }
            case Display_Command_Text:
                switch part.text {
                    case "#", ">", "~~~": testing.expect_value(t, part.color, data.muted_color)
                    case "Title": testing.expect_value(t, part.color, data.heading_color)
                    case "Quote":
                        testing.expect_value(t, part.color, data.fg_color)
                        testing.expect_value(t, cmd.pos, [2]f32{14, 26})
                    case "code":
                        testing.expect_value(t, part.color, data.code_color)
                        testing.expect_value(t, cmd.pos, [2]f32{5, 54})
                }
        }
    }
    testing.expect_value(t, rails, 1)
    testing.expect_value(t, code_rows, 3)
}

@(test)
test_display_visual_line_highlights_wrapped_and_empty_rows :: proc(t: ^testing.T) {
    data := Theme_Data{fg_color = rl.WHITE, bg_color = rl.BLACK, accent_color = rl.GOLD}
    theme := make_display_test_theme(&data)
    commands, _ := make_display_test_layout(&theme, "aaaaaa\n\nlast", len("aaaaaa\n"), 24, .VISUAL)
    highlight := rl.ColorLerp(data.bg_color, data.accent_color, 0.25)
    rows: [dynamic]f32
    defer delete(rows)
    for cmd in commands {
        if rect, ok := cmd.sub.(Display_Command_Rect); ok && rect.color == highlight {
            testing.expect_value(t, rect.w, f32(24))
            append(&rows, cmd.pos.y)
        }
    }
    testing.expect_value(t, len(rows), 3)
    for y, i in rows do testing.expect_value(t, y, 10 * f32(i))
}

@(test)
test_mouse_drag_selects_exact_utf8_and_uses_visual_commands :: proc(t: ^testing.T) {
    data := Theme_Data{fg_color = rl.WHITE, bg_color = rl.BLACK, accent_color = rl.GOLD}
    theme := make_display_test_theme(&data)
    ed: Editor
    editor_init(&ed)
    defer test_clipboard_destroy_editor(&ed)
    clip := strings.builder_make()
    defer strings.builder_destroy(&clip)
    set_test_clipboard(&ed, &clip)
    src :: "aé z\nnext"
    strings.write_string(&ed.sb, src)
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)
    editor_display_begin(&ed, &theme, {10, 20, 100, 100})

    testing.expect(t, editor_mouse_select(&ed, &theme, {14, 22}, true, true, false))
    testing.expect_value(t, ed.mode, Editor_Mode.NORMAL)
    testing.expect_value(t, ed.state.selection[0], 1)
    testing.expect(t, editor_mouse_select(&ed, &theme, {23, 22}, false, false, true))
    testing.expect_value(t, ed.mode, Editor_Mode.VISUAL)
    testing.expect_value(t, editor_visual_range(&ed), [2]int{1, 3})

    commands := make([dynamic]Display_Command, context.temp_allocator)
    collect :: proc(data: rawptr, cmd: Display_Command) { append(cast(^[dynamic]Display_Command)data, cmd) }
    display_command_gen(&ed, &theme, {100, 100}, collect, &commands)
    highlights := 0
    highlight := rl.ColorLerp(data.bg_color, data.accent_color, 0.25)
    for cmd in commands {
        if rect, ok := cmd.sub.(Display_Command_Rect); ok && rect.color == highlight {
            testing.expect_value(t, cmd.pos, [2]f32{6, 0})
            testing.expect_value(t, rect.w, f32(7))
            highlights += 1
        }
    }
    testing.expect_value(t, highlights, 1)
    editor_handle_keypress(&ed, .D, {})
    testing.expect_value(t, editor_get_text(&ed), "a z\nnext")
    testing.expect_value(t, strings.to_string(clip), "é")
    editor_handle_keypress(&ed, .U, {})
    testing.expect_value(t, editor_get_text(&ed), src)

    // A reverse selection including the newline remains characterwise.
    editor_mouse_select(&ed, &theme, {10, 32}, true, true, false)
    editor_mouse_select(&ed, &theme, {27, 22}, false, false, true)
    clear(&commands)
    caret := display_command_gen(&ed, &theme, {100, 100}, collect, &commands)
    testing.expect_value(t, caret, rl.Rectangle{16, 0, 6, 10})
    if glyph, ok := commands[len(commands) - 1].sub.(Display_Command_Text); testing.expect(t, ok) {
        testing.expect_value(t, glyph.text, "z")
        testing.expect_value(t, glyph.color, data.bg_color)
    }
    editor_handle_keypress(&ed, .Y, {})
    testing.expect_value(t, strings.to_string(clip), "z\n")
    editor_handle_keypress(&ed, .P, {.SHIFT})
    testing.expect_value(t, editor_get_text(&ed), "aé z\nz\nnext")
}

@(test)
test_mouse_hit_uses_wrapped_rows_and_scroll_offset :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)
    strings.write_string(&ed.sb, "aaaaaa\n\nlast")
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)
    editor_display_begin(&ed, &theme, {10, 20, 24, 50})
    ed.display.scroll_pos.y = 10
    editor_mouse_select(&ed, &theme, {15, 22}, true, true, false)
    testing.expect_value(t, ed.state.selection[0], 5)
    editor_mouse_select(&ed, &theme, {10, 32}, false, false, true)
    testing.expect_value(t, editor_visual_range(&ed), [2]int{5, 7})
    editor_handle_keypress(&ed, .V, {.SHIFT})
    testing.expect_value(t, ed.visual_characterwise, false)
    testing.expect_value(t, editor_visual_range(&ed), [2]int{0, 8})
}

@(test)
test_canvas_zoom_preserves_wrapping_and_mouse_offsets :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)
    strings.write_string(&ed.sb, "aaaaaa\n\nlast")
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)
    content := rl.Rectangle{10, 20, 24, 50}
    origin := [2]f32{40, 60}
    for zoom in ([?]f32{0.5, 0.77, 1, 2}) {
        editor_display_begin(&ed, &theme, content, zoom, origin)
        testing.expect_value(t, ed.display.layout_size, [2]f32{24, 50})
        ed.display.scroll_pos.y = 10
        editor_mouse_select(&ed, &theme, origin + [2]f32{15, 22} * zoom, true, true, false)
        testing.expect_value(t, ed.state.selection[0], 5)
        editor_mouse_select(&ed, &theme, origin + [2]f32{11, 32} * zoom, false, false, true)
        testing.expect_value(t, editor_visual_range(&ed), [2]int{5, 7})
    }
}

@(test)
test_display_fence_blank_and_eof_carets :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    theme.fonts[.PRE].baseSize = 12
    cases := [?]struct {src: string, offset: int, rect: rl.Rectangle}{
        {"```\n\n```\n", 4, {0, 12, 3, 12}}, // Blank row between delimiters.
        {"```\n", 4, {0, 12, 3, 12}}, // EOF after an unclosed fence.
        {"```\n```\n", 8, {0, 24, 3, 10}}, // EOF after a closed fence.
    }
    for c in cases {
        _, rect := make_display_test_layout(&theme, c.src, c.offset, 100, .NORMAL)
        testing.expect_value(t, rect, c.rect)
    }
}

@(test)
test_display_normal_block_inverts_current_rune :: proc(t: ^testing.T) {
    data := Theme_Data{fg_color = rl.WHITE, bg_color = rl.BLACK}
    theme := make_display_test_theme(&data)
    cases := [?]struct {
        src: string,
        caret: int,
        width: f32,
        rect: rl.Rectangle,
        glyph: string,
        variant: Theme_Font_Variant,
    }{
        {"aéz", 1, 30, {6, 0, 7, 10}, "é", .BODY},
        {"aéz", 2, 30, {6, 0, 7, 10}, "é", .BODY}, // UTF-8 continuation byte.
        {"a😃z", 4, 30, {6, 0, 6, 10}, "😃", .BODY}, // Missing glyph uses fallback metrics.
        {"ééé", 5, 14, {0, 10, 7, 10}, "é", .BODY},
        {"# é", 2, 30, {9, 0, 7, 18}, "é", .H1},
        {"`é`", 2, 30, {6, 0, 7, 10}, "é", .PRE},
    }
    for c in cases {
        commands, rect := make_display_test_layout(&theme, c.src, c.caret, c.width, .NORMAL)
        testing.expect_value(t, rect, c.rect)
        if !testing.expect(t, len(commands) >= 3) do continue
        block, ink := commands[len(commands)-2], commands[len(commands)-1]
        pos := [2]f32{c.rect.x, c.rect.y}
        testing.expect_value(t, block.pos, pos)
        testing.expect_value(t, block.sub.(Display_Command_Rect), Display_Command_Rect{w = c.rect.width, h = c.rect.height, color = data.fg_color})
        testing.expect_value(t, ink.pos, pos)
        testing.expect_value(t, ink.sub.(Display_Command_Text), Display_Command_Text{c.glyph, &theme.fonts[c.variant], data.bg_color})
    }
}

@(test)
test_display_normal_block_clips_native_overhang_without_moving_glyph :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    theme.pixel_scale = {2, 2}
    glyphs := [?]rl.GlyphInfo{{value = 'é', offsetX = -4, offsetY = -2}}
    recs := [?]rl.Rectangle{{width = 24, height = 26}}
    theme.native_fonts[.BODY] = rl.Font{
        texture = {id = 1}, glyphCount = 1,
        glyphs = raw_data(glyphs[:]), recs = raw_data(recs[:]),
    }
    widths := [?]f32{20, 15}
    for width in widths {
        commands, rect := make_display_test_layout(&theme, "aé", 1, width, .NORMAL)
        testing.expect_value(t, rect, rl.Rectangle{4, -1, min(width, 16) - 4, 13})
        if !testing.expect_value(t, len(commands), 3) do continue
        testing.expect_value(t, commands[1].pos, [2]f32{4, -1})
        testing.expect_value(t, commands[2].pos, [2]f32{6, 0})
    }
    commands, rect := make_display_test_layout(&theme, "é", 0, 2, .NORMAL)
    testing.expect_value(t, rect, rl.Rectangle{0, -1, 2, 13})
    if !testing.expect_value(t, len(commands), 3) do return
    testing.expect_value(t, commands[2].pos, [2]f32{0, 0})
}

@(test)
test_display_normal_block_visible_without_ink :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    cases := [?]struct {
        src: string,
        caret: int,
        width: f32,
        rect: rl.Rectangle,
        count: int,
    }{
        {"", 0, 24, {0, 0, 3, 10}, 1},
        {"a b", 1, 24, {6, 0, 3, 10}, 4},
        {"a\tb", 1, 24, {6, 0, 3, 10}, 4},
        {"a     b", 3, 18, {0, 10, 3, 10}, 3}, // Space dropped at the wrap.
        {"abc\n", 3, 18, {15, 0, 3, 10}, 2}, // Right edge.
        {"abc\n", 4, 18, {0, 10, 3, 10}, 2}, // Empty last line.
        {"abc", 3, 18, {15, 0, 3, 10}, 2}, // EOF.
        {"", 0, 1, {0, 0, 1, 10}, 1},
    }
    for c in cases {
        commands, rect := make_display_test_layout(&theme, c.src, c.caret, c.width, .NORMAL)
        testing.expect_value(t, rect, c.rect)
        if !testing.expect_value(t, len(commands), c.count) do continue
        cmd := commands[len(commands)-1]
        testing.expect_value(t, cmd.pos, [2]f32{c.rect.x, c.rect.y})
        testing.expect_value(t, cmd.sub.(Display_Command_Rect), Display_Command_Rect{w = c.rect.width, h = c.rect.height, color = data.fg_color})
    }
}

@(test)
test_display_insert_and_command_caret_stay_thin :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    modes := [?]Editor_Mode{.INSERT, .COMMAND}
    for mode in modes {
        commands, rect := make_display_test_layout(&theme, "aé", 2, 24, mode)
        testing.expect_value(t, rect, rl.Rectangle{6, 0, INSERT_CARET_W, 10})
        if !testing.expect_value(t, len(commands), 2) do continue
        testing.expect_value(t, commands[1].sub.(Display_Command_Rect).w, f32(INSERT_CARET_W))
    }
}

@(test)
test_display_streams_without_allocations :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    advances := [?]f32{6.25, 7.125, 3.5}
    metrics := &theme.font_metrics[.H3]
    metrics.advances = advances[:]
    metrics.pairs = make([dynamic]f32, 0, context.temp_allocator)
    row: [FONT_PAIR_COUNT]f32
    row['a' - FONT_PAIR_FIRST] = -0.5
    font_metrics_append_row(metrics, 'c', row[:])
    ed: Editor
    ed.sb = strings.builder_make()
    defer strings.builder_destroy(&ed.sb)
    block := "> café `code` with an unbroken_long_markdown_token\n~~~lang\n# literal\n~~~~\n### café\n"
    for _ in 0..<256 do strings.write_string(&ed.sb, block)
    ed.mode = .NORMAL
    ed.state.selection[0] = len(ed.sb.buf) - len("é\n")

    tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracker, context.allocator)
    defer mem.tracking_allocator_destroy(&tracker)

    count_cmd :: proc(data: rawptr, cmd: Display_Command) {
        count := cast(^int)data
        count^ += 1
    }
    count: int
    first, second: rl.Rectangle
    {
        context.allocator = mem.tracking_allocator(&tracker)
        context.temp_allocator = context.allocator
        first = display_command_gen(&ed, &theme, {120, 100})
        second = display_command_gen(&ed, &theme, {120, 100}, count_cmd, &count)
    }
    testing.expect(t, count > 256)
    testing.expect_value(t, first, second)
    testing.expect_value(t, tracker.total_allocation_count, 0)
}

@(test)
test_display_checkpoints_survive_edits_and_keep_fence_state :: proc(t: ^testing.T) {
    tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracker, context.allocator)
    defer mem.tracking_allocator_destroy(&tracker)
    context.allocator = mem.tracking_allocator(&tracker)

    data: Theme_Data
    theme := make_display_test_theme(&data)
    theme.fonts[.PRE].baseSize = 14
    ed: Editor
    editor_init(&ed)
    defer editor_destroy(&ed)
    reserve(&ed.sb.buf, 8192)
    strings.write_string(&ed.sb, "~~~\n")
    for _ in 0..<160 do strings.write_string(&ed.sb, "## café inside the fence\n")
    ed.mode = .INSERT
    ed.prev_frame_sel = {len(ed.sb.buf), len(ed.sb.buf)}
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)
    bounds := [2]f32{120, 100}
    first := display_command_gen(&ed, &theme, bounds, viewport_top = 0)
    if !testing.expect_value(t, first.height, f32(14)) do return
    if !testing.expect(t, len(ed.display.checkpoints) > 1) do return

    // A keystroke after an idle gap should reuse both the buffer and layout
    // storage, and should not take a second full-document undo snapshot.
    ed.state.last_edit_time = {}
    allocations := tracker.total_allocation_count
    editor_handle_charpress(&ed, 'a')
    cached := display_command_gen(&ed, &theme, bounds, viewport_top = first.y - 50)
    testing.expect_value(t, tracker.total_allocation_count, allocations)
    testing.expect_value(t, cached, display_command_gen(&ed, &theme, bounds))

    // Compare the visible submissions as well as the caret position.
    Visible :: struct {
        top: f32,
        commands: [dynamic]Display_Command,
    }
    collect_visible :: proc(data: rawptr, cmd: Display_Command) {
        visible := cast(^Visible)data
        if cmd.pos.y >= visible.top do append(&visible.commands, cmd)
    }
    top := cached.y - 50
    from_checkpoint := Visible{top = top}
    defer delete(from_checkpoint.commands)
    from_start := Visible{top = top}
    defer delete(from_start.commands)
    display_command_gen(&ed, &theme, bounds, collect_visible, &from_checkpoint, top + bounds.y, top)
    display_command_gen(&ed, &theme, bounds, collect_visible, &from_start, top + bounds.y)
    if testing.expect_value(t, len(from_checkpoint.commands), len(from_start.commands)) {
        for cmd, i in from_start.commands do testing.expect_value(t, from_checkpoint.commands[i], cmd)
    }

    // Break the opening fence. A stale checkpoint would still render the
    // succeeding lines as code even after the caret revisits the bottom.
    ed.state.selection = {0, 1}
    editor_handle_charpress(&ed, 'x')
    testing.expect_value(t, len(ed.display.checkpoints), 0)
    ed.state.selection = {len(ed.sb.buf), len(ed.sb.buf)}
    cached = display_command_gen(&ed, &theme, bounds, viewport_top = 0)
    testing.expect_value(t, cached, display_command_gen(&ed, &theme, bounds))
    testing.expect_value(t, cached.height, f32(10))
}

@(test)
test_display_fractional_pairs_across_tokens_and_rows :: proc(t: ^testing.T) {
    data: Theme_Data
    theme := make_display_test_theme(&data)
    glyphs := [?]rl.GlyphInfo{{value = '?'}, {value = 'A'}, {value = 'V'}, {value = ' '}, {value = '`'}}
    recs := [?]rl.Rectangle{{}, {width = 5, height = 8}, {width = 6, height = 8}, {}, {}}
    advances := [?]f32{6, 6.5, 7.25, 3.25, 4.5}
    for variant in Theme_Font_Variant {
        theme.fonts[variant].glyphCount = len(glyphs)
        theme.fonts[variant].glyphs = raw_data(glyphs[:])
        theme.fonts[variant].recs = raw_data(recs[:])
        m := &theme.font_metrics[variant]
        m.advances = advances[:]
        m.pairs = make([dynamic]f32, 0, context.temp_allocator)
        row: [FONT_PAIR_COUNT]f32
        row['V' - FONT_PAIR_FIRST] = -1.25
        row[' ' - FONT_PAIR_FIRST] = -0.5
        row['`' - FONT_PAIR_FIRST] = -2
        font_metrics_append_row(m, 'A', row[:])
        row = {}
        row['A' - FONT_PAIR_FIRST] = -0.75
        font_metrics_append_row(m, 'V', row[:])
        row = {}
        row['V' - FONT_PAIR_FIRST] = -0.75
        font_metrics_append_row(m, ' ', row[:])
        row['V' - FONT_PAIR_FIRST] = -1
        font_metrics_append_row(m, '`', row[:])
    }

    // The parser emits separate word/whitespace tokens, but their pair context
    // is still needed to draw them and to stay on the same visual line.
    cmds, rect := make_display_test_layout(&theme, "A V", 2, 16)
    testing.expect_value(t, rect, rl.Rectangle{8.5, 0, INSERT_CARET_W, 10})
    testing.expect_value(t, cmds[1].pos.x, f32(6.5))
    testing.expect_value(t, cmds[1].previous, 'A')
    testing.expect_value(t, cmds[2].pos.x, f32(9.25))
    testing.expect_value(t, cmds[2].previous, ' ')
    pen := Display_Pen{cmds[2].pos.x, cmds[2].previous}
    testing.expect_value(t, display_pen_step(&pen, &theme.fonts[.BODY], &theme.font_metrics[.BODY], 'V'), rect.x)
    testing.expect_value(t, pen.x, f32(15.75))

    cmds, rect = make_display_test_layout(&theme, "A V", 2, 15)
    testing.expect_value(t, rect, rl.Rectangle{0, 10, INSERT_CARET_W, 10})
    testing.expect_value(t, cmds[2].previous, rune(0))
    cmds, rect = make_display_test_layout(&theme, "AVAV", 3, 13, .NORMAL)
    testing.expect_value(t, cmds[0].sub.(Display_Command_Text).text, "AV")
    testing.expect_value(t, cmds[1].sub.(Display_Command_Text).text, "AV")
    testing.expect_value(t, cmds[1].previous, rune(0))
    testing.expect_value(t, rect, rl.Rectangle{5.25, 10, 7.25, 10})
    testing.expect_value(t, cmds[3].pos, [2]f32{5.25, 10}) // Inverted glyph.

    _, rect = make_display_test_layout(&theme, "A\nV", 2, 25)
    testing.expect_value(t, rect, rl.Rectangle{0, 10, INSERT_CARET_W, 10})
    cmds, rect = make_display_test_layout(&theme, "A`A`V", 4, 34)
    testing.expect_value(t, cmds[1].previous, rune(0)) // BODY -> PRE.
    testing.expect_value(t, cmds[3].previous, 'A')     // Still PRE.
    testing.expect_value(t, cmds[4].previous, rune(0)) // PRE -> BODY.
    testing.expect_value(t, rect, rl.Rectangle{20, 0, INSERT_CARET_W, 10})
}
