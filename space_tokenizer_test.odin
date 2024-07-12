package main

import "core:testing"

@(test)
test_space_tokenizer :: proc(t: ^testing.T) {
    s := "  Hello world\na"

    t1 := space_tokenizer_next_token(&s)
    t2 := space_tokenizer_next_token(&s)
    t3 := space_tokenizer_next_token(&s)
    t4 := space_tokenizer_next_token(&s)
    t5 := space_tokenizer_next_token(&s)
    t6 := space_tokenizer_next_token(&s)
    t7 := space_tokenizer_next_token(&s)

    testing.expect_value(t, t1, Space_Tokenizer_Token_Spaces("  "))
    testing.expect_value(t, t2, Space_Tokenizer_Token_Word("Hello"))
    testing.expect_value(t, t3, Space_Tokenizer_Token_Spaces(" "))
    testing.expect_value(t, t4, Space_Tokenizer_Token_Word("world"))
    testing.expect_value(t, t5, Space_Tokenizer_Token_Spaces("\n"))
    testing.expect_value(t, t6, Space_Tokenizer_Token_Word("a"))
    testing.expect_value(t, t7, nil)
}
