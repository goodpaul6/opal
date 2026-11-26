package main

import "core:encoding/json"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

CANVAS_GROUP_HEADER :: 42
CANVAS_GROUP_PAD :: CANVAS_GRID_STEP
CANVAS_PARENT_KEY :: "opalParent"

Canvas_Group_Layout :: struct {
    width, saved_height, height, lift: f32,
    revision: u64,
    theme_zoom: int,
}

canvas_is_group :: proc(node: json.Object) -> bool {
    return canvas_string(node, "type") == "group"
}

canvas_group_title_height :: proc(theme: ^Theme, label: string, width: f32) -> f32 {
    preview := canvas_preview_text(label)
    height: f32
    display_command_gen(nil, theme, {max(1, width - 20), 0}, preview = &preview, layout_height = &height)
    return max(f32(CANVAS_GROUP_HEADER), height + 18)
}

canvas_group_header :: proc(board: ^Canvas, node: json.Object) -> rl.Rectangle {
    frame := canvas_positioned_node(board, node)
    height := f32(CANVAS_GROUP_HEADER)
    lift: f32
    if board != nil {
        index := board.node_indices[canvas_string(node, "id")]
        if index > 0 && index <= len(board.group_layouts) {
            layout := board.group_layouts[index - 1]
            height, lift = max(height, layout.height), layout.lift
        }
    }
    // Grow above the frame so a title change leaves its cards in place.
    return {frame.x, frame.y + min(frame.height, f32(CANVAS_GROUP_HEADER)) - height - lift, frame.width, height}
}

canvas_layout_group_titles :: proc(board: ^Canvas, ed: ^Editor, theme: ^Theme, screen: [2]f32) {
    nodes := canvas_items(board, "nodes")
    for item, i in nodes {
        node := item.(json.Object)
        if !canvas_is_group(node) do continue
        if len(board.group_layouts) < len(nodes) do resize(&board.group_layouts, len(nodes))
        layout := &board.group_layouts[i]
        width := canvas_positioned_node(board, node).width
        if width != layout.width || board.current.revision != layout.revision || theme.zoom_level != layout.theme_zoom {
            layout.saved_height = canvas_group_title_height(theme, canvas_string(node, "label"), width)
            layout.width, layout.revision, layout.theme_zoom = width, board.current.revision, theme.zoom_level
        }
        layout.height, layout.lift = layout.saved_height, 0
        if board.editing == i + 1 && !board.expanded {
            available := (screen.y - CANVAS_BAR - editor_status_line_height(theme) - 16) / board.zoom
            layout.height = min(canvas_group_title_height(theme, editor_get_text(ed), width),
                                max(f32(CANVAS_GROUP_HEADER), available))
        }
    }
    // Keep expanded subheadings below their ancestor's header.
    for layout, i in board.group_layouts {
        if layout.height <= CANVAS_GROUP_HEADER do continue
        header := canvas_group_header(board, nodes[i].(json.Object))
        parent := canvas_parent(board, i + 1)
        for parent != 0 {
            ancestor := nodes[parent - 1].(json.Object)
            frame := canvas_positioned_node(board, ancestor)
            parent_layout := &board.group_layouts[parent - 1]
            lift := frame.y + min(frame.height, f32(CANVAS_GROUP_HEADER)) + 8 - header.y
            if lift <= parent_layout.lift do break
            parent_layout.lift = lift
            header = canvas_group_header(board, ancestor)
            parent = canvas_parent(board, parent)
        }
    }
}

canvas_parent :: proc(board: ^Canvas, index: int) -> int {
    if index <= 0 || index > len(board.parents) do return 0
    return board.parents[index - 1]
}

canvas_has_ancestor :: proc(board: ^Canvas, index, ancestor: int) -> bool {
    if ancestor == 0 do return false
    parent := canvas_parent(board, index)
    for _ in 0..<len(board.parents) {
        if parent == 0 do return false
        if parent == ancestor do return true
        parent = canvas_parent(board, parent)
    }
    return false
}

canvas_set_parent :: proc(board: ^Canvas, node: ^json.Object, parent: int) {
    id := ""
    if parent != 0 do id = canvas_string(canvas_items(board, "nodes")[parent - 1].(json.Object), "id")
    canvas_set(node, CANVAS_PARENT_KEY, strings.clone(id))
}

