package main

import "core:strings"

Command_Quit :: struct {}
Command_Color :: struct {}
Command_Theme :: struct { choice: Theme_Choice }

Command_Write :: struct {
    // Could be empty
    filename: string,
    quit: bool,
}

Command_Edit :: struct {
    filename: string,
    discard_changes: bool,
}

Command :: union #no_nil {
    Command_Quit,
    Command_Write,
    Command_Edit,
    Command_Theme,
    Command_Color,
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
        if tlen == len(src) do return nil, false

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

    if s == "w" || s == "wq" {
        filename: string
        if strings.trim_space(src^) != "" {
            filename = next_string(src) or_return
        }

        return Command_Write{
            strings.clone(filename, allocator),
            s == "wq",
        }, true
    }

    if s == "e" || s == "e!" {
        filename := next_string(src) or_return
        if filename == "" do return

        return Command_Edit{strings.clone(filename, allocator), s == "e!"}, true
    }

    if s == "q" {
        return Command_Quit{}, true
    }

    if s == "theme" {
        switch strings.trim_space(src^) {
            case "": return Command_Theme{.TOGGLE}, true
            case "dark": return Command_Theme{.DARK}, true
            case "light": return Command_Theme{.LIGHT}, true
        }
    }
    if (s == "color" || s == "col") && strings.trim_space(src^) == "" do return Command_Color{}, true
    return
}
