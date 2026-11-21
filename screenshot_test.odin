package main

import "core:testing"

@(test)
test_screenshot_density :: proc(t: ^testing.T) {
    cases := [?]struct { density: string, pixels: [2]i32 }{
        {"1", {800, 450}}, {"1.25", {1000, 563}}, {"1.5", {1200, 675}},
        {"1.75", {1400, 788}}, {"2", {1600, 900}}, {"2.25", {1800, 1013}},
        {"2.5", {2000, 1125}}, {"2.75", {2200, 1238}}, {"3", {2400, 1350}},
    }
    for c in cases {
        testing.expect_value(t, screenshot_pixel_size(screenshot_density_quarters(c.density)), c.pixels)
    }
    invalid_values := [?]string{"", "0.5", "1.3", "4", "NaN"}
    for invalid in invalid_values {
        testing.expect_value(t, screenshot_density_quarters(invalid), i32(0))
    }
}