canvas_reindex_parents :: proc(board: ^Canvas) {
    nodes := canvas_items(board, "nodes")
    resize(&board.parents, len(nodes))
    for item, i in nodes {
        parent := board.node_indices[canvas_string(item.(json.Object), CANVAS_PARENT_KEY)]
        if parent == i + 1 || (parent != 0 && !canvas_is_group(nodes[parent - 1].(json.Object))) {
            parent = 0
        }
        board.parents[i] = parent
    }
    // Imported extensions may contain cycles. Break them before traversal.
    for _, i in nodes {
        if canvas_has_ancestor(board, i + 1, i + 1) do board.parents[i] = 0
    }
}

canvas_contains_rect :: proc(outer, inner: rl.Rectangle) -> bool {
    return outer.x <= inner.x && outer.y <= inner.y &&
           outer.x + outer.width >= inner.x + inner.width && outer.y + outer.height >= inner.y + inner.height
}

canvas_enclosing_group :: proc(board: ^Canvas, rect: rl.Rectangle, index: int) -> int {
    parent := 0
    best_area := max(f32)
    for item, i in canvas_items(board, "nodes") {
        group := item.(json.Object)
        if i + 1 == index || !canvas_is_group(group) || canvas_has_ancestor(board, i + 1, index) do continue
        bounds := canvas_node_rect(group)
        area := bounds.width * bounds.height
        if area > rect.width * rect.height && area < best_area && canvas_contains_rect(bounds, rect) {
            parent, best_area = i + 1, area
        }
    }
    return parent
}

canvas_group_at :: proc(board: ^Canvas, point: [2]f32) -> int {
    parent := 0
    smallest := max(f32)
    for item, i in canvas_items(board, "nodes") {
        node := item.(json.Object)
        if !canvas_is_group(node) do continue
        rect := canvas_node_rect(node)
        area := rect.width * rect.height
        if area < smallest && rl.CheckCollisionPointRec(point, rect) {
            parent, smallest = i + 1, area
        }
    }
    return parent
}

canvas_space_in_group :: proc(board: ^Canvas, parent: int) -> [2]f32 {
    nodes := canvas_items(board, "nodes")
    group := canvas_node_rect(nodes[parent - 1].(json.Object))
    grid := f32(canvas_grid_step(board.zoom))
    x := math.ceil((group.x + CANVAS_GROUP_PAD) / grid) * grid
    y := math.ceil((group.y + CANVAS_GROUP_HEADER + CANVAS_GROUP_PAD) / grid) * grid
    for item, i in nodes {
        if canvas_parent(board, i + 1) != parent do continue
        other := canvas_node_rect(item.(json.Object))
        y = max(y, math.ceil((other.y + other.height + CANVAS_GROUP_PAD) / grid) * grid)
    }
    return {x, y}
}

canvas_import_groups :: proc(board: ^Canvas) {
    nodes := canvas_items(board, "nodes")
    has_groups := false
    for item in nodes {
        if canvas_is_group(item.(json.Object)) {
            has_groups = true
            break
        }
    }
    for item, i in nodes {
        node := item.(json.Object)
        if _, explicit := node[CANVAS_PARENT_KEY].(json.String); explicit do continue
        parent := canvas_enclosing_group(board, canvas_node_rect(node), i + 1) if has_groups else 0
        canvas_set_parent(board, &node, parent)
    }
    canvas_reindex_parents(board)
}

canvas_union_rect :: proc(a, b: rl.Rectangle) -> rl.Rectangle {
    left, top := min(a.x, b.x), min(a.y, b.y)
    right := max(a.x + a.width, b.x + b.width)
    bottom := max(a.y + a.height, b.y + b.height)
    return {left, top, right - left, bottom - top}
}

canvas_group_frame :: proc(rect: rl.Rectangle, grid: f32) -> rl.Rectangle {
    left := math.floor((rect.x - CANVAS_GROUP_PAD) / grid) * grid
    top := math.floor((rect.y - CANVAS_GROUP_HEADER - CANVAS_GROUP_PAD) / grid) * grid
    right := math.ceil((rect.x + rect.width + CANVAS_GROUP_PAD) / grid) * grid
    bottom := math.ceil((rect.y + rect.height + CANVAS_GROUP_PAD) / grid) * grid
    return {left, top, right - left, bottom - top}
}

