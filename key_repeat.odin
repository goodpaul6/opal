package main

import rl "vendor:raylib"

Key_Repeat_State_Key :: struct {
    is_pressed: bool,
    was_pressed: bool,
    pressed_for_frame_count: int,
}

Key_Repeat_State :: struct {
    keys: #sparse [rl.KeyboardKey]Key_Repeat_State_Key
}

key_repeat_begin_frame :: proc(using state: ^Key_Repeat_State) {
    for &key, ord in keys {
        key.is_pressed = rl.IsKeyDown(cast (rl.KeyboardKey) ord)
    }
}

key_repeat_should_repeat :: proc(using state: ^Key_Repeat_State, kkey: rl.KeyboardKey, delay_for_frames: int, repeat_every_frames: int) -> bool {
    key := keys[kkey]

    return key.pressed_for_frame_count > delay_for_frames && 
           key.pressed_for_frame_count % repeat_every_frames == 0
}

key_repeat_end_frame :: proc(using state: ^Key_Repeat_State) {
    for &key in keys {
        if key.is_pressed {
            key.pressed_for_frame_count += 1
        } else {
            key.pressed_for_frame_count = 0
        }

        key.was_pressed = key.is_pressed
    }
}
