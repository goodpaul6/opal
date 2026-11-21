package main

import "core:strings"

Markdown_Line :: struct {
    heading_level: int,
    quoted: bool,
    fenced: bool,
}

Parser :: struct {
    lex: Lexer,
    in_pre: bool,
    line_start: int,
    line: Markdown_Line,
    fence_marker: byte,
    fence_length: int,
    fence_delimiter: bool,
}

@(private="file")
parser_classify_line :: proc(p: ^Parser) -> Markdown_Line {
    p.fence_delimiter = false
    src := p.lex.src
    line := Markdown_Line{fenced = p.fence_length != 0}
    indent := 0
    for indent < len(src) && indent < 3 && src[indent] == ' ' do indent += 1
    src = src[indent:]
    if len(src) == 0 do return line

    marker := src[0]
    if marker == '`' || marker == '~' {
        if line.fenced && marker != p.fence_marker do return line
        run := 1
        for run < len(src) && src[run] == marker do run += 1
        if run < max(3, p.fence_length) do return line

        tail := src[run:]
        if lf := strings.index_byte(tail, '\n'); lf >= 0 {
            tail = tail[:lf]
            if len(tail) > 0 && tail[len(tail)-1] == '\r' do tail = tail[:len(tail)-1]
        }
        if line.fenced {
            for ch in tail {
                if ch != ' ' && ch != '\t' do return line
            }
            // The closing line itself is still code.
            p.fence_length = 0
            p.fence_delimiter = true
        } else if marker != '`' || strings.index_byte(tail, '`') < 0 {
            p.fence_marker = marker
            p.fence_length = run
            line.fenced = true
            p.fence_delimiter = true
        }
    } else if !line.fenced {
        if marker == '>' {
            line.quoted = true
        } else if marker == '#' {
            run := 1
            for run < len(src) && run <= 6 && src[run] == '#' do run += 1
            if run <= 6 && (run == len(src) || src[run] == ' ' || src[run] == '\t' || src[run] == '\n' ||
                            (src[run] == '\r' && run + 1 < len(src) && src[run+1] == '\n')) {
                line.heading_level = run
            }
        }
    }
    return line
}

parser_next_node :: proc(p: ^Parser) -> (node: Node, ok: bool) #optional_ok {
    if len(p.lex.src) > 0 && p.lex.pos == p.line_start do p.line = parser_classify_line(p)

    token, has_token := lexer_next_token(&p.lex)
    if !has_token {
        return
    }

    node.extents = token.extents
    if _, is_newline := token.sub.(Lexer_Token_Newline); is_newline {
        p.in_pre = false
        p.line_start = p.lex.pos
        node.sub = Node_Newline{}
        return node, true
    }

    _, is_backtick := token.sub.(Lexer_Token_Backtick)
    _, all_spaces := token.sub.(Lexer_Token_Spaces)
    node.sub = Node_Text{
        pre = p.line.fenced || is_backtick || p.in_pre,
        all_spaces = all_spaces,
        text = lexer_token_string(token),
    }

    if is_backtick && !p.line.fenced do p.in_pre = !p.in_pre

    return node, true
}

parser_parse_regular_line :: proc(p: ^Parser) -> List(Node) {
    list := List(Node){}
    for value in parser_next_node(p) {
        node := new(Node, context.temp_allocator)
        node^ = value
        list_push_back(&list, node)

        if _, is_newline := value.sub.(Node_Newline); is_newline do break
    }
    return list
}

parser_parse_string :: proc(src: string) -> List(Node) {
    p := Parser{lex = {src, 0}}
    list := List(Node){}

    for {
        line_nodes := parser_parse_regular_line(&p)
        if list_is_empty(line_nodes) do break
        list_append(&list, line_nodes)
    }

    return list
}
