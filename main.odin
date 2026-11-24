package main

import "core:os"
import "core:fmt"
import "core:strings"
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
CANVAS_REPEAT_DELAY_MS :: 210
CANVAS_DIRECTION_REPEAT_MS :: 44
CANVAS_ZOOM_REPEAT_MS :: 80

Input_Frame_Trace :: struct {
    caret, page, status: time.Duration,
}

main :: proc() {
    if len(os.args) > 1 && os.args[1] == "--screenshot" {
        os.exit(screenshot_main(os.args[2:]))
    }
    benchmark_startup := len(os.args) > 1 && os.args[1] == "--benchmark-startup"
    path := os.args[1] if len(os.args) > 1 && !benchmark_startup else ""
    canvas_mode := path == "" || strings.equal_fold(os.ext(path), ".canvas")
    launch, window_ready, theme_ready, frame_drawn: time.Tick
    if benchmark_startup do launch = time.tick_now()

    flags := rl.ConfigFlags{.WINDOW_RESIZABLE, .WINDOW_HIGHDPI}
    if canvas_mode do flags += {.MSAA_4X_HINT}
    rl.SetConfigFlags(flags)

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

    ed: Editor
    board: Canvas
    if canvas_mode {
        canvas_init(&board)
        if path != "" do canvas_open(&board, path)
    } else {
        editor_init(&ed, system_clipboard = true)
        if path != "" && path != "--markdown" {
            cmd := Command(Command_Edit{path})
            if !command_run(&cmd, &ed) do fmt.eprintln("Could not open", path)
        }
    }
    defer {
        if canvas_mode {
            if canvas_editor_active(&board) do canvas_finish_editing(&board, &ed)
            canvas_destroy(&board)
        } else {
            editor_destroy(&ed)
        }
    }

    kr := Key_Repeat_State{}
    keys := make([dynamic]rl.KeyboardKey, 0, 16)
    defer delete(keys)
    chars := make([dynamic]rune, 0, 16)
    defer delete(chars)
    drawn_size: [4]i32
    redraw_after_wait := false
    cursor := rl.MouseCursor.DEFAULT

    for !ed.exit_requested && !board.exit_requested {
        closing := rl.WindowShouldClose()
        if closing {
            if !canvas_mode || !canvas_dirty(&board, &ed) do break
            if board.prompt != .CLOSE do canvas_begin_prompt(&board, .CLOSE)
        }
        finished_editing := board.finish_editing
        if finished_editing do canvas_finish_editing(&board, &ed)
        input_tick: time.Tick
        when OPAL_TRACE_INPUT do input_tick = time.tick_now()
        frame_time := rl.GetTime()
        key_repeat_begin_frame(&kr, frame_time)
        defer key_repeat_end_frame(&kr)

        mouse := rl.GetMousePosition()

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
        frame_size := [4]i32{rl.GetScreenWidth(), rl.GetScreenHeight(), rl.GetRenderWidth(), rl.GetRenderHeight()}
        canvas_consumed, canvas_changed := false, false
        if canvas_mode {
            canvas_consumed, canvas_changed = canvas_handle_input(&board, &ed, &theme, keys[:], chars[:],
                live_editor_key_mods(key_mods, command_down), frame_size[0], frame_size[1])
        }
        zoom_wait: f64
        if canvas_mode && !board.expanded && board.zoom_settle_at != 0 {
            zoom_wait = board.zoom_settle_at - rl.GetTime()
            if zoom_wait <= 0 {
                board.zoom_settle_at = 0
                canvas_changed = true
            }
        }
        note_open := !canvas_mode || canvas_editor_active(&board)
        if note_open do editor_begin_frame(&ed)
        defer if note_open do editor_end_frame(&ed)
        if canvas_mode && canvas_editor_active(&board) && !board.expanded {
            canvas_inline_editor_begin(&board, &ed, &theme, {f32(frame_size[0]), f32(frame_size[1])})
        }
        mouse_selection := false
        if !canvas_consumed {
            mouse_selection = editor_mouse_select(&ed, &theme, mouse, rl.IsMouseButtonPressed(.LEFT),
                                                 rl.IsMouseButtonDown(.LEFT), rl.IsMouseButtonReleased(.LEFT))
        }
        shortcut_repeated := false
        if !canvas_consumed && len(chars) > 0 && (.CTRL in key_mods || .ALT in key_mods || command_down) {
            shortcut_keys := [?]rl.KeyboardKey{.EQUAL, .MINUS, .A, .B, .C, .E, .F, .R, .V, .W}
            for key in shortcut_keys {
                if rl.IsKeyPressedRepeat(key) && live_editor_shortcut_suppresses_chars(ed.mode, key, key_mods, command_down) {
                    shortcut_repeated = true
                    break
                }
            }
        }
        if !canvas_consumed {
            live_editor_handle_input(&ed, &theme, keys[:], chars[:], key_mods, command_down, shortcut_repeated)
        }

        repeats := 0
        repeat_key_held := false
        repeat_mods := live_editor_key_mods(key_mods, command_down)
        canvas_screen := [2]f32{f32(frame_size[0]), f32(frame_size[1])}
        for key in rl.KeyboardKey {
            if !kr.keys[key].is_pressed || editor_is_modifier_key(key) do continue
            if canvas_mode {
                if delta := canvas_zoom_key_delta(&board, key, repeat_mods); delta != 0 {
                    if (delta > 0 && board.zoom >= CANVAS_MAX_ZOOM) ||
                       (delta < 0 && board.zoom <= CANVAS_MIN_ZOOM) {
                        continue
                    }
                    repeat_key_held = true
                    if key_repeat_should_repeat(&kr, key, frame_time, CANVAS_REPEAT_DELAY_MS, CANVAS_ZOOM_REPEAT_MS) &&
                       canvas_zoom_at(&board, canvas_view_center(canvas_screen), f32(delta), frame_time) {
                        repeats += 1
                    }
                    continue
                }
            }
            if canvas_consumed {
                if canvas_mode && !canvas_editor_active(&board) && board.prompt == .NONE && board.drag == .NONE &&
                   board.key_mode != .G_PREFIX && repeat_mods - {.SHIFT} == {} &&
                   !(board.key_mode == .CONNECT && .SHIFT in repeat_mods) &&
                   canvas_key_direction(key, board.key_mode, repeat_mods) != {} {
                    repeat_key_held = true
                    if key_repeat_should_repeat(&kr, key, frame_time, CANVAS_REPEAT_DELAY_MS, CANVAS_DIRECTION_REPEAT_MS) {
                        canvas_keyboard_key(&board, &ed, key, repeat_mods, canvas_screen)
                        repeats += 1
                    }
                }
                continue
            }
            if live_editor_consumes_key(key, key_mods, command_down) ||
                key == .V || ((key == .P || key == .C) && ed.mode != .INSERT && ed.mode != .COMMAND) {
                continue
            }
            repeat_key_held = true
            if key_repeat_should_repeat(&kr, key, frame_time, 400, 20) {
                editor_handle_keypress(&ed, key, repeat_mods)
                repeats += 1
            }
        }

        over_note := note_open && board.prompt == .NONE && rl.CheckCollisionPointRec(mouse, ed.display.bounds)
        note_insert := !canvas_mode && ed.mode == .INSERT
        next_cursor := rl.MouseCursor.IBEAM if over_note || note_insert else rl.MouseCursor.DEFAULT
        if next_cursor != cursor {
            rl.SetMouseCursor(next_cursor)
            cursor = next_cursor
        }
        has_input := has_key_input || len(chars) > 0 || repeats > 0 || mouse_selection ||
                     canvas_changed || finished_editing || closing
        wake_needs_redraw := redraw_after_wait && len(keys) == 0
        if !has_input && !wake_needs_redraw && frame_size == drawn_size && !rl.IsWindowResized() {
            free_all(context.temp_allocator)
            // EndDrawing already polls after a swap. With no frame to swap,
            // poll here instead, keeping the GPU idle until there is work.
            if repeat_key_held {
                // The editor's repeat deadline can expire without an OS event.
                rl.WaitTime(0.001)
                rl.PollInputEvents()
            } else if zoom_wait > 0 {
                rl.WaitTime(min(zoom_wait, 0.008))
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
                &board if canvas_mode else nil,
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

draw_editor_frame :: proc(
    ed: ^Editor, theme: ^Theme, width, height, pixel_width, pixel_height: i32,
    trace: ^Input_Frame_Trace = nil, board: ^Canvas = nil,
) {
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

    rl.ClearBackground(theme.data.bg_color)
    if board != nil && !board.expanded {
        canvas_draw_board(board, ed, theme, width, height, trace)
        canvas_draw_toolbar(board, ed, theme, width, height)
        return
    }
    bar := f32(CANVAS_BAR) if board != nil else 0
    page_w := render_w * PAGE_WIDTH_PCT
    margin_side := (render_w - page_w) / 2
    status_h := editor_status_line_height(theme)
    content_h := max(0, render_h - status_h)
    top := bar + min(PAGE_MARGIN_TOP, max(0, content_h - bar) / 2)
    bottom := max(top, content_h - PAGE_MARGIN_BOTTOM)

    editor_display_begin(ed, theme, {margin_side, top, page_w, bottom - top})
    editor_display_draw(ed, theme, width, height, trace)
    editor_display_end(ed)
    if board != nil do canvas_draw_toolbar(board, ed, theme, width, height)
}
