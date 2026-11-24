package main

import "core:bytes"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

Canvas_Version :: struct {
    document: json.Object,
    revision: u64,
}

Canvas_Geometry :: struct {
    node: int,
    resize: bool,
    values: [2]json.Integer,
}

Canvas_Append :: struct {
    collection: string,
    item: json.Object, // Owned by history while the addition is undone.
    with_edge: bool,
    edge: json.Object,
}

Canvas_Change :: union {json.Object, Canvas_Geometry, Canvas_Append}
Canvas_History :: struct {
    change: Canvas_Change,
    revision: u64,
}
CANVAS_HISTORY_LIMIT :: 32

Canvas_Prompt :: enum { NONE, OPEN, SAVE, CLOSE }
Canvas_Drag :: enum { NONE, PAN, MOVE, RESIZE, CONNECT }
Canvas_Key_Mode :: enum { NORMAL, MOVE, RESIZE, CONNECT, G_PREFIX }
Canvas_Side :: enum { TOP, RIGHT, BOTTOM, LEFT }
CANVAS_SIDES :: [Canvas_Side]string{.TOP = "top", .RIGHT = "right", .BOTTOM = "bottom", .LEFT = "left"}
CANVAS_GRID_STEP :: 28
CANVAS_CARD_W :: 9 * CANVAS_GRID_STEP
CANVAS_CARD_H :: 5 * CANVAS_GRID_STEP

Canvas :: struct {
    current: Canvas_Version,
    undo, redo: [dynamic]Canvas_History,
    next_revision, saved_revision, next_id: u64,
    filename: string,
    disk_bytes: []byte,
    node_indices: map[string]int,

    selected, selected_edge, editing: int, // One-based indices. Zero means no selection.
    editing_edge: int,
    expanded, finish_editing, finish_after_save: bool,
    exit_requested, close_after_save: bool,

    pan: [2]f32,
    zoom: f32,
    zoom_settle_at: f64,
    rasters: [2]Canvas_Font_Rasters,
    last_rasters: int,
    fit: bool,
    drag: Canvas_Drag,
    drag_start, drag_point: [2]f32,
    drag_origin: rl.Rectangle,
    drag_recorded: bool,
    side: Canvas_Side,
    last_click: f64,
    last_click_point: [2]f32,
    last_click_node, last_click_edge: int,
    key_mode: Canvas_Key_Mode,
    key_move: Canvas_Geometry,
    connect_from: int,
    connect_source_side, connect_target_side: Maybe(Canvas_Side),

    prompt: Canvas_Prompt,
    prompt_text: strings.Builder,
    prompt_cursor: int,
    prompt_replace_all: bool,
    message: string,
}

canvas_set :: proc(object: ^json.Object, key: string, value: json.Value) {
    if old, exists := object^[key]; exists {
        json.destroy_value(old)
        object^[key] = value
    } else {
        object^[strings.clone(key)] = value
    }
}

canvas_init :: proc(board: ^Canvas) {
    board.current.document = make(json.Object)
    board.zoom = 1
    board.fit = true
    board.prompt_text = strings.builder_make()
    board.undo = make([dynamic]Canvas_History, 0, CANVAS_HISTORY_LIMIT)
    board.redo = make([dynamic]Canvas_History, 0, CANVAS_HISTORY_LIMIT)
}

canvas_free_change :: proc(change: Canvas_Change) {
    #partial switch change in change {
        case json.Object: json.destroy_value(change)
        case Canvas_Append:
            json.destroy_value(change.item)
            json.destroy_value(change.edge)
    }
}

canvas_clear_history :: proc(history: ^[dynamic]Canvas_History) {
    for entry in history do canvas_free_change(entry.change)
    clear(history)
}

canvas_destroy :: proc(board: ^Canvas) {
    for &rasters in board.rasters do canvas_font_rasters_destroy(&rasters)
    json.destroy_value(board.current.document)
    canvas_clear_history(&board.undo)
    canvas_clear_history(&board.redo)
    delete(board.undo)
    delete(board.redo)
    delete(board.filename)
    delete(board.disk_bytes)
    delete(board.node_indices)
    strings.builder_destroy(&board.prompt_text)
}

