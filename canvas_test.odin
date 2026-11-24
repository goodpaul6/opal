package main

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_canvas_commands_work_without_a_selection :: proc(t: ^testing.T) {
    dir, err := os.make_directory_temp("", "opal-canvas-commands-*", context.temp_allocator)
    if !testing.expect(t, err == nil) do return
    defer os.remove_all(dir)
    path := os.join_path({dir, "new board.canvas"}, context.temp_allocator) or_else ""
    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    ed: Editor
    size := [2]f32{800, 450}
    canvas_add_card(&board, 0, 0)

    testing.expect(t, canvas_keyboard_key(&board, &ed, .SEMICOLON, {.SHIFT}, size))
    testing.expect_value(t, board.prompt, Canvas_Prompt.COMMAND)
    canvas_prompt_insert(&board, transmute([]byte)fmt.tprintf("w \"%s\"", path))
    canvas_prompt_input(&board, &ed, {.ENTER}, {}, {})
    testing.expect_value(t, board.prompt, Canvas_Prompt.NONE)
    testing.expect(t, os.exists(path))
    testing.expect(t, !canvas_dirty(&board, &ed))

    canvas_add_card(&board, 252, 0)
    canvas_keyboard_key(&board, &ed, .SEMICOLON, {.SHIFT}, size)
    canvas_prompt_input(&board, &ed, {.ENTER}, {'q'}, {})
    testing.expect_value(t, board.prompt, Canvas_Prompt.CLOSE)
    testing.expect(t, !board.exit_requested)
    canvas_prompt_input(&board, &ed, {.ESCAPE}, {}, {})
    canvas_keyboard_key(&board, &ed, .SEMICOLON, {.SHIFT}, size)
    canvas_prompt_input(&board, &ed, {.ENTER}, {'w', 'q'}, {})
    testing.expect(t, !canvas_dirty(&board, &ed))
    testing.expect(t, board.exit_requested)
}

@(test)
test_canvas_open_dirty_board_offers_save_and_discard :: proc(t: ^testing.T) {
    dir, err := os.make_directory_temp("", "opal-canvas-open-*", context.temp_allocator)
    if !testing.expect(t, err == nil) do return
    defer os.remove_all(dir)
    next := os.join_path({dir, "next.canvas"}, context.temp_allocator) or_else ""
    prior := os.join_path({dir, "prior.canvas"}, context.temp_allocator) or_else ""
    missing := os.join_path({dir, "missing.canvas"}, context.temp_allocator) or_else ""
    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    ed: Editor
    size := [2]f32{800, 450}
    canvas_add_card(&board, 0, 0)
    if !testing.expect(t, canvas_save(&board, next)) do return
    draft: Canvas
    canvas_init(&draft)
    defer canvas_destroy(&draft)
    canvas_add_card(&draft, 0, 0)
    canvas_add_card(&draft, 252, 0)

    canvas_open_prompt(&draft)
    canvas_prompt_insert(&draft, transmute([]byte)next)
    canvas_prompt_input(&draft, &ed, {.ENTER}, {}, {})
    testing.expect_value(t, draft.prompt, Canvas_Prompt.CONFIRM_OPEN)
    canvas_prompt_input(&draft, &ed, {.ESCAPE}, {}, {})
    testing.expect_value(t, draft.pending_open, "")
    testing.expect_value(t, len(canvas_items(&draft, "nodes")), 2)

    canvas_keyboard_key(&draft, &ed, .SEMICOLON, {.SHIFT}, size)
    canvas_prompt_insert(&draft, transmute([]byte)fmt.tprintf("e! \"%s\"", missing))
    canvas_prompt_input(&draft, &ed, {.ENTER}, {}, {})
    testing.expect_value(t, draft.prompt, Canvas_Prompt.NONE)
    testing.expect_value(t, len(canvas_items(&draft, "nodes")), 2)
    testing.expect(t, canvas_dirty(&draft, &ed))

    canvas_open_prompt(&draft)
    canvas_prompt_insert(&draft, transmute([]byte)next)
    canvas_prompt_input(&draft, &ed, {.ENTER}, {}, {})
    canvas_prompt_input(&draft, &ed, {.ENTER}, {}, {})
    testing.expect_value(t, draft.prompt, Canvas_Prompt.SAVE)
    canvas_prompt_insert(&draft, transmute([]byte)prior)
    canvas_prompt_input(&draft, &ed, {.ENTER}, {}, {})
    testing.expect(t, os.exists(prior))
    testing.expect_value(t, len(canvas_items(&draft, "nodes")), 1)
    testing.expect_value(t, draft.pending_open, "")

    canvas_add_card(&draft, 252, 0)
    canvas_open_prompt(&draft)
    canvas_prompt_insert(&draft, transmute([]byte)next)
    canvas_prompt_input(&draft, &ed, {.ENTER}, {}, {})
    canvas_prompt_input(&draft, &ed, {.D}, {}, {})
    testing.expect_value(t, len(canvas_items(&draft, "nodes")), 1)
    testing.expect(t, !canvas_dirty(&draft, &ed))

    canvas_add_card(&draft, 252, 0)
    canvas_add_card(&draft, 504, 0)
    canvas_keyboard_key(&draft, &ed, .SEMICOLON, {.SHIFT}, size)
    canvas_prompt_insert(&draft, transmute([]byte)fmt.tprintf("e! \"%s\"", prior))
    canvas_prompt_input(&draft, &ed, {.ENTER}, {}, {})
    testing.expect_value(t, draft.prompt, Canvas_Prompt.NONE)
    testing.expect_value(t, len(canvas_items(&draft, "nodes")), 2)
    testing.expect(t, !canvas_dirty(&draft, &ed))
}

