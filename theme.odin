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

Theme_Font_Sizes :: [Theme_Font_Variant]i32

THEME_ZOOM_LEVEL_TO_FONT_SIZE := [?]Theme_Font_Sizes{
    {
        .H1 = 48,
        .BODY = 30,
        .PRE = 30,
    },

    {
        .H1 = 60,
        .BODY = 36,
        .PRE = 36,
    },

    {
        .H1 = 72,
        .BODY = 48,
        .PRE = 48,
    },

    {
        .H1 = 96,
        .BODY = 60,
        .PRE = 60,
    }
}

theme_make_default :: proc(zoom_level: int) -> Theme {
    DEFAULT_FONT_DATA := #load("fonts/Inter-Regular.ttf")
    DEFAULT_PRE_FONT_DATA := #load("fonts/CommitMono-400-Regular.otf")

    font_sizes := THEME_ZOOM_LEVEL_TO_FONT_SIZE[zoom_level]

    SUMI_INK_0 :: rl.Color{0x16, 0x16, 0x1D, 0xFF}
    FUJI_WHITE :: rl.Color{0xDC, 0xD7, 0xBA, 0xFF}

    return {
        fonts = {
            .H1 = rl.LoadFontFromMemory(
                fileType=".ttf",
                fileData=raw_data(DEFAULT_FONT_DATA),
                dataSize=i32(len(DEFAULT_FONT_DATA)),
                fontSize=font_sizes[.H1],
                codepoints=nil,
                codepointCount=0,
            ),
            .BODY = rl.LoadFontFromMemory(
                fileType=".ttf",
                fileData=raw_data(DEFAULT_FONT_DATA),
                dataSize=i32(len(DEFAULT_FONT_DATA)),
                fontSize=font_sizes[.BODY],
                codepoints=nil,
                codepointCount=0,
            ),
            .PRE = rl.LoadFontFromMemory(
                fileType=".otf",
                fileData=raw_data(DEFAULT_PRE_FONT_DATA),
                dataSize=i32(len(DEFAULT_PRE_FONT_DATA)),
                fontSize=font_sizes[.PRE],
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
