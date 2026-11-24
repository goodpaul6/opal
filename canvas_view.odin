package main

import "core:encoding/json"
import "core:math"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

CANVAS_BAR :: 44

Canvas_Button :: struct {
    label: string,
    rect: rl.Rectangle,
}

canvas_toolbar_buttons :: proc(board: ^Canvas, theme: ^Theme) -> (buttons: [3]Canvas_Button) {
    labels := [3]string{"New card", "Open", "Save"}
    if canvas_editor_active(board) {
        labels[0] = "Done"
        labels[1] = "Collapse" if board.expanded else "Expand"
    }
    font := &theme.fonts[.BODY]
    height := max(28, f32(font.baseSize))
    x: f32 = 12
    for label, i in labels {
        width := max(58, display_text_width(font, label, &theme.font_metrics[.BODY]) + 16)
        buttons[i] = {label, {x, (CANVAS_BAR - height) / 2, width, height}}
        x += width + 8
    }
    return
}

canvas_corner :: proc(rect: rl.Rectangle) -> [2]f32 {
    return {rect.x + rect.width, rect.y + rect.height}
}

canvas_anchor :: proc(rect: rl.Rectangle, side: Canvas_Side) -> [2]f32 {
    switch side {
        case .TOP: return {rect.x + rect.width / 2, rect.y}
        case .RIGHT: return {rect.x + rect.width, rect.y + rect.height / 2}
        case .BOTTOM: return {rect.x + rect.width / 2, rect.y + rect.height}
        case .LEFT: return {rect.x, rect.y + rect.height / 2}
    }
    return {}
}

canvas_distance_squared :: proc(a, b: [2]f32) -> f32 {
    d := a - b
    return d.x * d.x + d.y * d.y
}

canvas_edge_side :: proc(edge: json.Object, key: string, rect: rl.Rectangle, toward: [2]f32) -> Canvas_Side {
    value := canvas_string(edge, key)
    nearest: Canvas_Side
    distance := max(f32)
    sides := CANVAS_SIDES
    for side in Canvas_Side {
        if value == sides[side] do return side
        d := canvas_distance_squared(canvas_anchor(rect, side), toward)
        if d < distance {
            nearest, distance = side, d
        }
    }
    return nearest
}

canvas_node_rect :: proc(node: json.Object) -> rl.Rectangle {
    return {canvas_coord(node, "x"), canvas_coord(node, "y"), max(1, canvas_coord(node, "width")), max(1, canvas_coord(node, "height"))}
}

canvas_rect :: proc(board: ^Canvas, node: json.Object) -> rl.Rectangle {
    return display_view_rect(canvas_positioned_node(board, node), board.pan, board.zoom)
}

canvas_positioned_node :: proc(board: ^Canvas, node: json.Object) -> rl.Rectangle {
    rect := canvas_node_rect(node)
    if board != nil && (board.key_mode == .MOVE || board.key_mode == .RESIZE) &&
        board.node_indices[canvas_string(node, "id")] == board.key_move.node {
        if board.key_move.resize {
            rect.width, rect.height = f32(board.key_move.values.x), f32(board.key_move.values.y)
        } else {
            rect.x, rect.y = f32(board.key_move.values.x), f32(board.key_move.values.y)
        }
    }
    return rect
}

canvas_card_content :: proc(node: json.Object, board: ^Canvas = nil) -> rl.Rectangle {
    rect := canvas_positioned_node(board, node)
    return {rect.x + 10, rect.y + 9, max(0, rect.width - 20), max(0, rect.height - 18)}
}

canvas_editor_bounds :: proc(board: ^Canvas) -> rl.Rectangle {
    return display_view_rect(canvas_card_content(canvas_active_card(board)), board.pan, board.zoom)
}

canvas_toggle_expanded :: proc(board: ^Canvas, ed: ^Editor) {
    board.expanded = !board.expanded
    ed.mouse_selecting = false
    ed.should_scroll_cursor_into_view = true
}

CANVAS_ZOOM_SETTLE_SECONDS :: 0.12
CANVAS_MIN_ZOOM :: 0.12
CANVAS_MAX_ZOOM :: 3

canvas_grid_step :: proc(zoom: f32) -> i64 {
    step := i64(CANVAS_GRID_STEP)
    for f32(step) * max(zoom, CANVAS_MIN_ZOOM) < 16 {
        step *= 2
    }
    return step
}