canvas_record_undo :: proc(board: ^Canvas, change: Canvas_Change) {
    if len(board.undo) == CANVAS_HISTORY_LIMIT {
        canvas_free_change(board.undo[0].change)
        ordered_remove(&board.undo, 0)
    }
    append(&board.undo, Canvas_History{change, board.current.revision})
    canvas_clear_history(&board.redo)
    board.next_revision += 1
    board.current.revision = board.next_revision
    board.message = ""
}

canvas_push_undo :: proc(board: ^Canvas) {
    canvas_record_undo(board, json.clone_value(board.current.document).(json.Object))
}

canvas_step_history :: proc(board: ^Canvas, redo: bool) {
    source, target := &board.undo, &board.redo
    if redo do source, target = target, source
    if len(source^) == 0 do return
    entry := pop(source)
    inverse: Canvas_Change
    switch change in entry.change {
        case json.Object:
            inverse = board.current.document
            board.current.document = change
            canvas_reindex(board)
        case Canvas_Geometry:
            old, _ := canvas_apply_geometry(board, change)
            inverse = old
        case Canvas_Append:
            inverse = canvas_swap_append(board, change)
    }
    append(target, Canvas_History{inverse, board.current.revision})
    board.current.revision = entry.revision
    board.selected, board.selected_edge = 0, 0
    board.message = ""
}

canvas_items :: proc(board: ^Canvas, key: string) -> json.Array {
    items, _ := board.current.document[key].(json.Array)
    return items
}

canvas_geometry_keys :: proc(resize: bool) -> (string, string) {
    if resize do return "width", "height"
    return "x", "y"
}

canvas_apply_geometry :: proc(board: ^Canvas, change: Canvas_Geometry) -> (previous: Canvas_Geometry, changed: bool) {
    node := canvas_items(board, "nodes")[change.node - 1].(json.Object)
    x, y := canvas_geometry_keys(change.resize)
    previous = {change.node, change.resize, {node[x].(json.Integer), node[y].(json.Integer)}}
    if previous.values == change.values do return
    node[x], node[y] = change.values.x, change.values.y
    return previous, true
}

canvas_drag_geometry :: proc(board: ^Canvas, change: Canvas_Geometry) -> bool {
    previous, changed := canvas_apply_geometry(board, change)
    if changed && !board.drag_recorded {
        canvas_record_undo(board, previous)
        board.drag_recorded = true
    }
    return changed
}

canvas_append :: proc(board: ^Canvas, key: string, object: json.Object) {
    items := canvas_items(board, key)
    append(&items, object)
    // The array holds owned values. Update its header without destroying them.
    if _, exists := board.current.document[key]; exists {
        board.current.document[key] = items
    } else {
        board.current.document[strings.clone(key)] = items
    }
}

canvas_swap_append :: proc(board: ^Canvas, change: Canvas_Append) -> Canvas_Append {
    inverse := Canvas_Append{collection = change.collection, with_edge = change.with_edge}
    if change.item != nil {
        canvas_append(board, change.collection, change.item)
        if change.with_edge do canvas_append(board, "edges", change.edge)
    } else {
        if change.with_edge {
            edges := canvas_items(board, "edges")
            inverse.edge = pop(&edges).(json.Object)
            board.current.document["edges"] = edges
        }
        items := canvas_items(board, change.collection)
        inverse.item = pop(&items).(json.Object)
        board.current.document[change.collection] = items
    }
    if change.collection == "nodes" do canvas_reindex(board)
    return inverse
}

canvas_string :: proc(object: json.Object, key: string) -> string {
    value, _ := object[key].(json.String)
    return value
}

canvas_coord :: proc(object: json.Object, key: string) -> f32 {
    value, _ := object[key].(json.Integer)
    return f32(value)
}

canvas_find_node :: proc(nodes: json.Array, id: string) -> int {
    for item, i in nodes {
        if canvas_string(item.(json.Object), "id") == id do return i + 1
    }
    return 0
}

canvas_reindex :: proc(board: ^Canvas) {
    clear(&board.node_indices)
    for item, i in canvas_items(board, "nodes") {
        board.node_indices[canvas_string(item.(json.Object), "id")] = i + 1
    }
}

canvas_new_id :: proc(board: ^Canvas) -> string {
    for {
        board.next_id += 1
        id := fmt.tprintf("opal-%x", board.next_id)
        if id not_in board.node_indices &&
           canvas_find_node(canvas_items(board, "edges"), id) == 0 {
            return strings.clone(id)
        }
    }
}

