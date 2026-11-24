package main

import "core:encoding/json"
import "core:math"
import rl "vendor:raylib"

CANVAS_RESIZE_STEP :: 24
CANVAS_CARD_GAP :: 36

canvas_key_direction :: proc(key: rl.KeyboardKey, mode: Canvas_Key_Mode, mods: Editor_Key_Mod_State) -> [2]i32 {
    #partial switch key {
        case .H, .LEFT: return {-1, 0}
        case .J, .DOWN: return {0, 1}
        case .K, .UP: return {0, -1}
        case .L, .RIGHT: return {1, 0}
        case .B, .E:
            if mods == {} && (mode == .NORMAL || mode == .CONNECT) {
                return {-1 if key == .B else 1, 0}
            }
    }
    return {}
}

canvas_center :: proc(rect: rl.Rectangle) -> [2]f32 {
    return {rect.x + rect.width / 2, rect.y + rect.height / 2}
}

canvas_view_center :: proc(size: [2]f32) -> [2]f32 {
    return {size.x / 2, (size.y + CANVAS_BAR) / 2}
}

canvas_reveal_rect :: proc(board: ^Canvas, rect: rl.Rectangle, size: [2]f32) {
    margin :: 24
    low := [2]f32{margin, CANVAS_BAR + margin}
    high := size - margin
    start := [2]f32{rect.x, rect.y}
    extent := [2]f32{rect.width, rect.height}
    for axis in 0..<2 {
        if extent[axis] > high[axis] - low[axis] {
            board.pan[axis] += (low[axis] + high[axis] - extent[axis]) / 2 - start[axis]
        } else {
            board.pan[axis] += clamp(start[axis], low[axis], high[axis] - extent[axis]) - start[axis]
        }
    }
}

canvas_reveal_node :: proc(board: ^Canvas, index: int, size: [2]f32) {
    card := canvas_items(board, "nodes")[index - 1].(json.Object)
    canvas_reveal_rect(board, canvas_rect(board, card), size)
}

canvas_direction_score :: proc(delta: [2]f32, direction: [2]i32) -> f32 {
    distance := canvas_distance_squared(delta, {})
    if direction == {} do return distance
    dot := delta.x * f32(direction.x) + delta.y * f32(direction.y)
    if dot <= 0 do return max(f32)
    cross := delta.x * f32(direction.y) - delta.y * f32(direction.x)
    return distance + 3 * cross * cross
}

canvas_reveal_edge :: proc(board: ^Canvas, size: [2]f32) {
    edge := canvas_items(board, "edges")[board.selected_edge - 1].(json.Object)
    path, ok := canvas_edge_path(board, canvas_items(board, "nodes"), edge)
    if ok {
        midpoint := canvas_path_midpoint(path)
        canvas_reveal_rect(board, {midpoint.x - 40, midpoint.y - 14, 80, 28}, size)
    }
}

canvas_select_nearby_edge :: proc(board: ^Canvas, size: [2]f32) {
    edges := canvas_items(board, "edges")
    nodes := canvas_items(board, "nodes")
    point := canvas_view_center(size)
    card_id: string
    if board.selected != 0 {
        card := nodes[board.selected - 1].(json.Object)
        point = canvas_center(canvas_rect(board, card))
        card_id = canvas_string(card, "id")
    }
    next := 0
    nearest := max(f32)
    found_incident := false
    for item, i in edges {
        edge := item.(json.Object)
        incident := card_id != "" && (canvas_string(edge, "fromNode") == card_id || canvas_string(edge, "toNode") == card_id)
        if found_incident && !incident do continue
        path, ok := canvas_edge_path(board, nodes, edge)
        if !ok do continue
        score := canvas_distance_squared(canvas_path_midpoint(path), point)
        if score < nearest || (incident && !found_incident) {
            next, nearest, found_incident = i + 1, score, incident
        }
    }
    if next != 0 {
        board.selected, board.selected_edge = 0, next
        canvas_reveal_edge(board, size)
    }
}

