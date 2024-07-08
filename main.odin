package main

import rl "vendor:raylib"

WINDOW_TITLE :: "Opal"
WINDOW_INIT_WIDTH :: 800
WINDOW_INIT_HEIGHT :: 450
TARGET_FPS :: 120
SECONDS_TO_FRAMES :: TARGET_FPS

main :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE});

    rl.InitWindow(
        title=WINDOW_TITLE, 
        width=WINDOW_INIT_WIDTH, 
        height=WINDOW_INIT_HEIGHT,
    )
    defer rl.CloseWindow()

    rl.SetExitKey(.KEY_NULL)
    rl.SetTargetFPS(TARGET_FPS)

    theme := theme_make_default()
    defer theme_destroy(&theme)

    ed := Editor{}

    editor_init(&ed)
    defer editor_destroy(&ed)

    kr := Key_Repeat_State{}

    for !rl.WindowShouldClose() {
        key_repeat_begin_frame(&kr)
        defer key_repeat_end_frame(&kr)

        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)

        switch ed.mode {
            case .NORMAL: rl.SetMouseCursor(.DEFAULT)
            case .INSERT: rl.SetMouseCursor(.IBEAM)
        }

        for {
            ch := rl.GetCharPressed()
            if ch == 0 {
                break
            }
            
            editor_handle_charpress(&ed, ch)
        }

        is_ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
        is_shift_pressed := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

        for {
            key := rl.GetKeyPressed()
            if key == .KEY_NULL {
                break
            }

            editor_handle_keypress(&ed, key, is_ctrl_pressed, is_shift_pressed)
        }

        for key in rl.KeyboardKey {
            if key_repeat_should_repeat(&kr, key, 0.4 * SECONDS_TO_FRAMES, 5) {
                editor_handle_keypress(&ed, key, is_ctrl_pressed, is_shift_pressed)
            }
        }

        rl.BeginDrawing()
            rl.ClearBackground(theme.bg_color)

            editor_draw(&ed, &theme)
        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}
