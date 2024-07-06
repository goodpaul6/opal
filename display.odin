package main

import "core:strings"
import sa "core:container/small_array"
import rl "vendor:raylib"

editor_draw :: proc (using ed: ^Editor, font: rl.Font) {
    y_pos : f32 = 0.0
    blink := (cast (int) (rl.GetTime() * 1000 / 300)) % 2 == 0

    text := strings.to_string(sb)

    lines := strings.split_lines(text, context.temp_allocator)

    for line in lines {
        text := strings.clone_to_cstring(line, context.temp_allocator)

        rl.DrawTextEx(
            font=font,
            text=text,
            position={20.0, 20.0 + y_pos},
            fontSize=24,
            spacing=0,
            tint=FUJI_WHITE
        )

        y_pos += 22
    }
}
