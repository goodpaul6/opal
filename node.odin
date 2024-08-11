package main

Node_Text :: struct {
    pre: bool,
    // True if the entire text node is spaces
    all_spaces: bool,
    text: string,
}

Node_Todo_Marker :: struct {
    done: bool,
}

Node_Newline :: struct {}

Node_Sub :: union{Node_Text, Node_Todo_Marker, Node_Newline}

Node :: struct {
    next: ^Node,
    extents: [2]int,
    sub: Node_Sub,
}

node_literal_string :: proc(node: Node) -> string {
    switch sub in node.sub {
        case Node_Text: return sub.text
        case Node_Todo_Marker: return sub.done ? "- [x]" : "- [ ]"
        case Node_Newline: return "\n"
    }

    assert(false)
    return ""
}