canvas_set_node_rect :: proc(node: ^json.Object, rect: rl.Rectangle) {
    canvas_set(node, "x", i64(rect.x))
    canvas_set(node, "y", i64(rect.y))
    canvas_set(node, "width", i64(rect.width))
    canvas_set(node, "height", i64(rect.height))
}

canvas_grow_groups :: proc(board: ^Canvas, index: int) {
    node := canvas_items(board, "nodes")[index - 1].(json.Object)
    canvas_grow_group_bounds(board, canvas_parent(board, index), canvas_node_rect(node))
}

canvas_grow_group_bounds :: proc(board: ^Canvas, parent: int, child: rl.Rectangle) {
    nodes := canvas_items(board, "nodes")
    parent, child := parent, child
    for parent != 0 {
        group := nodes[parent - 1].(json.Object)
        padded := canvas_group_frame(child, f32(CANVAS_GRID_STEP))
        child = canvas_union_rect(canvas_node_rect(group), padded)
        canvas_set_node_rect(&group, child)
        parent = canvas_parent(board, parent)
    }
}

canvas_resize_minimum :: proc(board: ^Canvas, index: int) -> [2]i64 {
    minimum := [2]i64{CANVAS_MIN_CARD_W, CANVAS_MIN_CARD_H}
    nodes := canvas_items(board, "nodes")
    group := nodes[index - 1].(json.Object)
    if !canvas_is_group(group) do return minimum
    outer := canvas_node_rect(group)
    for item, i in nodes {
        if canvas_parent(board, i + 1) != index do continue
        child := canvas_node_rect(item.(json.Object))
        minimum.x = max(minimum.x, i64(child.x + child.width + CANVAS_GROUP_PAD - outer.x))
        minimum.y = max(minimum.y, i64(child.y + child.height + CANVAS_GROUP_PAD - outer.y))
    }
    return minimum
}

canvas_clear_visual :: proc(board: ^Canvas) {
    if board.visual do board.message = ""
    board.visual = false
    board.visual_anchor = 0
    board.visual_box = nil
    clear(&board.visual_nodes)
}

canvas_visual_contains :: proc(board: ^Canvas, index: int) -> bool {
    for selected in board.visual_nodes {
        if index == selected do return true
    }
    return false
}

canvas_mouse_pick :: proc(board: ^Canvas, index: int, toggle: bool) {
    if !board.visual && board.selected != 0 do append(&board.visual_nodes, board.selected)
    board.visual = true
    board.visual_anchor = 0
    board.visual_box = nil
    board.selected, board.selected_edge = index, 0
    for selected, i in board.visual_nodes {
        if selected != index do continue
        if toggle {
            ordered_remove(&board.visual_nodes, i)
            board.selected = board.visual_nodes[len(board.visual_nodes) - 1] if len(board.visual_nodes) > 0 else 0
            if board.selected == 0 do canvas_clear_visual(board)
        }
        return
    }
    append(&board.visual_nodes, index)
}

canvas_marquee_rect :: proc(a, b: [2]f32) -> rl.Rectangle {
    return {min(a.x, b.x), min(a.y, b.y), abs(a.x - b.x), abs(a.y - b.y)}
}

canvas_select_marquee :: proc(board: ^Canvas, rect: rl.Rectangle, additive := false) {
    if !additive do canvas_clear_visual(board)
    if additive && !board.visual && board.selected != 0 do append(&board.visual_nodes, board.selected)
    board.visual = true
    board.visual_anchor = 0
    board.visual_box = nil
    board.selected, board.selected_edge = 0, 0
    for item, i in canvas_items(board, "nodes") {
        if canvas_contains_rect(rect, canvas_rect(board, item.(json.Object))) && !canvas_visual_contains(board, i + 1) {
            append(&board.visual_nodes, i + 1)
        }
    }
    if len(board.visual_nodes) > 0 {
        board.selected = board.visual_nodes[0]
    } else {
        origin := ([2]f32{rect.x, rect.y} - board.pan) / board.zoom
        board.visual_box = rl.Rectangle{origin.x, origin.y, rect.width / board.zoom, rect.height / board.zoom}
    }
}

