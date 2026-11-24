package main

import "core:encoding/json"
import "core:math"
import rl "vendor:raylib"

Canvas_Edge_Path :: struct {
    points: [6][2]f32,
    count: int,
}

canvas_side_vector :: proc(side: Canvas_Side) -> [2]f32 {
    switch side {
        case .TOP: return {0, -1}
        case .RIGHT: return {1, 0}
        case .BOTTOM: return {0, 1}
        case .LEFT: return {-1, 0}
    }
    return {}
}

canvas_edge_path :: proc(board: ^Canvas, nodes: json.Array, edge: json.Object) -> (path: Canvas_Edge_Path, ok: bool) {
    from := board.node_indices[canvas_string(edge, "fromNode")]
    to := board.node_indices[canvas_string(edge, "toNode")]
    if from == 0 || to == 0 do return
    a := canvas_rect(board, nodes[from - 1].(json.Object))
    b := canvas_rect(board, nodes[to - 1].(json.Object))
    from_side := canvas_edge_side(edge, "fromSide", a, canvas_center(b))
    to_side := canvas_edge_side(edge, "toSide", b, canvas_center(a))
    return canvas_route_edge(a, b, from_side, to_side, board.zoom), true
}

// A straight connection is sufficient when both ports face it. For other
// pairs, keep the first and last segments perpendicular to the card borders.
canvas_route_edge :: proc(a, b: rl.Rectangle, from_side, to_side: Canvas_Side, zoom: f32) -> Canvas_Edge_Path {
    start, end := canvas_anchor(a, from_side), canvas_anchor(b, to_side)
    from_normal, to_normal := canvas_side_vector(from_side), canvas_side_vector(to_side)
    delta := end - start
    if delta.x * from_normal.x + delta.y * from_normal.y > 0 &&
       delta.x * to_normal.x + delta.y * to_normal.y < 0 {
        return {points = {start, end, {}, {}, {}, {}}, count = 2}
    }

    margin := max(12, 20 * zoom)
    p, q := start + from_normal * margin, end + to_normal * margin
    left, right := min(a.x, b.x) - margin, max(a.x + a.width, b.x + b.width) + margin
    top, bottom := min(a.y, b.y) - margin, max(a.y + a.height, b.y + b.height) + margin
    candidates := [6][2][2]f32{
        {{q.x, p.y}, {q.x, p.y}}, {{p.x, q.y}, {p.x, q.y}},
        {{left, p.y}, {left, q.y}}, {{right, p.y}, {right, q.y}},
        {{p.x, top}, {q.x, top}}, {{p.x, bottom}, {q.x, bottom}},
    }
    best := max(f32)
    path := Canvas_Edge_Path{points = {start, p, q, end, {}, {}}, count = 4}
    for bends in candidates {
        points := [6][2]f32{start, p, bends[0], bends[1], q, end}
        length: f32
        valid := true
        for i in 1..<4 {
            s, t := points[i], points[i + 1]
            if canvas_edge_segment_overlaps(s, t, a) || canvas_edge_segment_overlaps(s, t, b) {
                valid = false
                break
            }
            length += abs(t.x - s.x) + abs(t.y - s.y)
        }
        if valid && length < best {
            path, best = {points, len(points)}, length
        }
    }
    return path
}

canvas_edge_segment_overlaps :: proc(a, b: [2]f32, rect: rl.Rectangle) -> bool {
    return max(a.x, b.x) > rect.x && min(a.x, b.x) < rect.x + rect.width &&
           max(a.y, b.y) > rect.y && min(a.y, b.y) < rect.y + rect.height
}

canvas_path_midpoint :: proc(path: Canvas_Edge_Path) -> [2]f32 {
    if path.count == 2 do return (path.points[0] + path.points[1]) / 2
    lengths: [5]f32
    total: f32
    for i in 0..<path.count - 1 {
        lengths[i] = math.sqrt(canvas_distance_squared(path.points[i], path.points[i + 1]))
        total += lengths[i]
    }
    remaining := total / 2
    for i in 0..<path.count - 1 {
        if lengths[i] > 0 && remaining <= lengths[i] {
            return path.points[i] + (path.points[i + 1] - path.points[i]) * (remaining / lengths[i])
        }
        remaining -= lengths[i]
    }
    return path.points[0]
}

canvas_hit_path :: proc(path: Canvas_Edge_Path, point: [2]f32) -> bool {
    for i in 0..<path.count - 1 {
        a, b := path.points[i], path.points[i + 1]
        if a != b && rl.CheckCollisionPointLine(point, a, b, 7) do return true
    }
    return false
}

canvas_connection_target :: proc(board: ^Canvas, nodes: json.Array, point: [2]f32) -> (int, Canvas_Side) {
    if point.y < CANVAS_BAR do return 0, {}
    for i := len(nodes) - 1; i >= 0; i -= 1 {
        if i + 1 == board.selected do continue
        rect := canvas_rect(board, nodes[i].(json.Object))
        side := canvas_edge_side(nil, "", rect, point)
        if rl.CheckCollisionPointRec(point, rect) || canvas_distance_squared(point, canvas_anchor(rect, side)) <= 64 {
            return i + 1, side
        }
    }
    return 0, {}
}
