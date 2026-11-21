package main

import "core:fmt"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

// Quarter steps keep capture dimensions deterministic and bound GPU memory use.
screenshot_density_quarters :: proc(value: string) -> i32 {
    switch value {
        case "1": return 4
        case "1.25": return 5
        case "1.5": return 6
        case "1.75": return 7
        case "2": return 8
        case "2.25": return 9
        case "2.5": return 10
        case "2.75": return 11
        case "3": return 12
    }
    return 0
}

screenshot_pixel_size :: proc(density_quarters: i32) -> [2]i32 {
    return ([2]i32{WINDOW_INIT_WIDTH, WINDOW_INIT_HEIGHT} * density_quarters + 2) / 4
}

screenshot_main :: proc(args: []string) -> int {
    if len(args) < 2 || !strings.has_suffix(args[1], ".png") do return screenshot_usage()
    density_quarters: i32 = 4
    command: string
    show_command := false
    for i := 2; i < len(args); i += 2 {
        if i + 1 == len(args) do return screenshot_usage()
        switch args[i] {
            case "--density":
                density_quarters = screenshot_density_quarters(args[i + 1])
                if density_quarters == 0 do return screenshot_usage()
            case "--command":
                show_command = true
                command = args[i + 1]
            case: return screenshot_usage()
        }
    }

    src, err := os.read_entire_file(args[0], context.allocator)
    if err != nil {
        fmt.eprintf("Could not read %q\n", args[0])
        return 1
    }
    defer delete(src)

    rl.SetConfigFlags({.WINDOW_HIDDEN})
    rl.InitWindow(WINDOW_INIT_WIDTH, WINDOW_INIT_HEIGHT, WINDOW_TITLE)
    if !rl.IsWindowReady() {
        fmt.eprintln("Could not initialize raylib for screenshot capture")
        return 1
    }
    defer rl.CloseWindow()

    data := theme_data_make_default()
    defer theme_data_destroy(&data)
    scale := f32(density_quarters) / 4
    theme := theme_make(&data, pixel_scale = {scale, scale})
    defer theme_destroy(&theme)

    ed := Editor{}
    editor_init(&ed)
    defer editor_destroy(&ed)
    strings.write_string(&ed.sb, string(src))
    editor_begin_frame(&ed)
    defer editor_end_frame(&ed)
    if show_command {
        editor_handle_keypress(&ed, .SEMICOLON, {.SHIFT})
        for ch in command do editor_handle_charpress(&ed, ch)
    }

    pixels := screenshot_pixel_size(density_quarters)
    target := rl.LoadRenderTexture(pixels.x, pixels.y)
    if !rl.IsRenderTextureValid(target) {
        fmt.eprintln("Could not allocate screenshot render target")
        return 1
    }
    defer rl.UnloadRenderTexture(target)

    rl.BeginTextureMode(target)
    draw_editor_frame(
        &ed, &theme, WINDOW_INIT_WIDTH, WINDOW_INIT_HEIGHT,
        target.texture.width, target.texture.height,
    )
    rl.EndTextureMode()

    image := rl.LoadImageFromTexture(target.texture)
    if !rl.IsImageValid(image) {
        fmt.eprintln("Could not read screenshot pixels")
        return 1
    }
    defer rl.UnloadImage(image)
    rl.ImageFlipVertical(&image)
    // RGB is already composited onto the editor background. Discard the
    // blend pass's alpha so image viewers display those same edge colors.
    rl.ImageFormat(&image, .UNCOMPRESSED_R8G8B8)
    if !rl.ExportImage(image, strings.clone_to_cstring(args[1], context.temp_allocator)) {
        fmt.eprintf("Could not export screenshot to %q\n", args[1])
        return 1
    }
    return 0
}

@(private="file")
screenshot_usage :: proc() -> int {
    fmt.eprintln("Usage: opal --screenshot INPUT.md OUTPUT.png [--density 1–3 in 0.25 steps] [--command TEXT]")
    return 2
}