canvas_add_card :: proc(
    board: ^Canvas, x, y: i64, from := 0, from_side: Canvas_Side = .RIGHT, to_side: Canvas_Side = .LEFT,
) -> int {
    canvas_record_undo(board, Canvas_Append{collection = "nodes", with_edge = from != 0})
    card := make(json.Object)
    canvas_set(&card, "id", canvas_new_id(board))
    canvas_set(&card, "type", strings.clone("text"))
    canvas_set(&card, "x", x)
    canvas_set(&card, "y", y)
    dimensions := canvas_new_card_size(board.zoom)
    canvas_set(&card, "width", i64(dimensions.x))
    canvas_set(&card, "height", i64(dimensions.y))
    canvas_set(&card, "text", "")
    canvas_append(board, "nodes", card)
    index := len(canvas_items(board, "nodes"))
    board.node_indices[canvas_string(card, "id")] = index
    if from != 0 do canvas_append_edge(board, from, index, from_side, to_side)
    return index
}

canvas_connect :: proc(board: ^Canvas, from, to: int, from_side, to_side: Canvas_Side) {
    canvas_record_undo(board, Canvas_Append{collection = "edges"})
    canvas_append_edge(board, from, to, from_side, to_side)
}

canvas_append_edge :: proc(board: ^Canvas, from, to: int, from_side, to_side: Canvas_Side) {
    nodes := canvas_items(board, "nodes")
    from_id := canvas_string(nodes[from - 1].(json.Object), "id")
    to_id := canvas_string(nodes[to - 1].(json.Object), "id")
    edge := make(json.Object)
    canvas_set(&edge, "id", canvas_new_id(board))
    canvas_set(&edge, "fromNode", strings.clone(from_id))
    canvas_set(&edge, "toNode", strings.clone(to_id))
    sides := CANVAS_SIDES
    canvas_set(&edge, "fromSide", strings.clone(sides[from_side]))
    canvas_set(&edge, "toSide", strings.clone(sides[to_side]))
    canvas_append(board, "edges", edge)
}

canvas_remove_selected :: proc(board: ^Canvas) {
    nodes, edges := canvas_items(board, "nodes"), canvas_items(board, "edges")
    if board.selected == 0 && board.selected_edge == 0 do return
    canvas_push_undo(board)
    if board.selected != 0 {
        node := nodes[board.selected - 1].(json.Object)
        id := canvas_string(node, "id")
        for i := len(edges) - 1; i >= 0; i -= 1 {
            edge := edges[i].(json.Object)
            if canvas_string(edge, "fromNode") == id || canvas_string(edge, "toNode") == id {
                json.destroy_value(edge)
                ordered_remove(&edges, i)
            }
        }
        json.destroy_value(node)
        ordered_remove(&nodes, board.selected - 1)
        board.current.document["nodes"] = nodes
        canvas_reindex(board)
    } else {
        json.destroy_value(edges[board.selected_edge - 1])
        ordered_remove(&edges, board.selected_edge - 1)
    }
    if _, exists := board.current.document["edges"]; exists do board.current.document["edges"] = edges
    board.selected, board.selected_edge = 0, 0
}

// Keep the full JSON objects so features from other editors survive a save.
canvas_parse :: proc(data: []byte) -> (document: json.Object, ok: bool) {
    if !json.is_valid(data, .JSON, true) do return
    parser := json.make_parser(data, .JSON, true)
    value, err := json.parse_value(&parser)
    if err != nil do return
    defer if !ok do json.destroy_value(value)
    if parser.curr_token_err != .EOF do return
    document = value.(json.Object) or_return
    for key in ([?]string{"nodes", "edges"}) {
        entry, exists := document[key]
        if !exists do continue
        items := entry.(json.Array) or_return
        ids := make(map[string]bool, len(items), context.temp_allocator)
        for item in items {
            object := item.(json.Object) or_return
            id := object["id"].(json.String) or_return
            if id == "" || id in ids do return
            ids[id] = true
            if key == "nodes" {
                kind := object["type"].(json.String) or_return
                for coord in ([?]string{"x", "y", "width", "height"}) {
                    if _, valid := object[coord].(json.Integer); !valid do return
                }
                if kind == "text" {
                    if _, valid := object["text"].(json.String); !valid do return
                }
            } else {
                for endpoint in ([?]string{"fromNode", "toNode"}) {
                    if _, valid := object[endpoint].(json.String); !valid do return
                }
            }
        }
    }
    return document, true
}

