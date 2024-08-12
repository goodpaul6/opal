package main

import "core:slice"
import "core:fmt"
import nvg "vendor:nanovg"

Theme_Font_ID :: int

Theme_Font_Variant :: enum {
    H1,
    BODY,
    PRE,
}

Theme_Font_Sizes :: [Theme_Font_Variant]i32

Theme_Font_Data :: struct {
    name: string,
    data: []byte,
}

// This is the static data for a given theme.
Theme_Data :: struct {
    zoom_level_to_font_sizes: []Theme_Font_Sizes,
    font_data: [Theme_Font_Variant]Theme_Font_Data,

    bg_color: nvg.Color,
    fg_color: nvg.Color,
}

Theme :: struct {
    data: ^Theme_Data,

    zoom_level: int,

    // Loaded based on current zoom level.
    fonts: [Theme_Font_Variant]Theme_Font_ID,
}

theme_data_make_default :: proc() -> Theme_Data {
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
            .H1 = {"Inter", slice.clone(INTER_DATA[:])},
            .BODY = {"Inter", slice.clone(INTER_DATA[:])},
            .PRE = {"Commit Mono", slice.clone(COMMIT_MONO_DATA[:])}
        },

        bg_color = nvg.ColorHex(0xff16161d),
        fg_color = nvg.ColorHex(0xffdcd7ba),
    }
}

theme_data_destroy :: proc(using data: ^Theme_Data) {
    delete(zoom_level_to_font_sizes)

    for variant in Theme_Font_Variant {
        delete(font_data[variant].data)
    }
}

theme_make :: proc(data: ^Theme_Data, nvc: ^nvg.Context, zoom_level: int) -> Theme {
    font_sizes := data.zoom_level_to_font_sizes[zoom_level]

    load_if_not_loaded :: proc(nvc: ^nvg.Context, data: Theme_Font_Data) -> int {
        res := nvg.FindFont(nvc, data.name)

        if res >= 0 {
            return res
        }

        return nvg.CreateFontMem(nvc, data.name, data.data, false)
    }

    return {
        data = data,
        zoom_level = zoom_level,
        fonts = {
            .H1 = load_if_not_loaded(nvc, data.font_data[.H1]),
            .BODY = load_if_not_loaded(nvc, data.font_data[.BODY]),
            .PRE = load_if_not_loaded(nvc, data.font_data[.PRE]),
        },
    }
}

theme_destroy :: proc(using theme: ^Theme) {
    // TODO(Apaar): Figure out a way to unload fonts from NanoVG?
}

theme_set_zoom_level :: proc(theme: ^Theme, nvc: ^nvg.Context, raw_zoom_level: int) {
    data := theme.data
    theme_destroy(theme)

    zoom_level := clamp(raw_zoom_level, 0, len(data.zoom_level_to_font_sizes) - 1)

    theme^ = theme_make(data, nvc, zoom_level)
}

theme_font_variant_size :: proc(theme: ^Theme, variant: Theme_Font_Variant) -> i32 {
    return theme.data.zoom_level_to_font_sizes[theme.zoom_level][variant]
}
