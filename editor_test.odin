package main

import "core:testing"

@(test)
test_editor_loc :: proc(t: ^testing.T) {
    s := transmute([]byte) string("AAAA\nAAAA\nAAA")

    loc := byte_index_to_editor_loc(0, s)

    testing.expect_value(t, loc.row, 0)
    testing.expect_value(t, loc.col, 0)

    idx := editor_loc_to_byte_index(loc, s)

    testing.expect_value(t, idx, 0)

    loc = byte_index_to_editor_loc(4, s)

    testing.expect_value(t, loc.row, 0)
    testing.expect_value(t, loc.col, 4)

    idx = editor_loc_to_byte_index(loc, s)

    testing.expect_value(t, idx, 4)

    loc = byte_index_to_editor_loc(5, s)

    testing.expect_value(t, loc.row, 1)
    testing.expect_value(t, loc.col, 0)

    idx = editor_loc_to_byte_index(loc, s)

    testing.expect_value(t, idx, 5)

    idx = editor_loc_to_byte_index({5, 5}, s)

    testing.expect_value(t, idx, len(s))

    idx = editor_loc_to_byte_index({2, 2}, s)

    testing.expect_value(t, idx, 12)
}
