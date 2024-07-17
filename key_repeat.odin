package main

import "core:fmt"
import rl "vendor:raylib"

Key_Repeat_State_Key :: struct {
    is_pressed: bool,
    was_pressed: bool,
    repeat_time: f64,
}

Key_Repeat_State :: struct {
    keys: #sparse [rl.KeyboardKey]Key_Repeat_State_Key,
}

key_repeat_begin_frame :: proc(using state: ^Key_Repeat_State, repeat_delay_for_ms: int) {
    for &key, ord in keys {
        key.is_pressed = rl.IsKeyDown(cast (rl.KeyboardKey) ord)
        
        if key.is_pressed && !key.was_pressed {
            key.repeat_time = rl.GetTime() + f64(repeat_delay_for_ms) / 1000
        }
    }
}

key_repeat_should_repeat :: proc(
    using state: ^Key_Repeat_State, 
    kkey: rl.KeyboardKey, 
    repeat_every_ms: int,
) -> bool {
    key := &keys[kkey]

    if !key.is_pressed {
        return false
    }

    if rl.GetTime() < key.repeat_time {
        return false
    }

    key.repeat_time += f64(repeat_every_ms) / 1000
    return true
}

key_repeat_end_frame :: proc(using state: ^Key_Repeat_State) {
    for &key in keys {
        key.was_pressed = key.is_pressed
    }
}
