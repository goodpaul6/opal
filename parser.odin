package main

Parser :: struct {
    lex: Lexer,
}

parser_parse_regular_line :: proc(using p: ^Parser) -> List(Node) {
    list := List(Node){}

    in_pre := false

    for {
        token, ok := lexer_next_token(&lex)

        if !ok {
            return list
        }

        is_newline := false
        is_backtick := false
        all_spaces := false

        #partial switch sub in token.sub {
            case Lexer_Token_Newline: is_newline = true
            case Lexer_Token_Backtick: is_backtick = true
            case Lexer_Token_Spaces: all_spaces = true
        }

        sub: Node_Sub = Node_Text{
            pre = (is_backtick && !in_pre) || in_pre,
            all_spaces = all_spaces,
            text = lexer_token_string(token),
        } if !is_newline else Node_Newline{}

        if is_backtick do in_pre = !in_pre

        // TODO(Apaar): Once we have more node types, the extents
        // calculation is gonna be a lil more complex
        node := new(Node, context.temp_allocator)
        node.extents = token.extents
        node.sub = sub

        list_push_back(&list, node)
    }

    return list
}

parser_parse_string :: proc(src: string) -> List(Node) {
    using p := Parser{lex = {src, 0}}

    list := List(Node){}

    for {
        line_nodes := parser_parse_regular_line(&p)

        if list_is_empty(line_nodes) {
            break
        }

        list_append(&list, line_nodes)
    }
    
    return list
}
