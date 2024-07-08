package main

import rl "vendor:raylib"

Theme_Font_Variant :: enum {
    H1,
    BODY,
    PRE,
}

Theme :: struct {
    fonts: [Theme_Font_Variant]rl.Font,
    bg_color: rl.Color,
    fg_color: rl.Color,
}

theme_make_default :: proc() -> Theme {
    DEFAULT_FONT_DATA := #load("fonts/Inter-Regular.ttf")
    DEFAULT_PRE_FONT_DATA := #load("fonts/CommitMono-400-Regular.otf")

    DEFAULT_H1_SIZE :: 36
    DEFAULT_BODY_SIZE :: 20
    DEFAULT_PRE_SIZE :: 20

    SUMI_INK_0 :: rl.Color{0x16, 0x16, 0x1D, 0xFF}
    FUJI_WHITE :: rl.Color{0xDC, 0xD7, 0xBA, 0xFF}

    return {
        fonts = {
            .H1 = rl.LoadFontFromMemory(
                fileType=".ttf",
                fileData=raw_data(DEFAULT_FONT_DATA),
                dataSize=i32(len(DEFAULT_FONT_DATA)),
                fontSize=DEFAULT_H1_SIZE,
                codepoints=nil,
                codepointCount=0,
            ),
            .BODY = rl.LoadFontFromMemory(
                fileType=".ttf",
                fileData=raw_data(DEFAULT_FONT_DATA),
                dataSize=i32(len(DEFAULT_FONT_DATA)),
                fontSize=DEFAULT_BODY_SIZE,
                codepoints=nil,
                codepointCount=0,
            ),
            .PRE = rl.LoadFontFromMemory(
                fileType=".otf",
                fileData=raw_data(DEFAULT_PRE_FONT_DATA),
                dataSize=i32(len(DEFAULT_PRE_FONT_DATA)),
                fontSize=DEFAULT_PRE_SIZE,
                codepoints=nil,
                codepointCount=0,
            ),
        },
        bg_color = SUMI_INK_0,
        fg_color = FUJI_WHITE,
    }
}

theme_destroy :: proc(using theme: ^Theme) {
    for &font in fonts {
        rl.UnloadFont(font)
    }
}