canvas_select_in_direction :: proc(board: ^Canvas, direction: [2]i32, size: [2]f32, include_edges := false) {
    nodes := canvas_items(board, "nodes")
    edges := canvas_items(board, "edges")
    from := canvas_view_center(size)
    heading: [2]i32
    if board.selected != 0 {
        node := nodes[board.selected - 1].(json.Object)
        from, heading = canvas_center(canvas_rect(board, node)), direction
    } else if board.selected_edge != 0 {
        edge := edges[board.selected_edge - 1].(json.Object)
        path, ok := canvas_edge_path(board, nodes, edge)
        if ok do from, heading = canvas_path_midpoint(path), direction
    }

    next_node, next_edge := 0, 0
    distance := max(f32)
    for item, i in nodes {
        if board.selected == i + 1 do continue
        delta := canvas_center(canvas_rect(board, item.(json.Object))) - from
        d := canvas_direction_score(delta, heading)
        if d < distance {
            next_node, distance = i + 1, d
        }
    }
    if include_edges {
        for item, i in edges {
            if board.selected_edge == i + 1 do continue
            path, ok := canvas_edge_path(board, nodes, item.(json.Object))
            if !ok do continue
            d := canvas_direction_score(canvas_path_midpoint(path) - from, heading)
            if d < distance {
                next_edge, distance = i + 1, d
            }
        }
    }
    if next_edge != 0 {
        board.selected, board.selected_edge = 0, next_edge
        canvas_reveal_edge(board, size)
    } else if next_node != 0 {
        board.selected, board.selected_edge = next_node, 0
        canvas_reveal_node(board, next_node, size)
    }
}

canvas_adjacent_card :: proc(board: ^Canvas, from: int, side: Canvas_Side, size: [2]f32) -> [2]f32 {
    if from == 0 {
        return (canvas_view_center(size) - board.pan) / board.zoom - [2]f32{CANVAS_CARD_W / 2, CANVAS_CARD_H / 2}
    }
    nodes := canvas_items(board, "nodes")
    source := canvas_node_rect(nodes[from - 1].(json.Object))
    card := rl.Rectangle{source.x, source.y, CANVAS_CARD_W, CANVAS_CARD_H}
    switch side {
        case .TOP: card.y -= CANVAS_CARD_GAP + card.height
        case .BOTTOM: card.y += source.height + CANVAS_CARD_GAP
        case .LEFT: card.x -= CANVAS_CARD_GAP + card.width
        case .RIGHT: card.x += source.width + CANVAS_CARD_GAP
    }
    // Advance past an occupied slot while keeping the card in the same lane.
    for {
        blocked := false
        for item in nodes {
            other := canvas_node_rect(item.(json.Object))
            if !rl.CheckCollisionRecs(card, other) do continue
            blocked = true
            switch side {
                case .TOP: card.y = other.y - CANVAS_CARD_GAP - card.height
                case .BOTTOM: card.y = other.y + other.height + CANVAS_CARD_GAP
                case .LEFT: card.x = other.x - CANVAS_CARD_GAP - card.width
                case .RIGHT: card.x = other.x + other.width + CANVAS_CARD_GAP
            }
        }
        if !blocked do return {card.x, card.y}
    }
}

canvas_open_adjacent :: proc(board: ^Canvas, ed: ^Editor, side: Canvas_Side, size: [2]f32) {
    if board.selected == 0 do canvas_select_in_direction(board, {}, size)
    connect := board.connect_from
    from := connect if connect != 0 else board.selected
    point := canvas_adjacent_card(board, from, side, size)
    source_side := board.connect_source_side.? or_else side
    opposite := Canvas_Side((int(side) + 2) % 4)
    target_side := board.connect_target_side.? or_else opposite
    board.selected = canvas_add_card(board, i64(math.round(point.x)), i64(math.round(point.y)), connect, source_side, target_side)
    board.selected_edge = 0
    board.key_mode, board.connect_from = .NORMAL, 0
    canvas_reveal_node(board, board.selected, size)
    canvas_edit_card(board, ed, board.selected, true)
}

