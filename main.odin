package main

import rl "vendor:raylib"

WINDOW_TITLE :: "Opal"
WINDOW_INIT_WIDTH :: 800
WINDOW_INIT_HEIGHT :: 450
PAGE_MARGIN_TOP :: 40
PAGE_MARGIN_BOTTOM :: 40
PAGE_WIDTH_PCT :: 0.5

main :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE})

    rl.InitWindow(
        title=WINDOW_TITLE, 
        width=WINDOW_INIT_WIDTH, 
        height=WINDOW_INIT_HEIGHT,
    )
    defer rl.CloseWindow()

    rl.SetExitKey(.KEY_NULL)

    default_theme_data := theme_data_make_default()
    defer theme_data_destroy(&default_theme_data)

    theme := theme_make(&default_theme_data)
    defer theme_destroy(&theme)

    ed := Editor{}

    editor_init(&ed)
    defer editor_destroy(&ed)

    kr := Key_Repeat_State{}

    for !rl.WindowShouldClose() && !ed.exit_requested {
        key_repeat_begin_frame(&kr, 400)
        defer key_repeat_end_frame(&kr)

        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)

        switch ed.mode {
            case .NORMAL, .COMMAND: rl.SetMouseCursor(.DEFAULT)
            case .INSERT: rl.SetMouseCursor(.IBEAM)
        }

        for {
            ch := rl.GetCharPressed()
            if ch == 0 {
                break
            }
            
            editor_handle_charpress(&ed, ch)
        }

        key_mods := Editor_Key_Mod_State{}

        if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) do key_mods += {.CTRL}
        if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) do key_mods += {.SHIFT}

        for {
            key := rl.GetKeyPressed()
            if key == .KEY_NULL {
                break
            }

            if key == .EQUAL && .CTRL in key_mods {
                theme_set_zoom_level(&theme, theme.zoom_level + 1)
                continue
            }

            if key == .MINUS && .CTRL in key_mods {
                theme_set_zoom_level(&theme, theme.zoom_level - 1)
                continue
            }

            editor_handle_keypress(&ed, key, key_mods)
        }

        for key in rl.KeyboardKey {
            if key_repeat_should_repeat(&kr, key, 20) {
                editor_handle_keypress(&ed, key, key_mods)
            }
        }

        render_w := f32(rl.GetRenderWidth())
        render_h := f32(rl.GetRenderHeight())

        page_w := render_w * PAGE_WIDTH_PCT
        margin_side := render_w * ((1 - PAGE_WIDTH_PCT) / 2)

        rl.BeginDrawing()
            rl.ClearBackground(theme.data.bg_color)

            editor_display_begin(&ed, &theme, {
                margin_side,
                PAGE_MARGIN_TOP,
                page_w,
                render_h - editor_status_line_height(&theme) - PAGE_MARGIN_BOTTOM,
            })

            editor_display_draw(&ed, &theme)

            editor_display_end(&ed)

            rl.DrawRectangleRec(ed.display.prev_caret_rect, rl.RED)
        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}
