package main

import "core:strings"

Parser_Token_Spaces :: distinct string
Parser_Token_Word :: distinct string
Parser_Token_Pre :: distinct string

Parser_Token :: union #no_nil {
    Parser_Token_Spaces,
    Parser_Token_Word,
    Parser_Token_Pre,
}

parser_is_word_delimiter :: proc(ch: rune) -> bool {
    return ch == '`' || strings.is_ascii_space(ch)
}

parser_next_token :: proc(src: ^string) -> (token: Parser_Token, ok: bool) #optional_ok {
    if len(src) == 0 {
        return
    }

    state: enum {NONE, SPACE, PRE, WORD}
    count := 0

    loop: for ch in src {
        switch state {
            case .NONE: {
                if strings.is_ascii_space(ch) do state = .SPACE
                else if ch == '`' do state = .PRE
                else do state = .WORD

                count += 1
                continue loop
            }

            case .SPACE: {
                if strings.is_ascii_space(ch) do count += 1
                else do break loop

                continue loop
            }

            case .PRE: {
                count += 1

                if ch == '`' {
                    // We'll strip the backticks later
                    break loop
                }

                continue loop
            }

            case .WORD: {
                if parser_is_word_delimiter(ch) {
                    break loop
                }

                count += 1
                continue loop
            }
        }
    }

    switch state {
        case .SPACE: token = Parser_Token_Spaces(src[:count])
        case .PRE: token = Parser_Token_Pre(src[1:count-1])
        case .WORD: token = Parser_Token_Word(src[:count])
        case .NONE: return
    }

    src^ = src[count:]

    return token, true
}
