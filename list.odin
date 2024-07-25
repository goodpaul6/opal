package main

List :: struct($T: typeid) {
    head: ^T,
    tail: ^T,
}

List_Iterator :: struct($T: typeid) {
    // Handy to access the most recent prev node
    prev_node: ^T,
    node: ^T,
}

list_push_back :: proc(list: ^List($T), node: ^T) {
    if list.tail == nil {
        list.head = node
        list.tail = node
        return
    }

    list.tail.next = node
    list.tail = node
}

list_append :: proc(list_a: ^List($T), list_b: List(T)) {
    if list_a.tail == nil {
        list_a.head = list_b.head
        list_a.tail = list_b.tail
        return
    }

    for node := list_b.head; node != nil; node = node.next {
        list_a.tail.next = node
        list_a.tail = node
    }
}

list_is_empty :: proc(list: List($T)) -> bool {
    return list.head == nil
}

list_iterator_make :: proc(list: List($T)) -> List_Iterator(T) {
    return {nil, list.head}
}

list_iterator_iterate :: proc(iter: ^List_Iterator($T)) -> (value: ^T, ok: bool) {
    if iter.node == nil {
        return
    }

    value = iter.node

    iter.prev_node = value
    iter.node = value.next

    ok = true
    return
}

// Go back one node so the next iteration will process the current node again.
// Can only be called once per iteration since we only ever remember one node
// per iteration.
list_iterator_move_back_to_prev_once :: proc(iter: ^List_Iterator($T)) {
    assert(iter.prev_node != nil)

    iter.node = iter.prev_node
    iter.prev_node = nil
}