canvas_zoom_at :: proc(board: ^Canvas, point: [2]f32, wheel: f32, now: f64 = 0) -> bool {
    anchor := (point - board.pan) / board.zoom
    zoom := clamp(board.zoom * math.pow(f32(1.15), wheel), CANVAS_MIN_ZOOM, CANVAS_MAX_ZOOM)
    if zoom == board.zoom do return false
    board.zoom = zoom
    board.pan = point - anchor * board.zoom
    board.zoom_settle_at = now + CANVAS_ZOOM_SETTLE_SECONDS
    return true
}

canvas_render_rasters :: proc(board: ^Canvas, theme: ^Theme) -> ^Canvas_Font_Rasters {
    body := theme.fonts[.BODY].baseSize
    base_pixels := theme_raster_size(body, theme.pixel_scale.y)
    pixels := theme_raster_size(body, theme.pixel_scale.y * board.zoom)
    if board.zoom == 1 || pixels == base_pixels || pixels < 7 do return nil

    closest: ^Canvas_Font_Rasters
    // Compare ratios so a tiny cached atlas doesn't replace a closer base atlas.
    distance := f32(max(base_pixels, pixels)) / f32(min(base_pixels, pixels))
    for &rasters, i in board.rasters {
        if rasters.body_pixels == 0 || rasters.zoom_level != i32(theme.zoom_level) do continue
        if rasters.body_pixels == pixels {
            board.last_rasters = i
            rasters.prepare = board.zoom_settle_at == 0
            return &rasters
        }
        ratio := f32(max(rasters.body_pixels, pixels)) / f32(min(rasters.body_pixels, pixels))
        if ratio < distance {
            closest, distance = &rasters, ratio
        }
    }
    if board.zoom_settle_at != 0 {
        if closest != nil do closest.prepare = false
        return closest
    }
    board.last_rasters = 1 - board.last_rasters
    rasters := &board.rasters[board.last_rasters]
    canvas_font_rasters_destroy(rasters)
    rasters.body_pixels = pixels
    rasters.zoom_level = i32(theme.zoom_level)
    rasters.prepare = true
    return rasters
}

canvas_frame_board :: proc(board: ^Canvas, viewport: [2]f32, fit_zoom := true) {
    board.fit = false
    nodes := canvas_items(board, "nodes")
    if len(nodes) == 0 {
        board.pan = canvas_view_center(viewport)
        if fit_zoom do board.zoom = 1
        return
    }
    lower := [2]f32{max(f32), max(f32)}
    upper := [2]f32{-max(f32), -max(f32)}
    for item in nodes {
        rect := canvas_node_rect(item.(json.Object))
        lower = {min(lower.x, rect.x), min(lower.y, rect.y)}
        up := canvas_corner(rect)
        upper = {max(upper.x, up.x), max(upper.y, up.y)}
    }
    if fit_zoom {
        margin :: 40
        available := viewport - [2]f32{2 * margin, CANVAS_BAR + 2 * margin}
        size := upper - lower
        board.zoom = clamp(min(available.x / size.x, available.y / size.y), CANVAS_MIN_ZOOM, 1)
    }
    board.pan = canvas_view_center(viewport) - (lower + upper) / 2 * board.zoom
}

canvas_hit_card :: proc(board: ^Canvas, nodes: json.Array, mouse: [2]f32) -> int {
    for i := len(nodes) - 1; i >= 0; i -= 1 {
        if rl.CheckCollisionPointRec(mouse, canvas_rect(board, nodes[i].(json.Object))) do return i + 1
    }
    return 0
}

canvas_hit_edge_label :: proc(board: ^Canvas, theme: ^Theme, nodes: json.Array, mouse: [2]f32) -> int {
    edges := canvas_items(board, "edges")
    for i := len(edges) - 1; i >= 0; i -= 1 {
        edge := edges[i].(json.Object)
        label := canvas_string(edge, "label")
        if label == "" do continue
        path, ok := canvas_edge_path(board, nodes, edge)
        if ok && rl.CheckCollisionPointRec(mouse, canvas_edge_label_rect(theme, label, canvas_path_midpoint(path), board.zoom)) do return i + 1
    }
    return 0
}