@(test)
test_canvas_markdown_cards_round_trip :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "opal-canvas-*", context.temp_allocator)
    if !testing.expect(t, dir_err == nil) do return
    defer os.remove_all(dir)
    path := os.join_path({dir, "draft.canvas"}, context.temp_allocator) or_else ""

    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    first := canvas_add_card(&board, -120, 50)
    second := canvas_add_card(&board, 180, 70)
    canvas_connect(&board, first, second, .RIGHT, .LEFT)

    ed: Editor
    board.selected_edge = 1
    canvas_edit_edge(&board, &ed, 1)
    testing.expect_value(t, board.editing_edge, 1)
    testing.expect_value(t, ed.mode, Editor_Mode.INSERT)
    editor_begin_frame(&ed)
    label := [?]rune{'C', 'a', 'f', 'é'}
    for ch in label do editor_handle_charpress(&ed, ch)
    editor_handle_keypress(&ed, .ENTER, {})
    editor_handle_charpress(&ed, '2')
    editor_end_frame(&ed)
    canvas_finish_editing(&board, &ed)
    canvas_step_history(&board, false)
    testing.expect_value(t, canvas_string(canvas_items(&board, "edges")[0].(json.Object), "label"), "")
    canvas_step_history(&board, true)

    canvas_edit_card(&board, &ed, first, true)
    testing.expect(t, !board.expanded)
    testing.expect_value(t, canvas_editor_bounds(&board), rl.Rectangle{-110, 59, CANVAS_CARD_W - 20, CANVAS_CARD_H - 18})
    editor_begin_frame(&ed)
    editor_insert_text(&ed, "# Outline\n\nA **draft** with café.\n")
    caret := ed.state.selection
    canvas_toggle_expanded(&board, &ed)
    testing.expect(t, board.expanded)
    canvas_toggle_expanded(&board, &ed)
    testing.expect(t, !board.expanded)
    testing.expect_value(t, ed.mode, Editor_Mode.INSERT)
    testing.expect_value(t, ed.state.selection, caret)
    editor_handle_keypress(&ed, .ESCAPE, {})
    editor_handle_keypress(&ed, .U, {})
    testing.expect_value(t, editor_get_text(&ed), "")
    editor_handle_keypress(&ed, .R, {.CTRL})
    editor_end_frame(&ed)
    testing.expect(t, canvas_dirty(&board, &ed))
    canvas_finish_editing(&board, &ed)

    if !testing.expect(t, canvas_save(&board, path)) do return
    testing.expect(t, !canvas_dirty(&board, &ed))

    loaded: Canvas
    canvas_init(&loaded)
    defer canvas_destroy(&loaded)
    if !testing.expect(t, canvas_open(&loaded, path)) do return
    nodes := canvas_items(&loaded, "nodes")
    edges := canvas_items(&loaded, "edges")
    if !testing.expect_value(t, len(nodes), 2) || !testing.expect_value(t, len(edges), 1) do return
    testing.expect_value(t, canvas_coord(nodes[0].(json.Object), "x"), f32(-120))
    testing.expect_value(t, canvas_string(nodes[1].(json.Object), "text"), "")
    testing.expect_value(t, canvas_string(edges[0].(json.Object), "toNode"),
                         canvas_string(nodes[1].(json.Object), "id"))
    testing.expect_value(t, canvas_string(edges[0].(json.Object), "label"), "Café\n2")
    loaded.selected_edge = 1
    canvas_edit_edge(&loaded, &ed, 1)
    testing.expect_value(t, editor_get_text(&ed), "Café\n2")
    editor_begin_frame(&ed)
    ed.state.selection = {0, len(ed.sb.buf)}
    editor_delete_selection(&ed)
    editor_end_frame(&ed)
    canvas_finish_editing(&loaded, &ed)
    testing.expect_value(t, canvas_string(edges[0].(json.Object), "label"), "")
    canvas_step_history(&loaded, false)
    canvas_edit_card(&loaded, &ed, first)
    testing.expect_value(t, ed.mode, Editor_Mode.NORMAL)
    testing.expect_value(t, editor_get_text(&ed), "# Outline\n\nA **draft** with café.\n")
    canvas_finish_editing(&loaded, &ed)

    loaded.selected = second
    testing.expect(t, canvas_keyboard_key(&loaded, &ed, .D, {}, {800, 450}))
    testing.expect_value(t, len(canvas_items(&loaded, "nodes")), 1)
    testing.expect_value(t, len(canvas_items(&loaded, "edges")), 0)
    canvas_step_history(&loaded, false)
    testing.expect_value(t, len(canvas_items(&loaded, "nodes")), 2)
    testing.expect_value(t, len(canvas_items(&loaded, "edges")), 1)
    testing.expect(t, !canvas_dirty(&loaded, &ed))
    canvas_step_history(&loaded, true)
    testing.expect(t, canvas_dirty(&loaded, &ed))
    if !testing.expect(t, canvas_save(&loaded, path)) do return
    testing.expect(t, !canvas_save(&board, path)) // The other editor changed the saved version.
}

