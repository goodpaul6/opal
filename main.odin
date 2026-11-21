package main

import "core:os"
import "core:fmt"
import "core:time"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

WINDOW_TITLE :: "Opal"
WINDOW_INIT_WIDTH :: 800
WINDOW_INIT_HEIGHT :: 450
PAGE_MARGIN_TOP :: 40
PAGE_MARGIN_BOTTOM :: 40
PAGE_WIDTH_PCT :: 0.5
OPAL_TRACE_INPUT :: #config(OPAL_TRACE_INPUT, false)

Input_Frame_Trace :: struct {
    caret, page, status: time.Duration,
}

main :: proc() {
    if len(os.args) > 1 && os.args[1] == "--screenshot" {
        os.exit(screenshot_main(os.args[2:]))
    }
    benchmark_startup := len(os.args) > 1 && os.args[1] == "--benchmark-startup"
    launch, window_ready, theme_ready, frame_drawn: time.Tick
    if benchmark_startup do launch = time.tick_now()

    rl.SetConfigFlags({.WINDOW_RESIZABLE, .WINDOW_HIGHDPI})

    rl.InitWindow(
        title=WINDOW_TITLE, 
        width=WINDOW_INIT_WIDTH, 
        height=WINDOW_INIT_HEIGHT,
    )
    defer rl.CloseWindow()
    if benchmark_startup do window_ready = time.tick_now()

    rl.SetExitKey(.KEY_NULL)

    default_theme_data := theme_data_make_default()
    defer theme_data_destroy(&default_theme_data)

    initial_scale := [2]f32{1, 1}
    width, height := rl.GetScreenWidth(), rl.GetScreenHeight()
    pixel_width, pixel_height := rl.GetRenderWidth(), rl.GetRenderHeight()
    if width > 0 && height > 0 && pixel_width > 0 && pixel_height > 0 {
        initial_scale = {f32(pixel_width) / f32(width), f32(pixel_height) / f32(height)}
    }
    theme := theme_make(&default_theme_data, pixel_scale = initial_scale)
    defer theme_destroy(&theme)
    if benchmark_startup do theme_ready = time.tick_now()

    ed := Editor{}

    editor_init(&ed)
    defer editor_destroy(&ed)
    ed.state.set_clipboard = editor_system_clipboard_set
    ed.state.get_clipboard = editor_system_clipboard_get

    kr := Key_Repeat_State{}
    keys := make([dynamic]rl.KeyboardKey, 0, 16)
    defer delete(keys)
    chars := make([dynamic]rune, 0, 16)
    defer delete(chars)
    drawn_size: [4]i32
    redraw_after_wait := false
    cursor := rl.MouseCursor.DEFAULT

    for !rl.WindowShouldClose() && !ed.exit_requested {
        input_tick: time.Tick
        when OPAL_TRACE_INPUT do input_tick = time.tick_now()
        key_repeat_begin_frame(&kr, 400)
        defer key_repeat_end_frame(&kr)

        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)

        key_mods := Editor_Key_Mod_State{}

        if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) do key_mods += {.CTRL}
        if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) do key_mods += {.SHIFT}
        if rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT) do key_mods += {.ALT}

        command_down := false
        when ODIN_OS == .Darwin {
            command_down = rl.IsKeyDown(.LEFT_SUPER) || rl.IsKeyDown(.RIGHT_SUPER)
        }

        clear(&keys)
        has_key_input := false
        for key := rl.GetKeyPressed(); key != .KEY_NULL; key = rl.GetKeyPressed() {
            append(&keys, key)
            has_key_input = has_key_input || !editor_is_modifier_key(key)
        }
        clear(&chars)
        for ch := rl.GetCharPressed(); ch != 0; ch = rl.GetCharPressed() {
            append(&chars, ch)
        }
        shortcut_repeated := false
        if len(chars) > 0 && (.CTRL in key_mods || .ALT in key_mods || command_down) {
            shortcut_keys := [?]rl.KeyboardKey{.EQUAL, .MINUS, .A, .B, .C, .E, .F, .R, .V, .W}
            for key in shortcut_keys {
                if rl.IsKeyPressedRepeat(key) && live_editor_shortcut_suppresses_chars(ed.mode, key, key_mods, command_down) {
                    shortcut_repeated = true
                    break
                }
            }
        }
        live_editor_handle_input(&ed, &theme, keys[:], chars[:], key_mods, command_down, shortcut_repeated)

        repeats := 0
        repeat_key_held := false
        repeat_mods := live_editor_key_mods(key_mods, command_down)
        for key in rl.KeyboardKey {
            if !kr.keys[key].is_pressed || editor_is_modifier_key(key) ||
                live_editor_consumes_key(key, key_mods, command_down) ||
                key == .V || (key == .P && ed.mode != .INSERT && ed.mode != .COMMAND) {
                continue
            }
            repeat_key_held = true
            if key_repeat_should_repeat(&kr, key, 20) {
                editor_handle_keypress(&ed, key, repeat_mods)
                repeats += 1
            }
        }

        next_cursor := rl.MouseCursor.IBEAM if ed.mode == .INSERT else rl.MouseCursor.DEFAULT
        if next_cursor != cursor {
            rl.SetMouseCursor(next_cursor)
            cursor = next_cursor
        }
        frame_size := [4]i32{rl.GetScreenWidth(), rl.GetScreenHeight(), rl.GetRenderWidth(), rl.GetRenderHeight()}
        has_input := has_key_input || len(chars) > 0 || repeats > 0
        wake_needs_redraw := redraw_after_wait && len(keys) == 0
        if !has_input && !wake_needs_redraw && frame_size == drawn_size && !rl.IsWindowResized() {
            free_all(context.temp_allocator)
            // EndDrawing already polls after a swap. With no frame to swap,
            // poll here instead, keeping the GPU idle until there is work.
            if repeat_key_held {
                // The editor's repeat deadline can expire without an OS event.
                rl.WaitTime(0.001)
                rl.PollInputEvents()
            } else {
                rl.EnableEventWaiting()
                rl.PollInputEvents()
                rl.DisableEventWaiting()
                // An expose or restore can require a redraw at the same size.
                redraw_after_wait = true
            }
            continue
        }
        redraw_after_wait = false
        drawn_size = frame_size

        trace: Input_Frame_Trace
        frame_trace: ^Input_Frame_Trace
        input_end, draw_end: time.Tick
        when OPAL_TRACE_INPUT {
            if has_input {
                input_end = time.tick_now()
                frame_trace = &trace
            }
        }
        rl.BeginDrawing()
            draw_editor_frame(
                &ed, &theme,
                frame_size[0], frame_size[1], frame_size[2], frame_size[3],
                frame_trace,
            )
        when OPAL_TRACE_INPUT {
            if frame_trace != nil do draw_end = time.tick_now()
        }
        if benchmark_startup do frame_drawn = time.tick_now()
        rl.EndDrawing()
        if benchmark_startup {
            presented := time.tick_now()
            fmt.printf("startup: window %.3f ms, fonts %.3f ms, first draw %.3f ms, present/poll %.3f ms, total %.3f ms\n",
                time.duration_milliseconds(time.tick_diff(launch, window_ready)),
                time.duration_milliseconds(time.tick_diff(window_ready, theme_ready)),
                time.duration_milliseconds(time.tick_diff(theme_ready, frame_drawn)),
                time.duration_milliseconds(time.tick_diff(frame_drawn, presented)),
                time.duration_milliseconds(time.tick_diff(launch, presented)))
            break
        }
        when OPAL_TRACE_INPUT {
            if frame_trace != nil {
                present := time.tick_since(draw_end)
                draw := time.tick_diff(input_end, draw_end)
                fmt.eprintf(
                    "input keys=%d chars=%d repeats=%d bytes=%d zoom=%d: input %.3f ms, caret %.3f ms, page %.3f ms, status %.3f ms, other draw %.3f ms, present/poll %.3f ms, frame start to present %.3f ms\n",
                    len(keys), len(chars), repeats, len(ed.sb.buf), theme.zoom_level,
                    time.duration_milliseconds(time.tick_diff(input_tick, input_end)),
                    time.duration_milliseconds(trace.caret), time.duration_milliseconds(trace.page),
                    time.duration_milliseconds(trace.status),
                    time.duration_milliseconds(draw - trace.caret - trace.page - trace.status),
                    time.duration_milliseconds(present),
                    time.duration_milliseconds(time.tick_diff(input_tick, draw_end) + present),
                )
            }
        }

        free_all(context.temp_allocator)
    }
}

