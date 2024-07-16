package main

import "core:testing"
import "core:fmt"

@(test)
test_parser :: proc(t: ^testing.T) {
    // We handle UTF8 correctly :)
    s := "  Hello world\na`test\U0001F600`"
    pos := 0

    t1 := parser_next_token(&s, &pos)
    t2 := parser_next_token(&s, &pos)
    t3 := parser_next_token(&s, &pos)
    t4 := parser_next_token(&s, &pos)
    t5 := parser_next_token(&s, &pos)
    t6 := parser_next_token(&s, &pos)
    t7 := parser_next_token(&s, &pos)
    t8, ok := parser_next_token(&s, &pos)

    testing.expect_value(t, t1.sub, Parser_Token_Spaces("  "))
    testing.expect_value(t, t2.sub, Parser_Token_Word("Hello"))
    testing.expect_value(t, t3.sub, Parser_Token_Spaces(" "))
    testing.expect_value(t, t4.sub, Parser_Token_Word("world"))
    testing.expect_value(t, t5.sub, Parser_Token_Spaces("\n"))
    testing.expect_value(t, t6.sub, Parser_Token_Word("a"))
    testing.expect_value(t, t7.sub, Parser_Token_Pre("test\U0001F600"))
    testing.expect_value(t, ok, false)
}