@(test)
test_canvas_move_resize_and_zoom_do_not_allocate :: proc(t: ^testing.T) {
    tracking: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking, context.allocator)
    defer mem.tracking_allocator_destroy(&tracking)
    context.allocator = mem.tracking_allocator(&tracking)
    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    node := canvas_add_card(&board, 10, 20)

    allocations := tracking.total_allocation_count
    for i in 1..=128 {
        canvas_drag_geometry(&board, {node, false, {json.Integer(10 + i), 20}})
        canvas_zoom_at(&board, {200, 150}, -1 if i % 2 == 0 else 1)
    }
    board.drag_recorded = false
    canvas_drag_geometry(&board, {node, true, {320, 150}})
    canvas_drag_geometry(&board, {node, true, {325, 155}})
    testing.expect_value(t, tracking.total_allocation_count - allocations, i64(0))
    card := canvas_items(&board, "nodes")[0].(json.Object)
    testing.expect_value(t, len(board.undo), 3)
    testing.expect_value(t, canvas_coord(card, "x"), f32(138))
    testing.expect_value(t, canvas_coord(card, "width"), f32(325))
    canvas_step_history(&board, false)
    testing.expect_value(t, canvas_coord(card, "width"), f32(252))
    canvas_step_history(&board, false)
    testing.expect_value(t, canvas_coord(card, "x"), f32(10))
    canvas_step_history(&board, false)
    testing.expect_value(t, len(canvas_items(&board, "nodes")), 0)
    for _ in 0..<3 do canvas_step_history(&board, true)
    testing.expect_value(t, canvas_coord(card, "x"), f32(138))
    testing.expect_value(t, canvas_coord(card, "width"), f32(325))
}

@(test)
test_canvas_rasters_wait_for_zoom_to_settle_and_reuse_recent_sizes :: proc(t: ^testing.T) {
    board: Canvas
    board.zoom = 1
    theme := Theme{pixel_scale = {2, 2}}
    theme.fonts[.BODY].baseSize = 20
    canvas_zoom_at(&board, {200, 150}, 1, 10)
    testing.expect(t, board.zoom_settle_at > 10)
    testing.expect(t, canvas_render_rasters(&board, &theme) == nil)

    board.zoom_settle_at = 0
    first_zoom := board.zoom
    first := canvas_render_rasters(&board, &theme)
    if !testing.expect(t, first != nil) do return
    testing.expect_value(t, first.body_pixels, i32(46))
    testing.expect(t, first.prepare)
    canvas_zoom_at(&board, {200, 150}, 1, 11)
    testing.expect(t, canvas_render_rasters(&board, &theme) == first && !first.prepare)

    board.zoom_settle_at = 0
    second := canvas_render_rasters(&board, &theme)
    testing.expect(t, second != nil && second != first)
    board.zoom = first_zoom
    testing.expect(t, canvas_render_rasters(&board, &theme) == first && first.prepare)
}