canvas_hit_edge :: proc(board: ^Canvas, nodes: json.Array, mouse: [2]f32) -> int {
    edges := canvas_items(board, "edges")
    for i := len(edges) - 1; i >= 0; i -= 1 {
        path, ok := canvas_edge_path(board, nodes, edges[i].(json.Object))
        if ok && canvas_hit_path(path, mouse) do return i + 1
    }
    return 0
}

canvas_add_at :: proc(board: ^Canvas, ed: ^Editor, point: [2]f32) {
    pos := (point - board.pan) / board.zoom
    board.selected = canvas_add_card(board, i64(math.round(pos.x)), i64(math.round(pos.y)))
    board.selected_edge = 0
    canvas_edit_card(board, ed, board.selected, true)
}

canvas_add_from_toolbar :: proc(board: ^Canvas, ed: ^Editor, width, height: f32) {
    center := [2]f32{width / 2, (height + CANVAS_BAR) / 2}
    half_card := canvas_new_card_size(board.zoom) * board.zoom / 2
    point := center - half_card
    nodes := canvas_items(board, "nodes")
    previous := board.selected
    if previous == 0 do previous = len(nodes)
    if previous != 0 {
        rect := canvas_rect(board, nodes[previous - 1].(json.Object))
        point = {rect.x + rect.width + 32 * board.zoom, rect.y}
        if point.x + 2 * half_card.x > width || point.y < CANVAS_BAR || point.y + 2 * half_card.y > height {
            board.pan += center - (point + half_card)
            point = center - half_card
        }
    }
    canvas_add_at(board, ed, point)
}

canvas_open_prompt :: proc(board: ^Canvas, ed: ^Editor) {
    if canvas_dirty(board, ed) {
        board.message = "Save this canvas before opening another"
    } else {
        board.message = ""
        canvas_begin_prompt(board, .OPEN)
    }
}

canvas_prompt_clear_selection :: proc(board: ^Canvas) {
    if board.prompt_replace_all {
        strings.builder_reset(&board.prompt_text)
        board.prompt_replace_all = false
        board.prompt_cursor = 0
    }
}

canvas_prompt_insert :: proc(board: ^Canvas, text: []byte) {
    canvas_prompt_clear_selection(board)
    if ok, _ := inject_at_elems(&board.prompt_text.buf, board.prompt_cursor, ..text); ok {
        board.prompt_cursor += len(text)
    }
}

canvas_prompt_input :: proc(board: ^Canvas, ed: ^Editor, keys: []rl.KeyboardKey, chars: []rune, mods: Editor_Key_Mod_State) {
    shortcut := .CMD in mods || .CTRL in mods
    if board.prompt == .CLOSE {
        for key in keys {
            #partial switch key {
                case .ESCAPE: board.prompt = .NONE
                case .D: board.exit_requested = true
                case .ENTER:
                    board.close_after_save = true
                    board.prompt = .NONE
                    canvas_request_save(board, ed)
                case:
            }
        }
        return
    }
    if !shortcut {
        for ch in chars {
            if ch >= ' ' && ch != 127 {
                encoded, count := utf8.encode_rune(ch)
                canvas_prompt_insert(board, encoded[:count])
            }
        }
    }
    for key in keys {
        #partial switch key {
            case .ESCAPE:
                board.prompt = .NONE
                board.close_after_save = false
                board.finish_after_save = false
                board.message = ""
                return
            case .LEFT, .RIGHT, .HOME, .END:
                buf := board.prompt_text.buf[:]
                pos := board.prompt_cursor
                if key == .HOME || (shortcut && key == .LEFT) {
                    pos -= byte_index_to_editor_loc(pos, buf).col
                } else if key == .END || (shortcut && key == .RIGHT) {
                    pos = editor_find_line_end(buf, pos)
                } else if board.prompt_replace_all {
                    pos = 0 if key == .LEFT else len(buf)
                } else if key == .LEFT {
                    _, n := utf8.decode_last_rune(buf[:pos])
                    pos -= n
                } else {
                    _, n := utf8.decode_rune(buf[pos:])
                    pos += n
                }
                board.prompt_cursor, board.prompt_replace_all = pos, false
            case .BACKSPACE, .DELETE:
                if board.prompt_replace_all {
                    canvas_prompt_clear_selection(board)
                } else {
                    buf := &board.prompt_text.buf
                    lo, hi := board.prompt_cursor, board.prompt_cursor
                    if key == .BACKSPACE {
                        _, n := utf8.decode_last_rune(buf^[:lo])
                        lo -= n
                    } else {
                        _, n := utf8.decode_rune(buf^[hi:])
                        hi += n
                    }
                    copy(buf^[lo:], buf^[hi:])
                    resize(buf, len(buf^) - (hi - lo))
                    board.prompt_cursor = lo
                }
            case .A:
                if shortcut do board.prompt_replace_all = true
            case .V:
                if shortcut {
                    if text, ok := editor_system_clipboard_get(nil); ok {
                        canvas_prompt_insert(board, transmute([]byte)strings.trim_space(text))
                    }
                }
            case .ENTER:
                path := strings.trim_space(strings.to_string(board.prompt_text))
                if path == "" do continue
                if board.prompt == .OPEN {
                    if canvas_open(board, path) do board.prompt = .NONE
                } else if canvas_save(board, path) {
                    canvas_complete_save(board)
                }
            case:
        }
    }
}