live_zoom_shortcut_delta :: proc(key: rl.KeyboardKey, mods: Editor_Key_Mod_State, command_down: bool) -> int {
    if .CTRL not_in mods && !(ODIN_OS == .Darwin && command_down) do return 0
    #partial switch key {
        case .EQUAL: return 1
        case .MINUS: return -1
        case: return 0
    }
}

live_editor_consumes_key :: proc(key: rl.KeyboardKey, mods: Editor_Key_Mod_State, command_down: bool) -> bool {
    // Like Ctrl and Shift, the Command modifier itself should not cancel a pending editor action.
    when ODIN_OS == .Darwin {
        if key == .LEFT_SUPER || key == .RIGHT_SUPER do return true
    }
    return live_zoom_shortcut_delta(key, mods, command_down) != 0
}

@(private="file")
live_editor_key_mods :: proc(mods: Editor_Key_Mod_State, command_down: bool) -> Editor_Key_Mod_State {
    when ODIN_OS == .Darwin {
        if command_down do return mods + {.CMD}
    }
    return mods
}

@(private="file")
live_editor_shortcut_suppresses_chars :: proc(
    mode: Editor_Mode, key: rl.KeyboardKey, mods: Editor_Key_Mod_State, command_down: bool,
) -> bool {
    if .CTRL in mods && live_zoom_shortcut_delta(key, mods, command_down) != 0 do return true
    key_mods := live_editor_key_mods(mods, command_down)
    if .CTRL in key_mods || .CMD in key_mods {
        if key == .V && mode != .COMMAND do return true
        if key == .C && mode == .VISUAL do return true
    }
    if mode == .NORMAL do return key == .R && .CTRL in mods
    _, shortcut := editor_text_letter_shortcut(key, mods)
    return shortcut
}

