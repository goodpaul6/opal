package main

import "core:testing"
import "core:fmt"

@(test)
test_lexer :: proc(t: ^testing.T) {
    // We handle UTF8 correctly :)
    s := "  Hello world\na`test\U0001F600`-"
    l := Lexer{s, 0}

    t1 := lexer_next_token(&l)
    t2 := lexer_next_token(&l)
    t3 := lexer_next_token(&l)
    t4 := lexer_next_token(&l)
    t5 := lexer_next_token(&l)
    t6 := lexer_next_token(&l)
    t7 := lexer_next_token(&l)
    t8 := lexer_next_token(&l)
    t9 := lexer_next_token(&l)
    t10 := lexer_next_token(&l)
    _, ok := lexer_next_token(&l)

    testing.expect_value(t, t1.sub, Lexer_Token_Spaces("  "))
    testing.expect_value(t, t1.extents, [2]int{0, 2})
    testing.expect_value(t, t2.sub, Lexer_Token_Word("Hello"))
    testing.expect_value(t, t3.sub, Lexer_Token_Spaces(" "))
    testing.expect_value(t, t4.sub, Lexer_Token_Word("world"))
    testing.expect_value(t, t5.sub, Lexer_Token_Newline("\n"))
    testing.expect_value(t, t6.sub, Lexer_Token_Word("a"))
    testing.expect_value(t, t7.sub, Lexer_Token_Backtick("`"))
    testing.expect_value(t, t8.sub, Lexer_Token_Word("test\U0001F600"))
    testing.expect_value(t, t9.sub, Lexer_Token_Backtick("`"))
    testing.expect_value(t, t10.sub, Lexer_Token_Minus("-"))
    testing.expect_value(t, ok, false)
}
