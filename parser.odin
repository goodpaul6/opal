package main

import "core:strings"
import "core:io"
import "core:fmt"

Parser_Token_Newline :: distinct string
Parser_Token_Spaces :: distinct string
Parser_Token_Word :: distinct string
Parser_Token_Backtick :: distinct string
Parser_Token_Minus :: distinct string

Parser_Token_Sub :: union #no_nil {
    Parser_Token_Newline,
    Parser_Token_Spaces,
    Parser_Token_Word,
    Parser_Token_Backtick,
    Parser_Token_Minus,
}

Parser_Token :: struct {
    // For figuring out where the cursor is, for example
    extents: [2]int,
    sub: Parser_Token_Sub,
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

parser_is_non_newline_space :: proc(ch: rune) -> bool {
    return strings.is_ascii_space(ch) && ch != '\n'
}

parser_is_word_delimiter :: proc(ch: rune) -> bool {
    return ch == '`' || strings.is_ascii_space(ch)
}

parser_token_string :: proc(token: Parser_Token) -> string {
    switch sub in token.sub {
        case Parser_Token_Newline: return string(sub)
        case Parser_Token_Spaces: return string(sub)
        case Parser_Token_Word: return string(sub)
        case Parser_Token_Backtick: return string(sub)
        case Parser_Token_Minus: return string(sub)
    }

    assert(false)
    return ""
}

parser_next_token :: proc(src: ^string, pos: ^int) -> (token: Parser_Token, ok: bool) #optional_ok {
    state: enum {NONE, NEWLINE, SPACE, BACKTICK, MINUS, WORD}

    start := pos^
    count := 0

    reader: strings.Reader
    strings.reader_init(&reader, src^)

    loop: for ch, size in read_rune_iterator(&reader) {
        switch state {
            case .NONE: {
                count += size

                if parser_is_non_newline_space(ch) do state = .SPACE
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
                } else do state = .WORD

                continue loop
            }

            case .NEWLINE:
            case .BACKTICK:
            case .MINUS:

            case .SPACE: {
                if parser_is_non_newline_space(ch) do count += size
                else do break loop

                continue loop
            }

            case .WORD: {
                if parser_is_word_delimiter(ch) {
                    break loop
                }

                count += size
                continue loop
            }
        }
    }

    extents := [2]int{start, start + count}

    pos^ += count

    sub: Parser_Token_Sub

    switch state {
        case .NEWLINE: sub = Parser_Token_Newline(src[:count])
        case .SPACE: sub = Parser_Token_Spaces(src[:count])
        case .BACKTICK: sub = Parser_Token_Backtick(src[:count])
        case .WORD: sub = Parser_Token_Word(src[:count])
        case .MINUS: sub = Parser_Token_Minus(src[:count])
        case .NONE: return
    }

    src ^= src[count:]

    return {extents, sub}, true
}
