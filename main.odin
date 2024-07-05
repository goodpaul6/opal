package main

import rl "vendor:raylib"

WINDOW_TITLE :: "Opal"
WINDOW_INIT_WIDTH :: 800
WINDOW_INIT_HEIGHT :: 450

main :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT});

    rl.InitWindow(
        title=WINDOW_TITLE, 
        width=WINDOW_INIT_WIDTH, 
        height=WINDOW_INIT_HEIGHT
    )
    defer rl.CloseWindow()

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
            rl.ClearBackground(rl.BLACK)
        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}