@(test)
test_canvas_preserves_imported_fields :: proc(t: ^testing.T) {
    input :: `{
        "nodes": [
            {"id":"image","type":"file","x":-5,"y":10,"width":240,"height":80,"file":"sketch.png","color":"4"},
            {"id":"idea","type":"text","x":260,"y":10,"width":200,"height":100,"text":"## Idea","extension":{"tag":"keep"}}
        ],
        "edges":[{"id":"link","fromNode":"image","toNode":"idea","label":"notes"}],
        "extension":true
    }`
    document, ok := canvas_parse(transmute([]byte)string(input))
    if !testing.expect(t, ok) do return
    defer json.destroy_value(document)
    encoded, err := json.marshal(document, {spec = .JSON}, context.temp_allocator)
    if !testing.expect(t, err == nil) do return
    round_trip, valid := canvas_parse(encoded)
    if !testing.expect(t, valid) do return
    defer json.destroy_value(round_trip)
    nodes := round_trip["nodes"].(json.Array)
    testing.expect_value(t, canvas_string(nodes[0].(json.Object), "file"), "sketch.png")
    extra := nodes[1].(json.Object)["extension"].(json.Object)
    testing.expect_value(t, canvas_string(extra, "tag"), "keep")
    testing.expect_value(t, round_trip["extension"].(json.Boolean), true)
}

@(test)
test_canvas_keyboard_opens_inline_or_expanded :: proc(t: ^testing.T) {
    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    ed: Editor
    defer if board.editing != 0 do canvas_finish_editing(&board, &ed)

    screen := [2]f32{800, 450}
    board.zoom, board.pan = 0.5, {401.5, 237.25}
    testing.expect(t, canvas_keyboard_key(&board, &ed, .I, {}, screen))
    testing.expect_value(t, len(canvas_items(&board, "nodes")), 1)
    testing.expect_value(t, board.selected, 1)
    testing.expect_value(t, board.editing, 1)
    testing.expect_value(t, ed.mode, Editor_Mode.INSERT)
    testing.expect(t, !board.expanded)
    testing.expect_value(t, board.zoom, f32(0.5))
    grid := canvas_grid_step(board.zoom)
    node := canvas_active_card(&board)
    for key in ([?]string{"x", "y", "width", "height"}) {
        testing.expect_value(t, node[key].(json.Integer) %% grid, i64(0))
    }
    screen_step := f32(grid) * board.zoom
    view_grid := (board.pan - [2]f32{0, CANVAS_BAR}) / screen_step
    testing.expect_value(t, view_grid, canvas_round_to_grid(view_grid, 1))
    offset := canvas_center(canvas_rect(&board, node)) - canvas_view_center(screen)
    testing.expect(t, abs(offset.x) <= screen_step / 2 && abs(offset.y) <= screen_step / 2)

    canvas_finish_editing(&board, &ed)
    testing.expect(t, canvas_keyboard_key(&board, &ed, .ENTER, {.CMD, .SHIFT}, {800, 450}))
    testing.expect_value(t, len(canvas_items(&board, "nodes")), 1)
    testing.expect_value(t, board.editing, 1)
    testing.expect_value(t, ed.mode, Editor_Mode.NORMAL)
    testing.expect(t, board.expanded)

    canvas_finish_editing(&board, &ed)
    testing.expect(t, canvas_keyboard_key(&board, &ed, .A, {}, screen))
    testing.expect_value(t, board.editing, 2)
    right := canvas_node_rect(canvas_active_card(&board))
    first := canvas_node_rect(node)
    testing.expect_value(t, right.y, first.y)
    testing.expect_value(t, [2]f32{right.width, right.height}, [2]f32{first.width, first.height})
    testing.expect_value(t, i64(right.x) %% grid, i64(0))
    testing.expect(t, right.x > first.x + first.width)
}

@(test)
test_canvas_focus_centers_without_zooming :: proc(t: ^testing.T) {
    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    ed: Editor
    size := [2]f32{584, 412}
    canvas_add_card(&board, 0, 0)
    board.selected = canvas_add_card(&board, 600, 90)
    board.fit = false
    board.zoom = 1.5
    canvas_connect(&board, 1, 2, .RIGHT, .LEFT)
    node := canvas_items(&board, "nodes")[board.selected - 1].(json.Object)
    revision := board.current.revision

    canvas_keyboard_key(&board, &ed, .F, {}, size)
    testing.expect_value(t, board.zoom, f32(1.5))
    testing.expect_value(t, canvas_center(canvas_rect(&board, node)), canvas_view_center(size))
    testing.expect_value(t, board.selected, 2)
    testing.expect_value(t, board.current.revision, revision)

    canvas_keyboard_key(&board, &ed, .ESCAPE, {}, size)
    board.selected_edge = 1
    canvas_keyboard_key(&board, &ed, .F, {}, size)
    edge := canvas_items(&board, "edges")[0].(json.Object)
    path, ok := canvas_edge_path(&board, canvas_items(&board, "nodes"), edge)
    testing.expect(t, ok)
    testing.expect_value(t, canvas_path_midpoint(path), canvas_view_center(size))
    testing.expect_value(t, board.zoom, f32(1.5))

    canvas_keyboard_key(&board, &ed, .ESCAPE, {}, size)
    canvas_keyboard_key(&board, &ed, .F, {}, size)
    testing.expect_value(t, board.zoom, f32(1.5))
    canvas_keyboard_key(&board, &ed, .F, {.SHIFT}, size)
    testing.expect(t, board.zoom < 1)
    testing.expect_value(t, board.selected, 0)
}