canvas_extend_visual :: proc(board: ^Canvas) {
    if board.visual_anchor == 0 || board.selected == 0 do return
    nodes := canvas_items(board, "nodes")
    a := canvas_node_rect(nodes[board.visual_anchor - 1].(json.Object))
    b := canvas_node_rect(nodes[board.selected - 1].(json.Object))
    rect := canvas_union_rect(a, b)
    clear(&board.visual_nodes)
    for item, i in nodes {
        if canvas_contains_rect(rect, canvas_node_rect(item.(json.Object))) do append(&board.visual_nodes, i + 1)
    }
}

canvas_collect_visual_members :: proc(board: ^Canvas, members: ^[dynamic]int) {
    if board.visual {
        for index in board.visual_nodes {
            nested := false
            for other in board.visual_nodes {
                if canvas_has_ancestor(board, index, other) {
                    nested = true
                    break
                }
            }
            if !nested do append(members, index)
        }
    } else if board.selected != 0 {
        append(members, board.selected)
    }
}

canvas_prepare_selection_drag :: proc(board: ^Canvas) {
    canvas_collect_visual_members(board, &board.drag_members)
    nodes := canvas_items(board, "nodes")
    resize(&board.drag_moved, len(nodes))
    for &moved in board.drag_moved do moved = false
    for member in board.drag_members do board.drag_moved[member - 1] = true
    for moved, i in board.drag_moved {
        if moved do continue
        parent := canvas_parent(board, i + 1)
        for parent != 0 {
            if board.drag_moved[parent - 1] {
                board.drag_moved[i] = true
                break
            }
            parent = canvas_parent(board, parent)
        }
    }
}

canvas_drag_moves_node :: proc(board: ^Canvas, index, source: int) -> bool {
    if len(board.drag_moved) != 0 do return index > 0 && board.drag_moved[index - 1]
    return index == source || canvas_has_ancestor(board, index, source)
}

canvas_drop_group_at :: proc(board: ^Canvas, point: [2]f32) -> int {
    target := 0
    smallest := max(f32)
    for item, i in canvas_items(board, "nodes") {
        node := item.(json.Object)
        if !canvas_is_group(node) || canvas_drag_moves_node(board, i + 1, board.selected) do continue
        rect := canvas_rect(board, node)
        area := rect.width * rect.height
        if area <= smallest && rl.CheckCollisionPointRec(point, rect) {
            target, smallest = i + 1, area
        }
    }
    return target
}

canvas_finish_selection_drag :: proc(board: ^Canvas, change: Canvas_Geometry, target: int) {
    if len(board.drag_members) == 0 && target == 0 {
        canvas_finish_move(board, change)
        return
    }
    nodes := canvas_items(board, "nodes")
    single := [1]int{change.node}
    members := board.drag_members[:] if len(board.drag_members) != 0 else single[:]
    source := nodes[change.node - 1].(json.Object)
    delta := change.values - [2]i64{source["x"].(json.Integer), source["y"].(json.Integer)}
    if delta == {} && target == 0 do return
    canvas_push_undo(board)
    dropped_bounds: Maybe(rl.Rectangle)
    for member in members {
        node := nodes[member - 1].(json.Object)
        start := [2]i64{node["x"].(json.Integer), node["y"].(json.Integer)}
        canvas_apply_geometry(board, {member, false, start + delta})
        rect := canvas_node_rect(node)
        parent := canvas_parent(board, member)
        new_parent := target
        if parent != 0 && (target == 0 || canvas_has_ancestor(board, member, target)) &&
           canvas_contains_rect(canvas_node_rect(nodes[parent - 1].(json.Object)), rect) {
            new_parent = parent
        }
        if new_parent != parent {
            canvas_set_parent(board, &node, new_parent)
            board.parents[member - 1] = new_parent
        }
        if new_parent == target && target != 0 {
            if previous, ok := dropped_bounds.?; ok do rect = canvas_union_rect(previous, rect)
            dropped_bounds = rect
        }
    }
    if rect, ok := dropped_bounds.?; ok do canvas_grow_group_bounds(board, target, rect)
}