canvas_absolute_path :: proc(path: string, allocator := context.temp_allocator) -> (string, os.Error) {
    parent := os.dir(path)
    if parent == "" do parent = "."
    absolute, err := filepath.abs(parent, context.temp_allocator)
    if err != nil do return "", err
    return os.join_path({absolute, os.base(path)}, allocator)
}

canvas_open :: proc(board: ^Canvas, path: string) -> bool {
    if !strings.equal_fold(os.ext(path), ".canvas") {
        board.message = "Choose a .canvas file"
        return false
    }
    data, err := os.read_entire_file(path, context.allocator)
    if err != nil {
        board.message = "Could not open canvas"
        return false
    }
    document, ok := canvas_parse(data)
    if !ok {
        delete(data)
        board.message = "Invalid JSON Canvas document"
        return false
    }
    filename, path_err := canvas_absolute_path(path, context.allocator)
    if path_err != nil {
        json.destroy_value(document)
        delete(data)
        board.message = "Could not resolve canvas path"
        return false
    }
    delete(board.filename)
    delete(board.disk_bytes)
    json.destroy_value(board.current.document)
    canvas_clear_history(&board.undo)
    canvas_clear_history(&board.redo)
    board.current = {document, 0}
    canvas_reindex(board)
    board.saved_revision = 0
    board.filename, board.disk_bytes = filename, data
    board.selected, board.selected_edge = 0, 0
    board.fit = true
    board.message = ""
    return true
}

canvas_write_file :: proc(path: string, data: []byte, replace: bool, mode: os.Permissions) -> bool {
    file, err := os.create_temp_file(os.dir(path), ".opal-canvas-*")
    if err != nil do return false
    temp_path := strings.clone(os.name(file), context.temp_allocator)
    defer os.remove(temp_path)
    if os.fchmod(file, mode) != nil {
        os.close(file)
        return false
    }
    n, write_err := os.write(file, data)
    sync_err := os.sync(file)
    close_err := os.close(file)
    if write_err != nil || n != len(data) || sync_err != nil || close_err != nil do return false
    if replace do return os.rename(temp_path, path) == nil
    return os.link(temp_path, path) == nil
}

canvas_save :: proc(board: ^Canvas, path: string) -> bool {
    path := path
    if os.ext(path) == "" do path = fmt.tprintf("%s.canvas", path)
    if !strings.equal_fold(os.ext(path), ".canvas") {
        board.message = "Use a .canvas filename"
        return false
    }
    absolute, path_err := canvas_absolute_path(path)
    if path_err != nil {
        board.message = "Could not resolve canvas path"
        return false
    }
    path = absolute
    replace := path == board.filename
    mode := os.Permissions{.Read_User, .Write_User}
    if replace {
        info, stat_err := os.lstat(path, context.temp_allocator)
        if stat_err != nil || info.type != .Regular {
            board.message = "Choose a new filename to save a copy"
            return false
        }
        mode = info.mode
        on_disk, err := os.read_entire_file(path, context.temp_allocator)
        if err != nil || !bytes.equal(on_disk, board.disk_bytes) {
            board.message = "Canvas changed on disk. Save a copy with a new name."
            return false
        }
    } else if os.exists(path) {
        board.message = "That file already exists. Choose a new name."
        return false
    }
    data, err := json.marshal(board.current.document, {spec = .JSON, pretty = true, use_spaces = true, spaces = 2, sort_maps_by_key = true})
    if err != nil {
        board.message = "Could not encode canvas"
        return false
    }
    if !canvas_write_file(path, data, replace, mode) {
        delete(data)
        board.message = "Could not save canvas"
        return false
    }
    filename := strings.clone(path)
    delete(board.filename)
    delete(board.disk_bytes)
    board.filename, board.disk_bytes = filename, data
    board.saved_revision = board.current.revision
    board.message = "Canvas saved"
    return true
}

