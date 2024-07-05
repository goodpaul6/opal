package main

import rl "vendor:raylib"
import sa "core:container/small_array"
import "core:fmt"
import "core:math"

WINDOW_TITLE :: "Opal"
WINDOW_INIT_WIDTH :: 800
WINDOW_INIT_HEIGHT :: 450
TARGET_FPS :: 120
SECONDS_TO_FRAMES :: TARGET_FPS

FUJI_WHITE :: rl.Color{0xDC, 0xD7, 0xBA, 0xFF}
SUMI_INK_0 :: rl.Color{0x16, 0x16, 0x1D, 0xFF}

main :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE});

    rl.InitWindow(
        title=WINDOW_TITLE, 
        width=WINDOW_INIT_WIDTH, 
        height=WINDOW_INIT_HEIGHT
    )
    defer rl.CloseWindow()

    rl.SetExitKey(.KEY_NULL)
    rl.SetTargetFPS(TARGET_FPS)

    font := rl.LoadFontEx(
        "fonts/Inter-Regular.ttf", 
        fontSize=24, 
        codepoints=nil, 
        codepointCount=0
    )

    ed := Editor{}
    defer delete_editor(&ed)

    kr := Key_Repeat_State{}

    insert_string(&ed.buf, ed.pos, "Hello, world!")

    for !rl.WindowShouldClose() {
        key_repeat_begin_frame(&kr)
        defer key_repeat_end_frame(&kr)

        switch ed.mode {
            case .NORMAL: rl.SetMouseCursor(.DEFAULT)
            case .INSERT: rl.SetMouseCursor(.IBEAM)
        }

        for {
            ch := rl.GetCharPressed()
            if ch == 0 {
                break
            }
            
            handle_charpress(&ed, ch)
        }

        for {
            key := rl.GetKeyPressed()
            if key == .KEY_NULL {
                break
            }

            handle_keypress(&ed, key)
        }

        for key in rl.KeyboardKey {
            if key_repeat_should_repeat(&kr, key, 0.3 * SECONDS_TO_FRAMES, 4) {
                handle_keypress(&ed, key)
            }
        }

        rl.BeginDrawing()
            rl.ClearBackground(SUMI_INK_0)

            y_pos : f32 = 0.0
            blink := (cast (int) (rl.GetTime() * 1000 / 300)) % 2 == 0

            fmt.println("Line count: ", len(ed.buf.lines))

            for &line, line_row in ed.buf.lines {
                codepoints := sa.slice(&line)

                prev_ch: rune = 0

                if ed.pos.row == line_row && ed.pos.col < len(codepoints) && blink { 
                    prev_ch = codepoints[ed.pos.col]
                    codepoints[ed.pos.col] = '_'
                }

                defer if prev_ch != 0 {
                    codepoints[ed.pos.col] = prev_ch
                }

                rl.DrawTextCodepoints(
                    font=font,
                    codepoints=raw_data(codepoints),
                    codepointCount=cast(i32) len(codepoints),
                    position={20.0, 20.0 + y_pos},
                    fontSize=24,
                    spacing=0,
                    tint=FUJI_WHITE
                )

                y_pos += 22
            }
        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}