@(test)
test_canvas_keyboard_navigation_nudge_and_cancel :: proc(t: ^testing.T) {
    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    ed: Editor
    size := [2]f32{800, 450}
    root := canvas_add_card(&board, 50, 100)
    right := canvas_add_card(&board, 900, 100)
    canvas_add_card(&board, 50, 300)
    board.selected = root

    canvas_keyboard_key(&board, &ed, .E, {}, size)
    testing.expect_value(t, board.selected, right)
    testing.expect(t, board.pan.x < 0)
    canvas_keyboard_key(&board, &ed, .B, {}, size)
    testing.expect_value(t, board.selected, root)
    canvas_keyboard_key(&board, &ed, .L, {}, size)
    testing.expect_value(t, board.selected, right)
    card := canvas_items(&board, "nodes")[right - 1].(json.Object)
    screen_x := canvas_rect(&board, card).x
    canvas_keyboard_key(&board, &ed, .M, {}, size)
    canvas_keyboard_key(&board, &ed, .H, {}, size)
    testing.expect_value(t, canvas_rect(&board, card).x, screen_x - 4)
    testing.expect_value(t, canvas_coord(card, "x"), f32(900))
    canvas_keyboard_key(&board, &ed, .ESCAPE, {}, size)
    testing.expect_value(t, canvas_rect(&board, card).x, screen_x)

    previous_undo := len(board.undo)
    canvas_keyboard_key(&board, &ed, .M, {}, size)
    canvas_keyboard_key(&board, &ed, .H, {}, size)
    canvas_keyboard_key(&board, &ed, .H, {}, size)
    canvas_keyboard_key(&board, &ed, .ENTER, {}, size)
    testing.expect_value(t, len(board.undo), previous_undo + 1)
    testing.expect_value(t, canvas_coord(card, "x"), f32(868))
    canvas_keyboard_key(&board, &ed, .U, {}, size)
    testing.expect_value(t, canvas_coord(card, "x"), f32(900))
}

@(test)
test_canvas_keyboard_creates_and_connects_markdown_cards :: proc(t: ^testing.T) {
    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    ed: Editor
    size := [2]f32{800, 450}
    root := canvas_add_card(&board, 50, 200)
    board.selected = root
    canvas_keyboard_key(&board, &ed, .O, {.SHIFT}, size)
    testing.expect_value(t, ed.mode, Editor_Mode.INSERT)
    nodes := canvas_items(&board, "nodes")
    above := nodes[1].(json.Object)
    testing.expect_value(t, canvas_coord(above, "x"), f32(56))
    testing.expect_value(t, canvas_coord(above, "y"), f32(0))

    editor_begin_frame(&ed)
    editor_handle_keypress(&ed, .ESCAPE, {})
    testing.expect(t, !board.finish_editing)
    editor_handle_keypress(&ed, .ESCAPE, {})
    testing.expect(t, board.finish_editing)
    editor_end_frame(&ed)
    canvas_finish_editing(&board, &ed)
    canvas_keyboard_key(&board, &ed, .J, {}, size)
    testing.expect_value(t, board.selected, root)
    canvas_keyboard_key(&board, &ed, .G, {}, size)
    canvas_keyboard_key(&board, &ed, .C, {}, size)
    testing.expect_value(t, board.key_mode, Canvas_Key_Mode.CONNECT)
    canvas_keyboard_key(&board, &ed, .K, {.SHIFT}, size)
    canvas_keyboard_key(&board, &ed, .A, {}, size)
    testing.expect_value(t, ed.mode, Editor_Mode.INSERT)
    testing.expect_value(t, board.key_mode, Canvas_Key_Mode.NORMAL)
    canvas_finish_editing(&board, &ed)

    nodes = canvas_items(&board, "nodes")
    right := nodes[2].(json.Object)
    edges := canvas_items(&board, "edges")
    if !testing.expect_value(t, len(edges), 1) do return
    edge := edges[0].(json.Object)
    testing.expect_value(t, canvas_coord(right, "x"), f32(364))
    testing.expect_value(t, canvas_string(edge, "toNode"), canvas_string(right, "id"))
    testing.expect_value(t, canvas_string(edge, "fromSide"), "right")
    testing.expect_value(t, canvas_string(edge, "toSide"), "top")

    canvas_keyboard_key(&board, &ed, .U, {}, size)
    testing.expect_value(t, len(canvas_items(&board, "nodes")), 2)
    testing.expect_value(t, len(canvas_items(&board, "edges")), 0)
    canvas_keyboard_key(&board, &ed, .R, {.CTRL}, size)
    testing.expect_value(t, len(canvas_items(&board, "nodes")), 3)
    testing.expect_value(t, len(canvas_items(&board, "edges")), 1)

    board.selected = root
    canvas_keyboard_key(&board, &ed, .G, {}, size)
    canvas_keyboard_key(&board, &ed, .C, {}, size)
    canvas_keyboard_key(&board, &ed, .E, {}, size)
    testing.expect_value(t, board.selected, 3)
    canvas_keyboard_key(&board, &ed, .B, {}, size)
    testing.expect_value(t, board.selected, root)
    canvas_keyboard_key(&board, &ed, .K, {}, size)
    canvas_keyboard_key(&board, &ed, .L, {.ALT}, size)
    canvas_keyboard_key(&board, &ed, .H, {.SHIFT}, size)
    canvas_keyboard_key(&board, &ed, .ENTER, {}, size)
    testing.expect_value(t, len(canvas_items(&board, "edges")), 2)
    new_edge := canvas_items(&board, "edges")[1].(json.Object)
    testing.expect_value(t, canvas_string(new_edge, "fromSide"), "right")
    testing.expect_value(t, canvas_string(new_edge, "toSide"), "left")
    testing.expect_value(t, board.selected_edge, 2)
    canvas_keyboard_key(&board, &ed, .TAB, {}, size)
    canvas_keyboard_key(&board, &ed, .ENTER, {}, size)
    testing.expect_value(t, board.editing_edge, 1)
    testing.expect_value(t, board.selected_edge, 1)
    canvas_finish_editing(&board, &ed)
    canvas_keyboard_key(&board, &ed, .D, {}, size)
    testing.expect_value(t, len(canvas_items(&board, "nodes")), 3)
    testing.expect_value(t, len(canvas_items(&board, "edges")), 1)
}

