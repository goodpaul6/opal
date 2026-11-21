package main

import "core:testing"
import rl "vendor:raylib"

@(test)
test_font_raster_coverage :: proc(t: ^testing.T) {
    testing.expect_value(t, font_raster_coverage(0), u8(0))
    testing.expect_value(t, font_raster_coverage(255), u8(255))
    testing.expect_value(t, font_raster_coverage(127), u8(127))
    testing.expect_value(t, font_raster_coverage(128), u8(128))
    testing.expect_value(t, font_raster_coverage(64), u8(52))
    testing.expect_value(t, font_raster_coverage(191), u8(203))
    previous: u8
    for i in 0..=255 {
        alpha := u8(i)
        sharpened := font_raster_coverage(alpha)
        testing.expect(t, sharpened >= previous)
        testing.expect_value(t, sharpened, 255 - font_raster_coverage(255 - alpha))
        previous = sharpened
    }
}

@(test)
test_font_raster_adjust_atlas_only_changes_alpha :: proc(t: ^testing.T) {
    pixels := [?][2]u8{{255, 0}, {95, 64}, {200, 191}, {255, 255}}
    atlas := rl.Image{data = raw_data(pixels[:]), width = 2, height = 2, mipmaps = 1, format = .UNCOMPRESSED_GRAY_ALPHA}
    font_raster_adjust_atlas(atlas)
    testing.expect_value(t, pixels, [4][2]u8{{255, 0}, {95, 52}, {200, 203}, {255, 255}})
}

@(test)
test_font_raster_coverage_gain_curve :: proc(t: ^testing.T) {
    previous_dark, previous_light: int
    for i in 0..=255 {
        alpha := u8(i)
        dark := int(font_raster_gain_coverage(alpha, .DARK_INK))
        light := int(font_raster_gain_coverage(alpha, .LIGHT_INK))
        testing.expect_value(t, font_raster_gain_coverage(alpha, .OFF), alpha)
        testing.expect(t, dark >= previous_dark && light >= previous_light)
        testing.expect(t, 0 <= dark - i && dark - i <= 8)
        testing.expect(t, dark <= light && light - i <= 48)
        testing.expect_value(t, dark == 0, i == 0)
        testing.expect_value(t, light == 0, i == 0)
        testing.expect_value(t, dark == 255, i == 255)
        testing.expect_value(t, light == 255, i == 255)
        previous_dark, previous_light = dark, light
    }
    testing.expect_value(t, font_raster_gain_coverage(128, .DARK_INK), u8(136))
    testing.expect_value(t, font_raster_gain_coverage(128, .LIGHT_INK), u8(176))
}

@(test)
test_font_raster_coverage_gain :: proc(t: ^testing.T) {
    ink := rl.Color{0xDC, 0xD7, 0xBA, 0xFF}
    paper := rl.Color{0x16, 0x16, 0x1D, 0xFF}
    testing.expect_value(t, font_raster_coverage_gain(ink, paper), Font_Coverage_Gain.LIGHT_INK)
    testing.expect_value(t, font_raster_coverage_gain(paper, ink), Font_Coverage_Gain.DARK_INK)
    testing.expect_value(t, font_raster_coverage_gain(ink, ink), Font_Coverage_Gain.OFF)
}

@(test)
test_font_raster_apply_coverage_gain_only_changes_alpha :: proc(t: ^testing.T) {
    original := [4][2]u8{{255, 0}, {95, 128}, {200, 64}, {255, 255}}
    pixels := original
    atlas := rl.Image{data = raw_data(pixels[:]), width = 2, height = 2, mipmaps = 1, format = .UNCOMPRESSED_GRAY_ALPHA}
    font_raster_apply_coverage_gain(atlas, .OFF)
    testing.expect_value(t, pixels, original)
    font_raster_apply_coverage_gain(atlas, .LIGHT_INK)
    testing.expect_value(t, pixels, [4][2]u8{{255, 0}, {95, 176}, {200, 100}, {255, 255}})
}
