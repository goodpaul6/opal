package main

import "core:strings"
import "core:io"
import "core:fmt"

Lexer_Token_Newline :: distinct string
Lexer_Token_Spaces :: distinct string
Lexer_Token_Word :: distinct string
Lexer_Token_Backtick :: distinct string
Lexer_Token_Minus :: distinct string
Lexer_Token_Left_Bracket :: distinct string
Lexer_Token_Right_Bracket :: distinct string

Lexer_Token_Sub :: union #no_nil {
    Lexer_Token_Newline,
    Lexer_Token_Spaces,
    Lexer_Token_Word,
    Lexer_Token_Backtick,
    Lexer_Token_Minus,
    Lexer_Token_Left_Bracket,
    Lexer_Token_Right_Bracket,
}

Lexer_Token :: struct {
    // For figuring out where the cursor is, for example
    extents: [2]int,
    sub: Lexer_Token_Sub,
}

Lexer :: struct {
    src: string,
    pos: int,
}

@(private="file")
read_rune_iterator :: proc(reader: ^strings.Reader) -> (rr: rune, size: int, ok: bool) {
    err: io.Error

    rr, size, err = strings.reader_read_rune(reader)
    if err != nil {
        return
    }

    return rr, size, true
}

lexer_is_non_newline_space :: proc(ch: rune) -> bool {
    return strings.is_ascii_space(ch) && ch != '\n'
}

lexer_is_word_delimiter :: proc(ch: rune) -> bool {
    return ch == '`' || strings.is_ascii_space(ch)
}

lexer_token_string :: proc(token: Lexer_Token) -> string {
    switch sub in token.sub {
        case Lexer_Token_Newline: return string(sub)
        case Lexer_Token_Spaces: return string(sub)
        case Lexer_Token_Word: return string(sub)
        case Lexer_Token_Backtick: return string(sub)
        case Lexer_Token_Minus: return string(sub)
        case Lexer_Token_Left_Bracket: return string(sub)
        case Lexer_Token_Right_Bracket: return string(sub)
    }

    assert(false)
    return ""
}

lexer_next_token :: proc(using lex: ^Lexer) -> (token: Lexer_Token, ok: bool) #optional_ok {
    state: enum {
        NONE, 
        NEWLINE, 
        SPACE, 
        BACKTICK, 
        MINUS, 
        LEFT_BRACKET, 
        RIGHT_BRACKET,
        WORD,
    }

    start := pos
    count := 0

    reader: strings.Reader
    strings.reader_init(&reader, src)

    loop: for ch, size in read_rune_iterator(&reader) {
        switch state {
            case .NONE: {
                count += size

                if lexer_is_non_newline_space(ch) do state = .SPACE
                else if ch == '`' {
                    state = .BACKTICK

                    // Backticks are single char tokens
                    break loop
                } else if ch == '\n' {
                    state = .NEWLINE

                    break loop
                } else if ch == '-' {
                    state = .MINUS

                    break loop
                } else if ch == '[' {
                    state = .LEFT_BRACKET

                    break loop
                } else if ch == ']' {
                    state = .RIGHT_BRACKET

                    break loop
                } else do state = .WORD

                continue loop
            }

            case .NEWLINE:
            case .BACKTICK:
            case .MINUS:
            case .LEFT_BRACKET:
            case .RIGHT_BRACKET:

            case .SPACE: {
                if lexer_is_non_newline_space(ch) do count += size
                else do break loop

                continue loop
            }

            case .WORD: {
                if lexer_is_word_delimiter(ch) {
                    break loop
                }

                count += size
                continue loop
            }
        }
    }

    extents := [2]int{start, start + count}

    pos += count

    sub: Lexer_Token_Sub

    switch state {
        case .NEWLINE: sub = Lexer_Token_Newline(src[:count])
        case .SPACE: sub = Lexer_Token_Spaces(src[:count])
        case .BACKTICK: sub = Lexer_Token_Backtick(src[:count])
        case .WORD: sub = Lexer_Token_Word(src[:count])
        case .MINUS: sub = Lexer_Token_Minus(src[:count])
        case .LEFT_BRACKET: sub = Lexer_Token_Left_Bracket(src[:count])
        case .RIGHT_BRACKET: sub = Lexer_Token_Right_Bracket(src[:count])
        case .NONE: return
    }

    src = src[count:]

    return {extents, sub}, true
}
