// Iteratively tokenizes strings into runs of spaces
// and then non-space chars
package main

import "core:strings"

Space_Tokenizer_Token_Spaces :: distinct string
Space_Tokenizer_Token_Newline :: struct {}
Space_Tokenizer_Token_Word :: distinct string

Space_Tokenizer_Token :: union {Space_Tokenizer_Token_Spaces, Space_Tokenizer_Token_Newline, Space_Tokenizer_Token_Word}

space_tokenizer_next_token :: proc(s: ^string) -> Space_Tokenizer_Token {
    if len(s) == 0 {
        return nil
    }

    if strings.is_ascii_space(rune(s[0])) {
        if s[0] == '\n' {
            s^ = s[1:]
            return Space_Tokenizer_Token_Newline{}
        }

        length := 0

        for length < len(s) && strings.is_ascii_space(rune(s[length])) {
            length += 1
        }

        src_slice := s[:length]
        s^ = s[length:]

        return Space_Tokenizer_Token_Spaces(src_slice)
    }

    length := 0

    for length < len(s) && !strings.is_ascii_space(rune(s[length])) {
        length += 1
    }

    src_slice := s[:length]
    s^ = s[length:]

    return Space_Tokenizer_Token_Word(src_slice)
}