@(test)
test_canvas_mouse_can_choose_far_side_of_a_card :: proc(t: ^testing.T) {
    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    board.selected = canvas_add_card(&board, 20, 100)
    target := canvas_add_card(&board, 400, 100)
    nodes := canvas_items(&board, "nodes")
    a := canvas_rect(&board, nodes[0].(json.Object))
    b := canvas_rect(&board, nodes[1].(json.Object))
    index, top := canvas_connection_target(&board, nodes, canvas_anchor(b, .TOP) - [2]f32{0, 3})
    testing.expect_value(t, index, target)
    testing.expect_value(t, top, Canvas_Side.TOP)
    dest, right := canvas_connection_target(&board, nodes, canvas_anchor(b, .RIGHT) + [2]f32{3, 0})
    testing.expect_value(t, dest, target)
    testing.expect_value(t, right, Canvas_Side.RIGHT)
    path := canvas_route_edge(a, b, .RIGHT, right, board.zoom)
    testing.expect_value(t, path.points[path.count - 1], canvas_anchor(b, .RIGHT))
    testing.expect(t, path.points[path.count - 2].x > b.x + b.width)
    for i in 0..<path.count - 1 {
        testing.expect(t, !canvas_edge_segment_overlaps(path.points[i], path.points[i + 1], a))
        testing.expect(t, !canvas_edge_segment_overlaps(path.points[i], path.points[i + 1], b))
    }
    testing.expect(t, canvas_hit_path(path, canvas_path_midpoint(path)))
}