live_editor_handle_input :: proc(
    ed: ^Editor, theme: ^Theme, keys: []rl.KeyboardKey, chars: []rune,
    mods: Editor_Key_Mod_State, command_down, shortcut_repeated: bool,
) {
    // Cocoa GLFW already excludes Super-modified text from raylib's char queue.
    // Raylib does not associate Ctrl/Alt text with a key. Drop the frame's
    // characters when a shortcut could have produced them.
    discard_chars := shortcut_repeated
    for key in keys {
        if live_editor_shortcut_suppresses_chars(ed.mode, key, mods, command_down) {
            discard_chars = true
            break
        }
    }

    // Preserve the editor's char-before-key order (e.g. Normal-mode replace).
    if !discard_chars {
        for ch in chars do editor_handle_charpress(ed, ch)
    }
    key_mods := live_editor_key_mods(mods, command_down)
    for key in keys {
        if delta := live_zoom_shortcut_delta(key, mods, command_down); delta != 0 {
            theme_set_zoom_level(theme, theme.zoom_level + delta)
        } else if !live_editor_consumes_key(key, mods, command_down) {
            editor_handle_keypress(ed, key, key_mods)
        }
    }
}

draw_editor_frame :: proc(ed: ^Editor, theme: ^Theme, width, height, pixel_width, pixel_height: i32, trace: ^Input_Frame_Trace = nil) {
    if width <= 0 || height <= 0 || pixel_width <= 0 || pixel_height <= 0 do return
    render_w := f32(width)
    render_h := f32(height)
    theme_set_pixel_scale(theme, {f32(pixel_width) / render_w, f32(pixel_height) / render_h})

    // Use the same logical projection on both targets. BeginDrawing applies
    // its own platform-specific DPI transform; BeginTextureMode does not.
    rlgl.DrawRenderBatchActive()
    projection := rlgl.GetMatrixProjection()
    modelview := rlgl.GetMatrixModelview()
    defer {
        rlgl.DrawRenderBatchActive()
        rlgl.SetMatrixProjection(projection)
        rlgl.SetMatrixModelview(modelview)
    }
    rlgl.Viewport(0, 0, pixel_width, pixel_height)
    rlgl.MatrixMode(rlgl.PROJECTION)
    rlgl.LoadIdentity()
    rlgl.Ortho(0, f64(width), f64(height), 0, 0, 1)
    rlgl.MatrixMode(rlgl.MODELVIEW)
    rlgl.LoadIdentity()

    page_w := render_w * PAGE_WIDTH_PCT
    margin_side := (render_w - page_w) / 2
    status_h := editor_status_line_height(theme)
    content_h := max(0, render_h - status_h)
    top := min(PAGE_MARGIN_TOP, content_h / 2)
    bottom := max(top, content_h - PAGE_MARGIN_BOTTOM)

    rl.ClearBackground(theme.data.bg_color)
    editor_display_begin(ed, theme, {margin_side, top, page_w, bottom - top})
    editor_display_draw(ed, theme, width, height, trace)
    editor_display_end(ed)
}
