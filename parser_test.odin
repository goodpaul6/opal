package main

import "core:testing"

@(test)
test_parser :: proc(t: ^testing.T) {
    src := "hello world"

    list := parser_parse_string(src)

    testing.expect_value(t, list.head^, Node{
        next = list.head.next,
        extents = {0, 5},
        sub = Node_Text{false, false, "hello"},
    })

    testing.expect_value(t, list.head.next^, Node{
        next = list.head.next.next,
        extents = {5, 6},
        sub = Node_Text{false, true, " "},
    })

    testing.expect_value(t, list.head.next.next^, Node{
        next = nil,
        extents = {6, 11},
        sub = Node_Text{false, false, "world"},
    })
}
