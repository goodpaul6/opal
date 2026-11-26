package main

import "core:encoding/json"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

Canvas_Card_Color :: enum { DEFAULT, CLAY, PERSIMMON, GOLD, SAGE, TEAL, PLUM }

Canvas_Color_Preset :: struct { name, value: string, dark, light: u32 }

@(private="file")
CANVAS_CARD_COLORS := [Canvas_Card_Color]Canvas_Color_Preset{
    .DEFAULT    = {"Default", "", 0, 0},
    .CLAY       = {"Clay", "1", 0xC4746EFF, 0xC84053FF},
    .PERSIMMON = {"Persimmon", "2", 0xB6927BFF, 0xCC6D00FF},
    .GOLD       = {"Gold", "3", 0xC4B28AFF, 0xDE9800FF},
    .SAGE       = {"Sage", "4", 0x87A987FF, 0x6F894EFF},
    .TEAL       = {"Teal", "5", 0x8EA4A2FF, 0x597B75FF},
    .PLUM       = {"Plum", "6", 0xA292A3FF, 0x624C83FF},
}

canvas_card_color_tint :: proc(data: ^Theme_Data, value: string) -> (rl.Color, bool) {
    if len(value) == 1 && value[0] >= '1' && value[0] <= '6' {
        choice := Canvas_Card_Color(value[0] - '0')
        preset := CANVAS_CARD_COLORS[choice]
        tint := preset.light if data.light else preset.dark
        return rl.GetColor(tint), true
    }
    if len(value) == 7 && value[0] == '#' {
        hex, ok := strconv.parse_u64(value[1:], 16)
        if ok do return rl.GetColor(u32(hex) << 8 | 0xff), true
    }
    return {}, false
}

canvas_colorable :: proc(nodes: json.Array, index: int) -> bool {
    if index <= 0 || index > len(nodes) do return false
    kind := canvas_string(nodes[index - 1].(json.Object), "type")
    return kind == "text" || kind == "file" || kind == "link"
}

canvas_color_selection :: proc(board: ^Canvas) -> int {
    nodes := canvas_items(board, "nodes")
    if !board.visual do return board.selected if canvas_colorable(nodes, board.selected) else 0
    for index in board.visual_nodes {
        if canvas_colorable(nodes, index) do return index
    }
    return 0
}

canvas_open_color_picker :: proc(board: ^Canvas) -> bool {
    index := canvas_color_selection(board)
    if index == 0 || canvas_editor_active(board) {
        board.message = "Select a card on the canvas to change its color"
        return false
    }
    board.color_choice = .DEFAULT
    node := canvas_items(board, "nodes")[index - 1].(json.Object)
    value := canvas_string(node, "color")
    for preset, choice in CANVAS_CARD_COLORS {
        if preset.value == value do board.color_choice = choice
    }
    board.color_picker_open = true
    board.message = ""
    return true
}

canvas_set_selected_color :: proc(board: ^Canvas, choice: Canvas_Card_Color) {
    nodes := canvas_items(board, "nodes")
    single := [1]int{board.selected}
    indices := board.visual_nodes[:] if board.visual else single[:]
    value := CANVAS_CARD_COLORS[choice].value
    recorded := false
    for index in indices {
        if !canvas_colorable(nodes, index) do continue
        node := nodes[index - 1].(json.Object)
        if _, present := node["color"]; present {
            if value != "" && canvas_string(node, "color") == value do continue
        } else if value == "" {
            continue
        }
        if !recorded {
            canvas_push_undo(board)
            recorded = true
        }
        if value == "" {
            key, previous := delete_key(&node, "color")
            delete(key)
            json.destroy_value(previous)
        } else {
            canvas_set(&node, "color", strings.clone(value))
        }
    }
}

Canvas_Color_Menu :: struct {
    bounds: rl.Rectangle,
    rows: [Canvas_Card_Color]rl.Rectangle,
}

canvas_color_menu :: proc(board: ^Canvas, theme: ^Theme, width, height: i32) -> (menu: Canvas_Color_Menu) {
    anchor := canvas_toolbar_buttons(board, theme)[3].rect
    w := min(f32(172), max(0, f32(width) - 12))
    y := f32(CANVAS_BAR + 4)
    available := max(0, f32(height) - y - editor_status_line_height(theme) - 12)
    row_height := min(max(28, f32(theme.fonts[.BODY].baseSize) + 8), available / f32(len(menu.rows)))
    x := clamp(anchor.x, 6, max(6, f32(width) - w - 6))
    menu.bounds = {x, y, w, row_height * f32(len(menu.rows)) + 8}
    for choice in Canvas_Card_Color {
        menu.rows[choice] = {x + 4, y + 4 + f32(int(choice)) * row_height, max(0, w - 8), row_height}
    }
    return
}

canvas_color_picker_input :: proc(board: ^Canvas, theme: ^Theme, keys: []rl.KeyboardKey, width, height: i32) -> bool {
    for key in keys {
        #partial switch key {
            case .ESCAPE:
                board.color_picker_open = false
                return true
            case .ENTER:
                canvas_set_selected_color(board, board.color_choice)
                board.color_picker_open = false
                return true
            case .UP, .DOWN, .K, .J:
                step := -1 if key == .UP || key == .K else 1
                board.color_choice = Canvas_Card_Color(clamp(int(board.color_choice) + step, 0, len(CANVAS_CARD_COLORS) - 1))
        }
    }
    if rl.IsMouseButtonPressed(.LEFT) {
        menu := canvas_color_menu(board, theme, width, height)
        mouse := rl.GetMousePosition()
        for rect, choice in menu.rows {
            if rl.CheckCollisionPointRec(mouse, rect) {
                canvas_set_selected_color(board, choice)
                break
            }
        }
        board.color_picker_open = false
        return true
    }
    return len(keys) > 0
}

canvas_draw_color_picker :: proc(board: ^Canvas, theme: ^Theme, width, height: i32) {
    menu := canvas_color_menu(board, theme, width, height)
    bg, fg := theme.data.bg_color, theme.data.fg_color
    border := rl.ColorLerp(bg, fg, 0.25)
    mouse := rl.GetMousePosition()
    display_begin_scissor(theme, menu.bounds, height)
    defer rl.EndScissorMode()
    rl.DrawRectangleRec(menu.bounds, rl.ColorLerp(bg, fg, 0.09))
    rl.DrawRectangleLinesEx(menu.bounds, 1, border)
    size := f32(theme.fonts[.BODY].baseSize)
    for rect, choice in menu.rows {
        if rect.height < size do continue
        focused := choice == board.color_choice
        if focused || rl.CheckCollisionPointRec(mouse, rect) {
            rl.DrawRectangleRec(rect, display_selection_color(theme))
            if focused {
                focus := LOTUS_FOCUS if theme.data.light else theme.data.accent_color
                rl.DrawRectangleLinesEx(rect, 1, focus)
            }
        }
        preset := CANVAS_CARD_COLORS[choice]
        swatch := rl.Rectangle{rect.x + 8, rect.y + (rect.height - 14) / 2, 14, 14}
        color := rl.ColorLerp(bg, fg, 0.06)
        if tint, ok := canvas_card_color_tint(theme.data, preset.value); ok do color = tint
        rl.DrawRectangleRec(swatch, color)
        rl.DrawRectangleLinesEx(swatch, 1, border)
        canvas_draw_text(theme, preset.name, {rect.x + 31, rect.y + (rect.height - size) / 2}, fg)
    }
}