canvas_zoom_key_delta :: proc(board: ^Canvas, key: rl.KeyboardKey, mods: Editor_Key_Mod_State) -> int {
    if board.expanded || board.prompt != .NONE do return 0
    return live_zoom_shortcut_delta(key, mods, .CMD in mods)
}

canvas_keyboard_zoom :: proc(board: ^Canvas, keys: []rl.KeyboardKey, mods: Editor_Key_Mod_State, screen: [2]f32, now: f64) -> bool {
    zoomed := false
    for key in keys {
        if delta := canvas_zoom_key_delta(board, key, mods); delta != 0 {
            canvas_zoom_at(board, canvas_view_center(screen), f32(delta), now)
            zoomed = true
        }
    }
    return zoomed
}

// Return true when the canvas or its toolbar consumed the frame's input.
canvas_handle_input :: proc(
    board: ^Canvas, ed: ^Editor, theme: ^Theme, keys: []rl.KeyboardKey, chars: []rune, mods: Editor_Key_Mod_State,
    width, height: i32,
) -> (consumed, changed: bool) {
    shortcut := .CMD in mods || .CTRL in mods
    screen := [2]f32{f32(width), f32(height)}
    if board.fit && !board.expanded do canvas_frame_board(board, screen)
    if shortcut && len(keys) > 0 && canvas_keyboard_zoom(board, keys, mods, screen, rl.GetTime()) {
        return true, true
    }
    if board.prompt != .NONE {
        canvas_prompt_input(board, ed, keys, chars, mods)
        return true, len(keys) > 0 || len(chars) > 0
    }
    mouse := rl.GetMousePosition()
    pressed, down := rl.IsMouseButtonPressed(.LEFT), rl.IsMouseButtonDown(.LEFT)
    if canvas_editor_active(board) {
        if pressed && mouse.y < CANVAS_BAR {
            buttons := canvas_toolbar_buttons(board, theme)
            if rl.CheckCollisionPointRec(mouse, buttons[0].rect) do board.finish_editing = true
            if rl.CheckCollisionPointRec(mouse, buttons[1].rect) do canvas_toggle_expanded(board, ed)
            if rl.CheckCollisionPointRec(mouse, buttons[2].rect) do canvas_request_save(board, ed)
            return true, true
        }
        for key in keys {
            if shortcut && key == .S {
                canvas_request_save(board, ed)
                return true, true
            }
            if shortcut && key == .ENTER {
                if .SHIFT in mods do canvas_toggle_expanded(board, ed)
                else do board.finish_editing = true
                return true, true
            }
        }
        if board.expanded do return false, false
        if pressed && !rl.CheckCollisionPointRec(mouse, canvas_inline_editor_outer_bounds(board, ed, theme, screen)) {
            canvas_finish_editing(board, ed)
        } else {
            wheel := rl.GetMouseWheelMove()
            if wheel != 0 && mouse.y >= CANVAS_BAR {
                canvas_zoom_at(board, mouse, wheel, rl.GetTime())
                return true, true
            }
            return false, false
        }
    }

    if board.drag == .NONE {
        if pressed && board.key_mode != .NORMAL {
            board.key_mode, board.connect_from = .NORMAL, 0
            board.last_click = 0
        }
        if pressed && mouse.y < CANVAS_BAR {
            buttons := canvas_toolbar_buttons(board, theme)
            if rl.CheckCollisionPointRec(mouse, buttons[0].rect) {
                canvas_add_from_toolbar(board, ed, f32(width), f32(height))
            } else if rl.CheckCollisionPointRec(mouse, buttons[1].rect) {
                canvas_open_prompt(board, ed)
            } else if rl.CheckCollisionPointRec(mouse, buttons[2].rect) {
                canvas_request_save(board, ed)
            }
            return true, true
        }
        for key in keys {
            if key == .N && mods == {} && board.key_mode == .NORMAL {
                if mouse.y >= CANVAS_BAR && mouse.y < f32(height) && mouse.x >= 0 && mouse.x < f32(width) {
                    canvas_add_at(board, ed, mouse)
                } else {
                    canvas_add_from_toolbar(board, ed, f32(width), f32(height))
                }
                return true, true
            }
            if canvas_keyboard_key(board, ed, key, mods, {f32(width), f32(height)}) do board.last_click = 0
            if canvas_editor_active(board) || board.prompt != .NONE do return true, true
        }
    }

    if mouse.y >= CANVAS_BAR && board.drag == .NONE {
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            canvas_zoom_at(board, mouse, wheel, rl.GetTime())
            changed = true
        }
    }
    nodes := canvas_items(board, "nodes")
    if pressed && mouse.y >= CANVAS_BAR && board.drag == .NONE {
        board.drag_start = mouse
        board.drag_point = mouse
        board.drag_recorded = false
        if board.selected != 0 {
            rect := canvas_rect(board, nodes[board.selected - 1].(json.Object))
            for side in Canvas_Side {
                if canvas_distance_squared(mouse, canvas_anchor(rect, side)) <= 64 {
                    board.drag, board.side = .CONNECT, side
                    return true, true
                }
            }
            if canvas_distance_squared(mouse, canvas_corner(rect)) <= 81 {
                board.drag, board.drag_origin = .RESIZE, canvas_node_rect(nodes[board.selected - 1].(json.Object))
                return true, true
            }
        }
        edge := canvas_hit_edge_label(board, theme, nodes, mouse)
        index := 0 if edge != 0 else canvas_hit_card(board, nodes, mouse)
        if index == 0 && edge == 0 do edge = canvas_hit_edge(board, nodes, mouse)
        now := rl.GetTime()
        double_click := board.last_click > 0 && now - board.last_click <= 0.34 &&
                        index == board.last_click_node && edge == board.last_click_edge &&
                        canvas_distance_squared(mouse, board.last_click_point) <= 36
        board.selected, board.selected_edge = index, edge
        if double_click {
            board.last_click = 0
            if edge != 0 {
                canvas_reveal_edge(board, screen)
                canvas_edit_edge(board, ed, edge)
            }
            else if index != 0 do canvas_edit_card(board, ed, index)
            else do canvas_add_at(board, ed, mouse)
            return true, true
        }
        board.last_click, board.last_click_point, board.last_click_node = now, mouse, index
        board.last_click_edge = edge
        if index != 0 {
            board.drag = .MOVE
            board.drag_origin = canvas_node_rect(nodes[index - 1].(json.Object))
        } else if edge == 0 {
            board.drag = .PAN
            board.drag_origin = {board.pan.x, board.pan.y, 0, 0}
        }
        return true, true
    }

    if board.drag != .NONE {
        if down && board.drag_point == mouse do return true, false
        board.drag_point = mouse
        delta := mouse - board.drag_start
        if board.drag == .CONNECT {
            if !down {
                index, side := canvas_connection_target(board, nodes, mouse)
                if index != 0 {
                    canvas_connect(board, board.selected, index, board.side, side)
                }
            }
        } else if board.drag_recorded || canvas_distance_squared(mouse, board.drag_start) >= 9 {
            if board.drag == .PAN {
                board.pan = [2]f32{board.drag_origin.x, board.drag_origin.y} + delta
            } else {
                origin := board.drag_origin
                resizing := board.drag == .RESIZE
                local_delta := delta / board.zoom
                value := [2]f32{origin.x, origin.y} + local_delta
                if resizing {
                    size := [2]f32{origin.width, origin.height} + local_delta
                    value = {max(100, size.x), max(68, size.y)}
                }
                values := [2]json.Integer{json.Integer(math.round(value.x)), json.Integer(math.round(value.y))}
                if !canvas_drag_geometry(board, {board.selected, resizing, values}) && !board.drag_recorded {
                    if !down do board.drag = .NONE
                    return true, !down
                }
            }
            board.drag_recorded = true
            board.last_click = 0
        }
        if !down do board.drag = .NONE
        return true, true
    }
    return true, changed || len(keys) > 0
}

