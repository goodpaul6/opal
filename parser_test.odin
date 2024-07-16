package main

import "core:testing"

@(test)
test_parser :: proc(t: ^testing.T) {
    // We handle UTF8 correctly :)
    s := "  Hello world\na`test\U0001F600`"

    t1 := parser_next_token(&s)
    t2 := parser_next_token(&s)
    t3 := parser_next_token(&s)
    t4 := parser_next_token(&s)
    t5 := parser_next_token(&s)
    t6 := parser_next_token(&s)
    t7 := parser_next_token(&s)
    t8, ok := parser_next_token(&s)

    testing.expect_value(t, t1, Parser_Token_Spaces("  "))
    testing.expect_value(t, t2, Parser_Token_Word("Hello"))
    testing.expect_value(t, t3, Parser_Token_Spaces(" "))
    testing.expect_value(t, t4, Parser_Token_Word("world"))
    testing.expect_value(t, t5, Parser_Token_Spaces("\n"))
    testing.expect_value(t, t6, Parser_Token_Word("a"))
    testing.expect_value(t, t7, Parser_Token_Pre("test\U0001F600"))
    testing.expect_value(t, ok, false)
}
