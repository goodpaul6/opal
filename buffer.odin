package main

import sa "core:container/small_array"

MAX_LINE_LENGTH :: 512

Line :: sa.Small_Array(MAX_LINE_LENGTH, rune)

Buffer :: struct {
    lines: [dynamic]Line,
}

delete_buffer :: proc(using buf: ^Buffer) {
    delete(lines)
}

resize_buffer_to_pos :: proc(using buf: ^Buffer, pos: Pos) -> ^Line {
    assert(pos.row >= 0)

    if pos.row >= len(lines) {
        resize(&lines, pos.row + 1)
    }

    assert(pos.col >= 0)
    assert(pos.col < MAX_LINE_LENGTH)

    line := &lines[pos.row]

    if pos.col >= sa.len(line^) {
        sa.resize(line, pos.col)
    }

    return line
}

insert_rune :: proc(using buf: ^Buffer, pos: Pos, ch: rune) -> bool {
    line := resize_buffer_to_pos(buf, pos)

    return sa.inject_at(line, ch, pos.col)
}

insert_string :: proc(using buf: ^Buffer, pos: Pos, text: string) -> bool {
    for ch, idx in text {
        // TODO(Apaar): Might be better to memcpy from a rune slice
        // instead.
        insert_rune(buf, Pos{pos.row, pos.col + idx}, ch) or_return
    }

    return true
}

insert_empty_line_below :: proc(using buf: ^Buffer, pos: Pos) {
    resize_buffer_to_pos(buf, pos)

    inject_at(&lines, pos.row + 1, Line{})
}

remove_rune :: proc(using buf: ^Buffer, pos: Pos) {
    assert(pos.row >= 0)

    if pos.row >= len(lines) {
        return
    }

    line := &lines[pos.row]

    if pos.col >= sa.len(line^) {
        return
    }

    sa.ordered_remove(line, pos.col)
}

clamp_pos_to_buffer :: proc(using pos: ^Pos, buf: ^Buffer) {
    line_count := len(buf.lines)

    if line_count == 0 {
        row = 0
        col = 0
        return
    }

    row = clamp(row, 0, line_count - 1)
    col = clamp(col, 0, sa.len(buf.lines[row]))
}