canvas_draw_text :: proc(
    theme: ^Theme, text: string, pos: [2]f32, color: rl.Color, zoom: f32 = 1, rasters: ^Canvas_Font_Rasters = nil,
) {
    display_draw_text(theme, &theme.fonts[.BODY], text, {}, color, origin = pos, zoom = zoom, rasters = rasters)
}

canvas_draw_button :: proc(theme: ^Theme, rect: rl.Rectangle, label: string) {
    rl.DrawRectangleRec(rect, rl.ColorLerp(theme.data.bg_color, theme.data.fg_color, 0.09))
    size := f32(theme.fonts[.BODY].baseSize)
    canvas_draw_text(theme, label, {rect.x + 8, rect.y + (rect.height - size) / 2}, theme.data.fg_color)
}

canvas_draw_arrow :: proc(tip, tail: [2]f32, color: rl.Color) {
    delta := tip - tail
    length := math.sqrt(delta.x * delta.x + delta.y * delta.y)
    if length < 2 do return
    direction := delta / length
    head := tip - direction * min(10, length * 0.5)
    wing := [2]f32{-direction.y, direction.x} * 5
    rl.DrawLineEx(tip, head + wing, 1.5, color)
    rl.DrawLineEx(tip, head - wing, 1.5, color)
}

canvas_draw_edge_path :: proc(path: Canvas_Edge_Path, color: rl.Color, from_arrow, to_arrow: bool) {
    for i in 0..<path.count - 1 {
        a, b := path.points[i], path.points[i + 1]
        if a != b do rl.DrawLineEx(a, b, 1.5, color)
    }
    if from_arrow do canvas_draw_arrow(path.points[0], path.points[1], color)
    if to_arrow do canvas_draw_arrow(path.points[path.count - 1], path.points[path.count - 2], color)
}

