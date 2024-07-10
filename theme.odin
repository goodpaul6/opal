package main

import rl "vendor:raylib"
import "core:slice"
import "core:fmt"

Theme_Font_Variant :: enum {
    H1,
    BODY,
    PRE,
}

Theme_Font_Sizes :: [Theme_Font_Variant]i32

// This is the static data for a given theme.
Theme_Data :: struct {
    zoom_level_to_font_sizes: []Theme_Font_Sizes,
    font_data: [Theme_Font_Variant][]byte,

    bg_color: rl.Color,
    fg_color: rl.Color,
}

Theme :: struct {
    data: ^Theme_Data,

    zoom_level: int,

    // Loaded based on current zoom level
    fonts: [Theme_Font_Variant]rl.Font,
}

theme_make_default_theme_data :: proc() -> Theme_Data {
    INTER_DATA := #load("fonts/Inter-Regular.ttf")
    COMMIT_MONO_DATA := #load("fonts/CommitMono-400-Regular.otf")

    return {
        zoom_level_to_font_sizes = slice.clone([]Theme_Font_Sizes{
            {
                .H1 = 36,
                .BODY = 24,
                .PRE = 24,
            },

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
        }),

        font_data = {
            .H1 = INTER_DATA,
            .BODY = INTER_DATA,
            .PRE = COMMIT_MONO_DATA,
        },

        bg_color = {0x16, 0x16, 0x1D, 0xFF},
        fg_color = {0xDC, 0xD7, 0xBA, 0xFF},
    }
}

theme_data_destroy :: proc(data: ^Theme_Data) {
    // TODO(Apaar): Delete font data as well
    delete(data.zoom_level_to_font_sizes)
}

theme_make :: proc(data: ^Theme_Data, zoom_level := 0) -> Theme {
    font_sizes := data.zoom_level_to_font_sizes[zoom_level]

    return {
        data = data,
        zoom_level = zoom_level,
        fonts = {
            .H1 = rl.LoadFontFromMemory(
                fileType=".ttf",
                fileData=raw_data(data.font_data[.H1]),
                dataSize=i32(len(data.font_data[.H1])),
                fontSize=font_sizes[.H1],
                codepoints=nil,
                codepointCount=0,
            ),
            .BODY = rl.LoadFontFromMemory(
                fileType=".ttf",
                fileData=raw_data(data.font_data[.BODY]),
                dataSize=i32(len(data.font_data[.BODY])),
                fontSize=font_sizes[.BODY],
                codepoints=nil,
                codepointCount=0,
            ),
            .PRE = rl.LoadFontFromMemory(
                fileType=".otf",
                fileData=raw_data(data.font_data[.PRE]),
                dataSize=i32(len(data.font_data[.PRE])),
                fontSize=font_sizes[.PRE],
                codepoints=nil,
                codepointCount=0,
            ),
        },
    }
}

@(private="file")
unload_fonts :: proc(using theme: ^Theme) {
    for &font in fonts {
        rl.UnloadFont(font)
    }
}

theme_set_zoom_level :: proc(theme: ^Theme, raw_zoom_level: int) {
    zoom_level := clamp(raw_zoom_level, 0, len(theme.data.zoom_level_to_font_sizes) - 1)

    theme^ = theme_make(theme.data, zoom_level)
}

theme_destroy :: proc(theme: ^Theme) {
    unload_fonts(theme)
}
