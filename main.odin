package main

import "core:fmt"
import "core:unicode/utf8"
import sdl "vendor:sdl2"
import gl "vendor:OpenGL"
import nvg "vendor:nanovg"
import nvgl "vendor:nanovg/gl"

WINDOW_TITLE :: "Opal"
WINDOW_INIT_WIDTH :: 800
WINDOW_INIT_HEIGHT :: 450
PAGE_MARGIN_TOP :: 40
PAGE_MARGIN_BOTTOM :: 40
PAGE_WIDTH_PCT :: 0.5

main :: proc() {
    if sdl.Init({.VIDEO, .EVENTS}) != 0 {
        panic("Failed to init SDL")
    }
    defer sdl.Quit()

    sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
    sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
    sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GLprofile.CORE))

    window := sdl.CreateWindow(
        WINDOW_TITLE, 
        x=sdl.WINDOWPOS_CENTERED, y=sdl.WINDOWPOS_CENTERED,
        w=WINDOW_INIT_WIDTH, h=WINDOW_INIT_HEIGHT,
        flags={.OPENGL, .RESIZABLE, .INPUT_FOCUS, .ALLOW_HIGHDPI},
    )

    if window == nil { 
        panic(sdl.GetErrorString())
    }

    defer sdl.DestroyWindow(window)

    gl_ctx := sdl.GL_CreateContext(window)
    defer sdl.GL_DeleteContext(gl_ctx)

    // Odin bundles the OpenGL loader, which is nice
    gl.load_up_to(3, 3, sdl.gl_set_proc_address)

    gl.Viewport(0, 0, WINDOW_INIT_WIDTH, WINDOW_INIT_HEIGHT)
    gl.ClearColor(0, 0, 0, 1.0)

    /*
    default_theme_data := theme_data_make_default()
    defer theme_data_destroy(&default_theme_data)

    theme := theme_make(&default_theme_data)
    defer theme_destroy(&theme)
    */

    nvc := nvgl.Create({.ANTI_ALIAS})
    defer nvgl.Destroy(nvc)

    ed := Editor{}

    editor_init(&ed)
    defer editor_destroy(&ed)

    kr := Key_Repeat_State{}

    font_id := nvg.CreateFont(nvc, "inter", "fonts/Inter-Regular.ttf")
    
    main_loop: for !ed.exit_requested {
        key_repeat_begin_frame(&kr, 400)
        defer key_repeat_end_frame(&kr)

        editor_begin_frame(&ed)
        defer editor_end_frame(&ed)

        event: sdl.Event

        for sdl.PollEvent(&event) {
            #partial switch event.type {
                case .QUIT: break main_loop
                case .KEYDOWN:
                    editor_handle_keypress(&ed, event.key.keysym.scancode, {})
                case .TEXTINPUT:
                    str := string(event.text.text[:])
                    for ch in str {
                        editor_handle_charpress(&ed, ch)
                    }
            }
        }

        window_w, window_h: i32
        sdl.GetWindowSize(window, &window_w, &window_h)

        gl.Viewport(0, 0, window_w, window_h)

        nvg.BeginFrame(nvc, f32(window_w), f32(window_h), 1)
        defer nvg.EndFrame(nvc)

        nvg.BeginPath(nvc)
        nvg.FillColor(nvc, nvg.RGB(0x16, 0x16, 0x1d))
        nvg.Fill(nvc)

        nvg.FillColor(nvc, nvg.RGB(0xdc, 0xd7, 0xba))

        nvg.BeginPath(nvc)

        nvg.FontFaceId(nvc, font_id)
        nvg.FontSize(nvc, 24)
        nvg.Text(nvc, 100, 100, "Hello, world!")

        nvg.BeginPath(nvc)
        nvg.Circle(nvc, 200, 200, 50)
        nvg.Fill(nvc)

        /*
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
        rl.EndDrawing()
        */    

        sdl.GL_SwapWindow(window)

        free_all(context.temp_allocator)
    }
}
