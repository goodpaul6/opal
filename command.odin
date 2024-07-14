package main

import "core:strings"

Command_Write :: struct {
    // Could be empty
    filename: string,
}

Command_Edit :: struct {
    filename: string,
}

Command :: union #no_nil {
    Command_Write,
    Command_Edit,
}

// TODO(Apaar): Break into ident or string
Command_Token_String :: distinct string
Command_Token :: union {Command_Token_String}

// TODO(Apaar): Produce actual error value
command_next_token :: proc(src: ^string) -> (Command_Token, bool) {
    for len(src) > 0 && strings.is_ascii_space(rune(src[0])) {
        src^ = src[1:]
    }

    if len(src) == 0 {
        return nil, false
    }

    if src[0] == '"' {
        tlen := 1

        for i := 1; i < len(src) && src[i] != '"'; i += 1 {
            tlen += 1
        }

        token := Command_Token_String(src[1:tlen])
        src^ = src[tlen + 1:] 
        
        return token, true
    }

    tlen := 0

    for i := 0; i < len(src) && !strings.is_ascii_space(rune(src[i])); i += 1 {
        tlen += 1
    }

    token := Command_Token_String(src[:tlen])
    src^ = src[tlen:]

    return token, true
}

@(private="file")
next_string :: proc(src: ^string) -> (s: string, ok: bool) {
    token := command_next_token(src) or_return

    cs := token.(Command_Token_String) or_return

    return string(cs), true
}

// TODO(Apaar): Indicate error
command_parse :: proc(src: ^string, allocator := context.temp_allocator) -> (cmd: Command, ok: bool) #optional_ok {
    s := next_string(src) or_return

    if s == "w" {
        filename, ok := next_string(src) 

        return Command_Write{strings.clone(filename, allocator)}, true
    }

    if s == "e" {
        filename := next_string(src) or_return

        return Command_Edit{strings.clone(filename, allocator)}, true
    }

    return
}