canvas_draw_connection_ports :: proc(rect: rl.Rectangle, active: Canvas_Side, accent: rl.Color) {
    for side in Canvas_Side {
        size: f32 = 5.5 if side == active else 3
        color := accent if side == active else rl.ColorAlpha(accent, 0.55)
        rl.DrawCircleV(canvas_anchor(rect, side), size, color)
    }
}

canvas_draw_board :: proc(board: ^Canvas, ed: ^Editor, theme: ^Theme, width, height: i32, trace: ^Input_Frame_Trace) {
    bg, fg := theme.data.bg_color, theme.data.fg_color
    accent, muted := theme.data.accent_color, theme.data.muted_color
    w, h := f32(width), f32(height)
    if board.fit do canvas_frame_board(board, {w, h})
    rasters := canvas_render_rasters(board, theme)

    spacing := f32(canvas_grid_step(board.zoom)) * board.zoom
    y0 := board.pan.y - CANVAS_BAR - math.floor((board.pan.y - CANVAS_BAR) / spacing) * spacing
    grid_color := rl.ColorLerp(bg, muted, 0.27)
    for x := board.pan.x - math.floor(board.pan.x / spacing) * spacing; x < w; x += spacing {
        for y := CANVAS_BAR + y0; y < h; y += spacing {
            rl.DrawRectangleRec({x - 0.75, y - 0.75, 1.5, 1.5}, grid_color)
        }
    }

    nodes := canvas_items(board, "nodes")
    edges := canvas_items(board, "edges")
    for item, i in edges {
        edge := item.(json.Object)
        path, ok := canvas_edge_path(board, nodes, edge)
        if !ok do continue
        color := accent if i + 1 == board.selected_edge else muted
        to_end := canvas_string(edge, "toEnd")
        canvas_draw_edge_path(path, color, canvas_string(edge, "fromEnd") == "arrow", to_end == "" || to_end == "arrow")
    }

    for item, i in nodes {
        node := item.(json.Object)
        rect := canvas_rect(board, node)
        if rect.x >= w || rect.y >= h || rect.x + rect.width <= 0 || rect.y + rect.height <= CANVAS_BAR do continue
        selected := board.selected == i + 1
        kind := canvas_string(node, "type")
        fill := rl.ColorLerp(bg, fg, 0.06)
        if kind == "group" do fill = rl.ColorAlpha(fill, 0.4)
        rl.DrawRectangleRec(rect, fill)
        rl.DrawRectangleLinesEx(rect, 1, accent if selected || board.connect_from == i + 1 else rl.ColorLerp(bg, fg, 0.23))
        text := kind
        switch kind {
            case "text": text = canvas_string(node, "text")
            case "file": text = canvas_string(node, "file")
            case "link": text = canvas_string(node, "url")
            case "group": text = canvas_string(node, "label")
        }
        if board.editing == i + 1 {
            editor_display_begin(ed, theme, canvas_card_content(node), board.zoom, board.pan)
            editor_display_draw(ed, theme, width, height, trace, show_status = false, rasters = rasters)
        } else {
            canvas_draw_preview(board, theme, text, canvas_card_content(node, board), height, rasters)
        }
        if selected {
            for side in Canvas_Side do rl.DrawCircleV(canvas_anchor(rect, side), 4, accent)
            rl.DrawCircleV(canvas_corner(rect), 3.5, accent)
        }
    }

    for item, i in edges {
        if board.editing_edge == i + 1 do continue
        edge := item.(json.Object)
        label := canvas_string(edge, "label")
        if label == "" do continue
        path, ok := canvas_edge_path(board, nodes, edge)
        if !ok do continue
        bounds := canvas_edge_label_rect(theme, label, canvas_path_midpoint(path), board.zoom)
        if bounds.x >= w || bounds.y >= h || bounds.x + bounds.width <= 0 || bounds.y + bounds.height <= CANVAS_BAR do continue
        rl.DrawRectangleRec(bounds, bg)
        border := accent if i + 1 == board.selected_edge else rl.ColorLerp(bg, fg, 0.23)
        rl.DrawRectangleLinesEx(bounds, 1, border)
        canvas_draw_label_lines(theme, label, [2]f32{bounds.x, bounds.y} + [2]f32{6, 3} * board.zoom, fg, board.zoom, rasters)
    }

    if board.editing_edge != 0 {
        bounds := canvas_label_editor_rect(board, ed, theme, {w, h})
        if bounds.width > 0 && bounds.height > 0 {
            rl.DrawRectangleRec(bounds, bg)
            rl.DrawRectangleLinesEx(bounds, 1, accent)
            canvas_inline_editor_begin(board, ed, theme, {w, h})
            editor_display_draw(ed, theme, width, height, trace, show_status = false, rasters = rasters)
        }
    }

    if board.drag == .CONNECT {
        source := canvas_rect(board, nodes[board.selected - 1].(json.Object))
        mouse := rl.GetMousePosition()
        target, side := canvas_connection_target(board, nodes, mouse)
        if target != 0 {
            rect := canvas_rect(board, nodes[target - 1].(json.Object))
            canvas_draw_edge_path(canvas_route_edge(source, rect, board.side, side, board.zoom), accent, false, true)
            canvas_draw_connection_ports(rect, side, accent)
        } else {
            a := canvas_anchor(source, board.side)
            rl.DrawLineEx(a, mouse, 1.5, accent)
            canvas_draw_arrow(mouse, a, accent)
        }
    }
    if board.key_mode == .CONNECT {
        if board.selected != 0 && board.selected != board.connect_from {
            a, b, from_side, to_side := canvas_key_edge_anchors(board)
            canvas_draw_edge_path(canvas_route_edge(a, b, from_side, to_side, board.zoom), accent, false, true)
            canvas_draw_connection_ports(a, from_side, accent)
            canvas_draw_connection_ports(b, to_side, accent)
        } else if side, ok := board.connect_source_side.?; ok {
            source := canvas_rect(board, nodes[board.connect_from - 1].(json.Object))
            canvas_draw_connection_ports(source, side, accent)
        }
    }
    if len(nodes) == 0 {
        help :: "Press i or double-click to add a Markdown card"
        font := &theme.fonts[.BODY]
        size := display_text_width(font, help, &theme.font_metrics[.BODY])
        canvas_draw_text(theme, help, {max(12, (w - size) / 2), h / 2}, muted)
    }
    if canvas_editor_active(board) do editor_status_draw(ed, theme, width, height)
}