@(test)
test_canvas_navigation_crosses_cards_and_arrows :: proc(t: ^testing.T) {
    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    ed: Editor
    screen := [2]f32{800, 450}
    left := canvas_add_card(&board, 0, 210)
    middle := canvas_add_card(&board, 360, 210)
    right := canvas_add_card(&board, 850, 210)
    above := canvas_add_card(&board, 360, -200)
    canvas_connect(&board, middle, right, .RIGHT, .LEFT)
    canvas_connect(&board, left, middle, .RIGHT, .LEFT)
    canvas_connect(&board, above, middle, .BOTTOM, .TOP)

    board.selected = left
    canvas_keyboard_key(&board, &ed, .E, {}, screen)
    testing.expect_value(t, board.selected_edge, 2)
    canvas_keyboard_key(&board, &ed, .L, {}, screen)
    testing.expect_value(t, board.selected, middle)
    canvas_keyboard_key(&board, &ed, .E, {}, screen)
    testing.expect_value(t, board.selected_edge, 1)
    canvas_keyboard_key(&board, &ed, .B, {}, screen)
    testing.expect_value(t, board.selected, middle)
    canvas_keyboard_key(&board, &ed, .K, {}, screen)
    testing.expect_value(t, board.selected_edge, 3)
    canvas_keyboard_key(&board, &ed, .UP, {}, screen)
    testing.expect_value(t, board.selected, above)
    canvas_keyboard_key(&board, &ed, .J, {}, screen)
    testing.expect_value(t, board.selected_edge, 3)
    canvas_keyboard_key(&board, &ed, .DOWN, {}, screen)
    testing.expect_value(t, board.selected, middle)
    canvas_keyboard_key(&board, &ed, .H, {}, screen)
    testing.expect_value(t, board.selected_edge, 2)
    testing.expect_value(t, board.key_mode, Canvas_Key_Mode.NORMAL)
    canvas_keyboard_key(&board, &ed, .ENTER, {}, screen)
    testing.expect_value(t, board.editing_edge, 2)

    data := Theme_Data{line_spacing = 1.35}
    theme := Theme{data = &data}
    theme.fonts[.BODY].baseSize = 20
    field := canvas_label_editor_rect(&board, &ed, &theme, screen)
    edge := canvas_items(&board, "edges")[1].(json.Object)
    path, _ := canvas_edge_path(&board, canvas_items(&board, "nodes"), edge)
    testing.expect_value(t, canvas_center(field), canvas_path_midpoint(path))

    editor_begin_frame(&ed)
    editor_handle_charpress(&ed, 'a')
    editor_handle_charpress(&ed, 'é')
    editor_handle_keypress(&ed, .LEFT, {})
    editor_handle_charpress(&ed, 'b')
    editor_end_frame(&ed)
    canvas_finish_editing(&board, &ed)
    testing.expect_value(t, canvas_string(edge, "label"), "abé")
    canvas_keyboard_key(&board, &ed, .ENTER, {}, screen)
    editor_begin_frame(&ed)
    editor_handle_charpress(&ed, 'x')
    editor_handle_keypress(&ed, .ESCAPE, {})
    editor_handle_keypress(&ed, .U, {})
    editor_end_frame(&ed)
    canvas_finish_editing(&board, &ed)
    testing.expect_value(t, canvas_string(edge, "label"), "abé")
}

@(test)
test_canvas_keyboard_resize_previews_and_undoes :: proc(t: ^testing.T) {
    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    ed: Editor
    screen := [2]f32{800, 450}
    board.selected = canvas_add_card(&board, 150, 150)
    node := canvas_items(&board, "nodes")[0].(json.Object)
    undo_count := len(board.undo)
    canvas_keyboard_key(&board, &ed, .R, {}, screen)
    canvas_keyboard_key(&board, &ed, .L, {}, screen)
    canvas_keyboard_key(&board, &ed, .K, {}, screen)
    testing.expect_value(t, canvas_rect(&board, node), rl.Rectangle{150, 150, 270, 130})
    testing.expect_value(t, canvas_coord(node, "width"), f32(252))
    canvas_keyboard_key(&board, &ed, .ESCAPE, {}, screen)
    testing.expect_value(t, canvas_rect(&board, node), rl.Rectangle{150, 150, CANVAS_CARD_W, CANVAS_CARD_H})
    testing.expect_value(t, len(board.undo), undo_count)

    canvas_keyboard_key(&board, &ed, .R, {}, screen)
    canvas_keyboard_key(&board, &ed, .H, {}, screen)
    canvas_keyboard_key(&board, &ed, .J, {}, screen)
    canvas_keyboard_key(&board, &ed, .ENTER, {}, screen)
    testing.expect_value(t, canvas_node_rect(node), rl.Rectangle{150, 150, 242, 158})
    testing.expect_value(t, len(board.undo), undo_count + 1)
    canvas_keyboard_key(&board, &ed, .U, {}, screen)
    testing.expect_value(t, canvas_node_rect(node), rl.Rectangle{150, 150, CANVAS_CARD_W, CANVAS_CARD_H})
}

@(test)
test_canvas_mouse_resize_snaps_to_grid_at_current_zoom :: proc(t: ^testing.T) {
    rect := rl.Rectangle{-17, 31, 252, 140}
    testing.expect_value(t, canvas_drag_resize_size(rect, {8, 20}, 0.5), [2]json.Integer{241, 137})
    testing.expect_value(t, canvas_drag_resize_size(rect, {-500, -500}, 0.5), [2]json.Integer{129, 81})
}