canvas_create_group :: proc(board: ^Canvas, screen: [2]f32) -> int {
    nodes := canvas_items(board, "nodes")
    members := make([dynamic]int, context.temp_allocator)
    canvas_collect_visual_members(board, &members)

    grid := f32(canvas_grid_step(board.zoom))
    first := len(nodes)
    parent := 0
    bounds: rl.Rectangle
    if len(members) == 0 {
        if box, ok := board.visual_box.?; ok {
            x, y := math.floor(box.x / grid) * grid, math.floor(box.y / grid) * grid
            w := max(4 * grid, math.ceil((box.x + box.width) / grid) * grid - x)
            h := max(3 * grid, math.ceil((box.y + box.height) / grid) * grid - y)
            bounds = {x, y, w, h}
            parent = canvas_enclosing_group(board, bounds, 0)
        } else {
            w, h := 12 * grid, 7 * grid
            world_center := (canvas_view_center(screen) - board.pan) / board.zoom
            origin := canvas_round_to_grid(world_center - [2]f32{w, h} / 2, grid)
            bounds = {origin.x, origin.y, w, h}
        }
    } else {
        parent = canvas_parent(board, members[0])
        bounds = canvas_node_rect(nodes[members[0] - 1].(json.Object))
        for index in members {
            first = min(first, index - 1)
            if canvas_parent(board, index) != parent do parent = 0
            bounds = canvas_union_rect(bounds, canvas_node_rect(nodes[index - 1].(json.Object)))
        }
        bounds = canvas_group_frame(bounds, grid)
        if parent != 0 do first = max(first, parent)
    }

    canvas_push_undo(board)
    group := make(json.Object)
    id := canvas_new_id(board)
    canvas_set(&group, "id", id)
    canvas_set(&group, "type", strings.clone("group"))
    canvas_set(&group, "label", strings.clone("Group"))
    canvas_set_node_rect(&group, bounds)
    canvas_set_parent(board, &group, parent)
    for index in members {
        node := nodes[index - 1].(json.Object)
        canvas_set(&node, CANVAS_PARENT_KEY, strings.clone(id))
    }
    if first == len(nodes) {
        canvas_append(board, "nodes", group)
    } else {
        inject_at(&nodes, first, json.Value(group))
        board.current.document["nodes"] = nodes
    }
    canvas_reindex(board)
    group_index := board.node_indices[id]
    if parent != 0 do canvas_grow_groups(board, group_index)
    canvas_clear_visual(board)
    board.selected, board.selected_edge = group_index, 0
    return group_index
}

canvas_finish_move :: proc(board: ^Canvas, change: Canvas_Geometry) {
    node := canvas_items(board, "nodes")[change.node - 1].(json.Object)
    bounds := canvas_node_rect(node)
    if node["x"].(json.Integer) == change.values.x && node["y"].(json.Integer) == change.values.y do return
    bounds.x, bounds.y = f32(change.values.x), f32(change.values.y)
    parent := canvas_enclosing_group(board, bounds, change.node)
    if parent != canvas_parent(board, change.node) {
        canvas_push_undo(board)
        canvas_apply_geometry(board, change)
        canvas_set_parent(board, &node, parent)
        board.parents[change.node - 1] = parent
        if parent != 0 do canvas_grow_groups(board, change.node)
    } else {
        old, changed := canvas_apply_geometry(board, change)
        if changed do canvas_record_undo(board, old)
    }
}

canvas_finish_resize :: proc(board: ^Canvas, change: Canvas_Geometry) {
    nodes := canvas_items(board, "nodes")
    node := nodes[change.node - 1].(json.Object)
    if node["width"].(json.Integer) == change.values.x && node["height"].(json.Integer) == change.values.y do return
    if parent := canvas_parent(board, change.node); parent != 0 {
        bounds := canvas_node_rect(node)
        bounds.width, bounds.height = f32(change.values.x), f32(change.values.y)
        outer := canvas_node_rect(nodes[parent - 1].(json.Object))
        if !canvas_contains_rect(outer, bounds) {
            canvas_push_undo(board)
            canvas_apply_geometry(board, change)
            canvas_grow_groups(board, change.node)
            return
        }
    }
    old, changed := canvas_apply_geometry(board, change)
    if changed do canvas_record_undo(board, old)
}