canvas_key_edge_anchors :: proc(board: ^Canvas) -> (a, b: rl.Rectangle, from_side, to_side: Canvas_Side) {
    nodes := canvas_items(board, "nodes")
    a = canvas_rect(board, nodes[board.connect_from - 1].(json.Object))
    b = canvas_rect(board, nodes[board.selected - 1].(json.Object))
    from_side = board.connect_source_side.? or_else canvas_edge_side(nil, "", a, canvas_center(b))
    to_side = board.connect_target_side.? or_else canvas_edge_side(nil, "", b, canvas_anchor(a, from_side))
    return
}

canvas_finish_key_move :: proc(board: ^Canvas) {
    previous, changed := canvas_apply_geometry(board, board.key_move)
    if changed do canvas_record_undo(board, previous)
    board.key_mode = .NORMAL
}

canvas_next_grid_line :: proc(value: i64, step: i64, direction: i32) -> i64 {
    remainder := value %% step
    if direction > 0 {
        delta := step - remainder
        return value + delta if value <= max(i64) - delta else value
    }
    delta := step if remainder == 0 else remainder
    return value - delta if value >= min(i64) + delta else value
}

canvas_keyboard_key :: proc(board: ^Canvas, ed: ^Editor, key: rl.KeyboardKey, mods: Editor_Key_Mod_State, size: [2]f32) -> bool {
    if editor_is_modifier_key(key) do return false
    if key == .ESCAPE {
        if board.key_mode == .NORMAL do board.selected, board.selected_edge = 0, 0
        if board.key_mode == .CONNECT {
            board.selected = board.connect_from
            canvas_reveal_node(board, board.selected, size)
        }
        board.key_mode, board.connect_from = .NORMAL, 0
        return true
    }
    if board.key_mode == .G_PREFIX {
        board.key_mode = .NORMAL
        if key == .C && mods == {} {
            if board.selected == 0 do canvas_select_in_direction(board, {}, size)
            if board.selected != 0 {
                board.key_mode = .CONNECT
                board.connect_from = board.selected
                board.connect_source_side, board.connect_target_side = nil, nil
            }
        }
        return true
    }

    if board.key_mode == .NORMAL && (.CMD in mods || .CTRL in mods) {
        #partial switch key {
            case .ENTER:
                if .SHIFT not_in mods || board.selected == 0 do return false
                canvas_edit_card(board, ed, board.selected)
                if board.editing != 0 do canvas_toggle_expanded(board, ed)
            case .S: canvas_request_save(board, ed)
            case .O: canvas_open_prompt(board, ed)
            case .Z: canvas_step_history(board, .SHIFT in mods)
            case .R:
                if .CTRL not_in mods do return false
                canvas_step_history(board, true)
            case: return false
        }
        return true
    }
    direction := canvas_key_direction(key, board.key_mode, mods)
    if board.key_mode == .CONNECT && direction != {} && (mods == {.ALT} || mods == {.SHIFT}) {
        side := Canvas_Side.TOP
        if direction.x < 0 do side = .LEFT
        else if direction.x > 0 do side = .RIGHT
        else if direction.y > 0 do side = .BOTTOM
        if .ALT in mods do board.connect_source_side = side
        else do board.connect_target_side = side
        return true
    }
    if mods - {.SHIFT} != {} do return false
    if direction != {} {
        if .SHIFT in mods {
            board.pan -= [2]f32{f32(direction.x), f32(direction.y)} * 90
        } else if board.key_mode == .MOVE || board.key_mode == .RESIZE {
            values := board.key_move.values
            if board.key_mode == .RESIZE {
                increments := [2]json.Integer{json.Integer(direction.x), json.Integer(direction.y)} * CANVAS_RESIZE_STEP
                minimum := [2]json.Integer{100, 68}
                for axis in 0..<2 {
                    if increments[axis] != 0 do values[axis] = max(min(minimum[axis], values[axis]), values[axis] + increments[axis])
                }
            } else {
                step := canvas_grid_step(board.zoom)
                for axis in 0..<2 {
                    if direction[axis] != 0 do values[axis] = canvas_next_grid_line(values[axis], step, direction[axis])
                }
            }
            board.key_move.values = values
            canvas_reveal_node(board, board.selected, size)
        } else {
            canvas_select_in_direction(board, direction, size, include_edges = board.key_mode == .NORMAL)
        }
        return true
    }

    if board.key_mode == .MOVE || board.key_mode == .RESIZE {
        if key == .ENTER do canvas_finish_key_move(board)
        return true
    }
    if key == .O || (key == .A && mods == {}) {
        side := Canvas_Side.RIGHT
        if key == .O do side = .TOP if .SHIFT in mods else .BOTTOM
        canvas_open_adjacent(board, ed, side, size)
        return true
    }
    if board.key_mode == .CONNECT {
        if key == .ENTER && board.selected != 0 && board.selected != board.connect_from {
            _, _, from_side, to_side := canvas_key_edge_anchors(board)
            canvas_connect(board, board.connect_from, board.selected, from_side, to_side)
            board.key_mode, board.connect_from = .NORMAL, 0
            board.selected, board.selected_edge = 0, len(canvas_items(board, "edges"))
        }
        return true
    }
    if key == .TAB {
        if board.selected_edge == 0 {
            canvas_select_nearby_edge(board, size)
            return true
        }
        count := len(canvas_items(board, "edges"))
        if count == 0 do return true
        if .SHIFT in mods {
            board.selected_edge = count if board.selected_edge <= 1 else board.selected_edge - 1
        } else {
            board.selected_edge = board.selected_edge % count + 1
        }
        canvas_reveal_edge(board, size)
        return true
    }
    if key == .F && mods == {.SHIFT} {
        canvas_frame_board(board, size)
        return true
    }
    if mods != {} do return false

    #partial switch key {
        case .I, .ENTER:
            if board.selected != 0 do canvas_edit_card(board, ed, board.selected, insert = key == .I)
            else if key == .ENTER && board.selected_edge != 0 {
                canvas_reveal_edge(board, size)
                canvas_label_prompt(board)
            }
            else if key == .I && len(canvas_items(board, "nodes")) == 0 do canvas_open_adjacent(board, ed, .RIGHT, size)
        case .G: board.key_mode = .G_PREFIX
        case .M, .R:
            if board.selected != 0 {
                card := canvas_items(board, "nodes")[board.selected - 1].(json.Object)
                resizing := key == .R
                x, y := canvas_geometry_keys(resizing)
                board.key_move = {board.selected, resizing, {card[x].(json.Integer), card[y].(json.Integer)}}
                board.key_mode = .RESIZE if resizing else .MOVE
            }
        case .BACKSPACE, .DELETE, .D, .X: canvas_remove_selected(board)
        case .F:
            if board.selected != 0 {
                node := canvas_items(board, "nodes")[board.selected - 1].(json.Object)
                board.pan += canvas_view_center(size) - canvas_center(canvas_rect(board, node))
            } else if board.selected_edge != 0 {
                edge := canvas_items(board, "edges")[board.selected_edge - 1].(json.Object)
                path, ok := canvas_edge_path(board, canvas_items(board, "nodes"), edge)
                if ok do board.pan += canvas_view_center(size) - canvas_path_midpoint(path)
            } else {
                canvas_frame_board(board, size, fit_zoom = false)
            }
        case .U: canvas_step_history(board, false)
        case: return false
    }
    return true
}