@(test)
test_canvas_keyboard_zoom_is_scoped_to_board :: proc(t: ^testing.T) {
    board := Canvas{zoom = 1}
    screen := [2]f32{800, 450}
    testing.expect(t, canvas_keyboard_zoom(&board, {.EQUAL}, {.CTRL}, screen, 1))
    testing.expect_value(t, board.zoom, f32(1.15))
    testing.expect_value(t, board.zoom_settle_at, f64(1 + CANVAS_ZOOM_SETTLE_SECONDS))

    board.editing = 1
    testing.expect(t, canvas_keyboard_zoom(&board, {.MINUS}, {.CTRL}, screen, 2))
    testing.expect(t, board.zoom < 1.15)
    board.expanded = true
    previous := board.zoom
    testing.expect(t, !canvas_keyboard_zoom(&board, {.EQUAL}, {.CTRL}, screen, 3))
    testing.expect_value(t, board.zoom, previous)
    when ODIN_OS == .Darwin {
        board.expanded = false
        testing.expect_value(t, canvas_zoom_key_delta(&board, .EQUAL, {.CMD}), 1)
        testing.expect_value(t, canvas_zoom_key_delta(&board, .MINUS, {.CMD}), -1)
    }
}

@(test)
test_canvas_move_snaps_to_the_visible_grid :: proc(t: ^testing.T) {
    board: Canvas
    canvas_init(&board)
    defer canvas_destroy(&board)
    ed: Editor
    screen := [2]f32{800, 450}
    board.zoom = 0.25
    board.selected = canvas_add_card(&board, -17, 31)
    step := canvas_grid_step(board.zoom)
    testing.expect_value(t, step, i64(112))
    testing.expect_value(t, canvas_grid_step(1), i64(28))

    canvas_keyboard_key(&board, &ed, .M, {}, screen)
    canvas_keyboard_key(&board, &ed, .H, {}, screen)
    testing.expect_value(t, board.key_move.values, [2]json.Integer{-112, 31})
    canvas_keyboard_key(&board, &ed, .H, {}, screen)
    testing.expect_value(t, board.key_move.values, [2]json.Integer{-224, 31})
    canvas_keyboard_key(&board, &ed, .K, {}, screen)
    testing.expect_value(t, board.key_move.values, [2]json.Integer{-224, 0})
    canvas_keyboard_key(&board, &ed, .L, {}, screen)
    testing.expect_value(t, board.key_move.values, [2]json.Integer{-112, 0})
    canvas_keyboard_key(&board, &ed, .J, {}, screen)
    testing.expect_value(t, board.key_move.values, [2]json.Integer{-112, 112})
    canvas_keyboard_key(&board, &ed, .ENTER, {}, screen)
    node := canvas_items(&board, "nodes")[0].(json.Object)
    testing.expect_value(t, canvas_node_rect(node), rl.Rectangle{-112, 112, 224, 112})
}

@(test)
test_canvas_repeat_uses_distinct_movement_and_zoom_intervals :: proc(t: ^testing.T) {
    keys: Key_Repeat_State
    keys.keys[.H] = {is_pressed = true, pressed_at = 10, repeat_time = 10}
    keys.keys[.EQUAL] = {is_pressed = true, pressed_at = 10, repeat_time = 10}
    testing.expect(t, !key_repeat_should_repeat(&keys, .H, 10.20, CANVAS_REPEAT_DELAY_MS, CANVAS_DIRECTION_REPEAT_MS))
    testing.expect(t, !key_repeat_should_repeat(&keys, .EQUAL, 10.20, CANVAS_REPEAT_DELAY_MS, CANVAS_ZOOM_REPEAT_MS))
    testing.expect(t, key_repeat_should_repeat(&keys, .H, 10.22, CANVAS_REPEAT_DELAY_MS, CANVAS_DIRECTION_REPEAT_MS))
    testing.expect(t, key_repeat_should_repeat(&keys, .EQUAL, 10.22, CANVAS_REPEAT_DELAY_MS, CANVAS_ZOOM_REPEAT_MS))
    testing.expect(t, key_repeat_should_repeat(&keys, .H, 10.27, CANVAS_REPEAT_DELAY_MS, CANVAS_DIRECTION_REPEAT_MS))
    testing.expect(t, !key_repeat_should_repeat(&keys, .EQUAL, 10.27, CANVAS_REPEAT_DELAY_MS, CANVAS_ZOOM_REPEAT_MS))
    testing.expect(t, key_repeat_should_repeat(&keys, .EQUAL, 10.31, CANVAS_REPEAT_DELAY_MS, CANVAS_ZOOM_REPEAT_MS))
    keys.keys[.EQUAL].is_pressed = false
    testing.expect(t, !key_repeat_should_repeat(&keys, .EQUAL, 10.50, CANVAS_REPEAT_DELAY_MS, CANVAS_ZOOM_REPEAT_MS))
}
