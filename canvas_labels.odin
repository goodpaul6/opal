package main

import "core:encoding/json"
import "core:strings"
import rl "vendor:raylib"

canvas_label_line_height :: proc(theme: ^Theme) -> f32 {
    return f32(theme.fonts[.BODY].baseSize) + 4
}

canvas_edge_label_rect :: proc(theme: ^Theme, text: string, midpoint: [2]f32, zoom: f32) -> rl.Rectangle {
    font := &theme.fonts[.BODY]
    metrics := &theme.font_metrics[.BODY]
    rest := text
    width: f32
    for line in strings.split_lines_iterator(&rest) {
        width = max(width, display_text_width(font, line, metrics))
    }
    w := (width + 12) * zoom
    h := (f32(font.baseSize) + f32(strings.count(text, "\n")) * canvas_label_line_height(theme) + 6) * zoom
    return {midpoint.x - w / 2, midpoint.y - h / 2, w, h}
}

canvas_label_editor_rect :: proc(board: ^Canvas, ed: ^Editor, theme: ^Theme, screen: [2]f32) -> rl.Rectangle {
    edge := canvas_items(board, "edges")[board.editing_edge - 1].(json.Object)
    path, ok := canvas_edge_path(board, canvas_items(board, "nodes"), edge)
    if !ok do return {}
    midpoint := canvas_path_midpoint(path)
    text := editor_get_text(ed)
    bounds := canvas_edge_label_rect(theme, text, midpoint, board.zoom)
    row_count := 1 + strings.count(text, "\n")
    font_height := f32(theme.fonts[.BODY].baseSize)
    editor_height := (f32(row_count) * font_height * theme.data.line_spacing + 6) * board.zoom
    bounds.width = min(max(bounds.width + 2 * board.zoom, 120 * board.zoom), max(0, screen.x - 16))
    bottom := screen.y - editor_status_line_height(theme)
    bounds.height = min(max(bounds.height, editor_height), max(0, bottom - CANVAS_BAR - 8))
    bounds.x = clamp(midpoint.x - bounds.width / 2, 8, max(8, screen.x - bounds.width - 8))
    bounds.y = clamp(midpoint.y - bounds.height / 2, CANVAS_BAR + 4, max(CANVAS_BAR + 4, bottom - bounds.height - 4))
    return bounds
}

canvas_inline_editor_outer_bounds :: proc(board: ^Canvas, ed: ^Editor, theme: ^Theme, screen: [2]f32) -> rl.Rectangle {
    if board.editing_edge != 0 do return canvas_label_editor_rect(board, ed, theme, screen)
    return canvas_editor_bounds(board)
}

canvas_inline_editor_begin :: proc(board: ^Canvas, ed: ^Editor, theme: ^Theme, screen: [2]f32) {
    if board.editing_edge == 0 {
        editor_display_begin(ed, theme, canvas_card_content(canvas_active_card(board), board), board.zoom, board.pan)
        return
    }
    bounds := canvas_label_editor_rect(board, ed, theme, screen)
    dimensions := [2]f32{bounds.width, bounds.height} / board.zoom
    size := rl.Rectangle{0, 0, max(0, dimensions.x - 12), max(0, dimensions.y - 6)}
    origin := [2]f32{bounds.x, bounds.y} + [2]f32{6, 3} * board.zoom
    editor_display_begin(ed, theme, size, board.zoom, origin)
}

canvas_draw_label_lines :: proc(
    theme: ^Theme, text: string, origin: [2]f32, color: rl.Color, zoom: f32, rasters: ^Canvas_Font_Rasters,
) {
    at := origin
    rest := text
    for line in strings.split_lines_iterator(&rest) {
        canvas_draw_text(theme, line, at, color, zoom, rasters)
        at.y += canvas_label_line_height(theme) * zoom
    }
}