canvas_active_card :: proc(board: ^Canvas) -> json.Object {
    return canvas_items(board, "nodes")[board.editing - 1].(json.Object)
}

canvas_editor_active :: proc(board: ^Canvas) -> bool {
    return board.editing != 0 || board.editing_edge != 0
}

canvas_editor_target :: proc(board: ^Canvas) -> (json.Object, string) {
    if board.editing_edge != 0 {
        return canvas_items(board, "edges")[board.editing_edge - 1].(json.Object), "label"
    }
    if board.editing != 0 do return canvas_active_card(board), "text"
    return nil, ""
}

canvas_dirty :: proc(board: ^Canvas, ed: ^Editor) -> bool {
    if board.current.revision != board.saved_revision do return true
    item, field := canvas_editor_target(board)
    return item != nil && editor_get_text(ed) != canvas_string(item, field)
}

canvas_begin_editor :: proc(board: ^Canvas, ed: ^Editor, text: string, insert: bool, caret := 0) {
    ed^ = {}
    editor_init(ed, system_clipboard = true)
    ed.canvas = board
    strings.write_string(&ed.sb, text)
    ed.state.selection, ed.prev_frame_sel = {caret, caret}, {caret, caret}
    if insert {
        ed.mode = .INSERT
        track_text_and_pos(ed)
    }
    board.expanded = false
    board.message = ""
}

canvas_edit_card :: proc(board: ^Canvas, ed: ^Editor, index: int, insert := false) {
    card := canvas_items(board, "nodes")[index - 1].(json.Object)
    if canvas_string(card, "type") != "text" do return
    canvas_begin_editor(board, ed, canvas_string(card, "text"), insert)
    board.editing = index
}

canvas_edit_edge :: proc(board: ^Canvas, ed: ^Editor, index: int) {
    edge := canvas_items(board, "edges")[index - 1].(json.Object)
    if board.node_indices[canvas_string(edge, "fromNode")] == 0 ||
       board.node_indices[canvas_string(edge, "toNode")] == 0 {
        return
    }
    label := canvas_string(edge, "label")
    canvas_begin_editor(board, ed, label, true, len(label))
    board.editing_edge = index
}

canvas_commit_editor :: proc(board: ^Canvas, ed: ^Editor) {
    item, field := canvas_editor_target(board)
    if item == nil do return
    text := editor_get_text(ed)
    if text == canvas_string(item, field) do return
    canvas_push_undo(board)
    canvas_set(&item, field, strings.clone(text))
}

canvas_finish_editing :: proc(board: ^Canvas, ed: ^Editor) {
    canvas_commit_editor(board, ed)
    editor_destroy(ed)
    ed^ = {}
    board.editing, board.editing_edge = 0, 0
    board.expanded = false
    board.finish_editing = false
}

canvas_begin_prompt :: proc(board: ^Canvas, prompt: Canvas_Prompt) {
    board.prompt = prompt
    board.drag = .NONE
    board.key_mode = .NORMAL
    board.connect_from = 0
    board.prompt_replace_all = false
    board.prompt_cursor = 0
    strings.builder_reset(&board.prompt_text)
}

canvas_complete_save :: proc(board: ^Canvas) {
    board.prompt = .NONE
    if board.close_after_save do board.exit_requested = true
    if board.finish_after_save do board.finish_editing = true
    board.finish_after_save = false
}

canvas_request_save :: proc(board: ^Canvas, ed: ^Editor, finish_editing := false) {
    canvas_commit_editor(board, ed)
    board.finish_after_save = finish_editing
    if board.filename == "" {
        canvas_begin_prompt(board, .SAVE)
    } else if canvas_save(board, board.filename) {
        canvas_complete_save(board)
    } else {
        canvas_begin_prompt(board, .SAVE)
    }
}

canvas_card_command :: proc(board: ^Canvas, ed: ^Editor, cmd: ^Command) -> bool {
    switch c in cmd {
        case Command_Quit:
            board.finish_editing = true
            return true
        case Command_Write:
            if c.filename == "" {
                canvas_request_save(board, ed, finish_editing = c.quit)
                return true
            }
            canvas_commit_editor(board, ed)
            if canvas_save(board, c.filename) {
                board.finish_editing = c.quit
                return true
            }
        case Command_Edit:
            board.message = "Return to the canvas to open another document"
    }
    return false
}
