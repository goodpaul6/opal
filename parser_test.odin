package main

import "core:testing"

@(test)
test_parser :: proc(t: ^testing.T) {
    list := parser_parse_string("hello world")

    testing.expect_value(t, list.head^, Node{
        next = list.head.next,
        extents = {0, 5},
        sub = Node_Text{text = "hello"},
    })

    testing.expect_value(t, list.head.next^, Node{
        next = list.head.next.next,
        extents = {5, 6},
        sub = Node_Text{all_spaces = true, text = " "},
    })

    testing.expect_value(t, list.head.next.next^, Node{
        extents = {6, 11},
        sub = Node_Text{text = "world"},
    })
}

@(test)
test_parser_inline_code_stops_at_newline :: proc(t: ^testing.T) {
    p := Parser{lex = {"`open\nplain `closed` tail", 0}}
    expected_text := [?]string{"`", "open", "\n", "plain", " ", "`", "closed", "`", " ", "tail"}
    expected_pre := [?]bool{true, true, false, false, false, true, true, true, false, false}

    for text, i in expected_text {
        node, ok := parser_next_node(&p)
        if !testing.expect(t, ok) do return
        testing.expect_value(t, node_edit_string(node), text)
        if sub, is_text := node.sub.(Node_Text); is_text {
            testing.expect_value(t, sub.pre, expected_pre[i])
        }
    }
    _, ok := parser_next_node(&p)
    testing.expect(t, !ok)
}

// Check line classification without losing any source bytes, including newlines.
@(private="file")
expect_markdown_lines :: proc(t: ^testing.T, src: string, lines: []Markdown_Line) {
    p := Parser{lex = {src, 0}}
    offset, line := 0, 0
    for node in parser_next_node(&p) {
        if !testing.expect(t, line < len(lines)) do return
        testing.expect_value(t, p.line, lines[line])
        start, end := node.extents[0], node.extents[1]
        testing.expect_value(t, start, offset)
        if !testing.expect(t, start < end && end <= len(src)) do return
        testing.expect_value(t, node_edit_string(node), src[start:end])
        if text, is_text := node.sub.(Node_Text); is_text {
            if p.line.fenced do testing.expect(t, text.pre)
        } else {
            line += 1
        }
        offset = end
    }
    testing.expect_value(t, offset, len(src))
    testing.expect_value(t, line, len(lines) - (src[len(src)-1] == '\n' ? 0 : 1))
}

@(test)
test_parser_atx_and_quote_prefixes :: proc(t: ^testing.T) {
    src := "# One\n ## Two #\n  ###\tTrois\n   #### 四\n#####\r\n######\n####### text\n#tag\n    # indented\n\t# tabbed\n\\# escaped\n   >é\n>> nested markers\n>\n    > indented\n #"
    expect_markdown_lines(t, src, []Markdown_Line{
        {heading_level = 1}, {heading_level = 2}, {heading_level = 3},
        {heading_level = 4}, {heading_level = 5}, {heading_level = 6},
        {}, {}, {}, {}, {}, {quoted = true}, {quoted = true}, {quoted = true}, {}, {heading_level = 1},
    })
}

@(test)
test_parser_fence_validates_openers_and_closers :: proc(t: ^testing.T) {
    src := "``\n    ~~~ not an opener\n\t~~~ not an opener\n``` invalid `info\n# still a heading\n" +
           "   ````odin\n# café\n\n> literal\n```\n~~~~~\n    ````\n\t````\n```` text\n   ````` \t\r\n> quote again\n" +
           "~~~ info`ok\n\twithin\n  ~~~\t\n## after\n~~~ unclosed\n# literal to EOF"
    code := Markdown_Line{fenced = true}
    expect_markdown_lines(t, src, []Markdown_Line{
        {}, {}, {}, {}, {heading_level = 1},
        code, code, code, code, code, code, code, code, code, code, {quoted = true},
        code, code, code, {heading_level = 2}, code, code,
    })
    expect_markdown_lines(t, "~~~\n  ~~~", []Markdown_Line{code, code})
}
