package main

import "core:testing"

@(test)
test_parser :: proc(t: ^testing.T) {
    src := "hello world"

    list := parser_parse_string(src)

    testing.expect_value(t, list.head^, Node{
        next = list.head.next,
        sub = Node_Text{false, "hello"},
    })

    testing.expect_value(t, list.head.next^, Node{
        next = list.head.next.next,
        sub = Node_Text{false, " "},
    })

    testing.expect_value(t, list.head.next.next^, Node{
        next = nil,
        sub = Node_Text{false, "world"},
    })
}