// Keep board layout bounded even when a card contains a long draft.
canvas_draw_preview :: proc(
    board: ^Canvas, theme: ^Theme, text: string, content: rl.Rectangle, height: i32, rasters: ^Canvas_Font_Rasters,
) {
    bounds := display_view_rect(content, board.pan, board.zoom)
    top, bottom := max(bounds.y, CANVAS_BAR), min(bounds.y + bounds.height, f32(height))
    if text == "" || bounds.width <= 0 || bottom <= top do return
    end := min(len(text), 8192)
    if end < len(text) {
        for end > 0 && !utf8.rune_start(text[end]) do end -= 1
    }
    preview := text[:end]
    display_begin_scissor(theme, {bounds.x, top, bounds.width, bottom - top}, height)
    defer rl.EndScissorMode()
    viewport := Display_Viewport{theme, {bounds.x, bounds.y}, top, bottom, board.zoom, rasters}
    display_command_gen(nil, theme, {content.width, content.height}, display_command_draw, &viewport,
                        stop_y = (bottom - bounds.y) / board.zoom, preview = &preview)
}

canvas_draw_toolbar :: proc(board: ^Canvas, ed: ^Editor, theme: ^Theme, width, height: i32) {
    bg, fg, muted := theme.data.bg_color, theme.data.fg_color, theme.data.muted_color
    rl.DrawRectangleRec({0, 0, f32(width), CANVAS_BAR}, rl.ColorLerp(bg, fg, 0.045))
    buttons := canvas_toolbar_buttons(board, theme)
    for button in buttons do canvas_draw_button(theme, button.rect, button.label)
    last := buttons[len(buttons) - 1].rect
    text_x := last.x + last.width + 16
    title := "Untitled canvas" if board.filename == "" else os.base(board.filename)
    if canvas_dirty(board, ed) {
        rl.DrawCircleV({text_x + 3, CANVAS_BAR / 2}, 3, theme.data.accent_color)
        text_x += 13
    }
    size := f32(theme.fonts[.BODY].baseSize)
    canvas_draw_text(theme, title, {text_x, (CANVAS_BAR - size) / 2}, muted)
    message := board.message
    switch board.key_mode {
        case .NORMAL:
        case .MOVE: message = "Move · h j k l · Enter to place · Esc to cancel"
        case .RESIZE: message = "Resize · h j k l · Enter to apply · Esc to cancel"
        case .CONNECT: message = "Connect · Shift+direction sets target · Option+direction sets source"
        case .G_PREFIX: message = "g · c to connect"
    }

    if board.prompt != .NONE {
        panel := rl.Rectangle{12, CANVAS_BAR + 12, max(0, min(f32(width) - 24, 720)), size * 3 + 32}
        rl.DrawRectangleRec(panel, rl.ColorLerp(bg, fg, 0.12))
        label := "Open canvas" if board.prompt == .OPEN else "Save canvas"
        value := strings.to_string(board.prompt_text)
        if board.prompt == .CLOSE {
            label = "Save changes before closing?"
            value = "Enter to save, D to discard, Esc to cancel"
        }
        if value == "" {
            value = "Type or paste a .canvas path and press Enter"
        } else {
            font := &theme.fonts[.BODY]
            metrics := &theme.font_metrics[.BODY]
            for len(value) > 0 && display_text_width(font, value, metrics) > panel.width - 24 {
                _, n := utf8.decode_rune(value)
                value = value[n:]
            }
        }
        display_begin_scissor(theme, panel, height)
        canvas_draw_text(theme, label, {panel.x + 12, panel.y + 9}, fg)
        if board.prompt_replace_all && len(board.prompt_text.buf) > 0 {
            selection_w := display_text_width(&theme.fonts[.BODY], value, &theme.font_metrics[.BODY])
            rl.DrawRectangleRec({panel.x + 12, panel.y + size + 15, selection_w, size}, display_selection_color(theme))
        }
        canvas_draw_text(theme, value, {panel.x + 12, panel.y + size + 15}, fg)
        canvas_draw_text(theme, board.message, {panel.x + 12, panel.y + 2 * size + 20}, theme.data.accent_color)
        rl.EndScissorMode()
    } else if message != "" {
        pos := [2]f32{12, f32(height) - size - 12}
        if canvas_editor_active(board) do pos.y -= editor_status_line_height(theme)
        panel := rl.Rectangle{0, pos.y - 5, f32(width), size + 20}
        rl.DrawRectangleRec(panel, rl.ColorLerp(bg, fg, 0.08))
        canvas_draw_text(theme, message, pos, fg)
    }
}
