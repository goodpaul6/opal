package main

import "core:slice"

editor_undo_track :: proc(using ed: ^Editor, data: $T) {
    append(&undo_trackers, Editor_Undo_Tracker{
        orig_data = slice.clone(data[:]),
        data = data,
    })
}

editor_undo_commit :: proc(using ed: ^Editor) {
    for &item in redos {
        delete(item.data)
    }
    clear(&redos)

    placed_nil := false

    for tracker in undo_trackers {
        is_equal := false

        switch v in tracker.data {
            case ^[dynamic]byte: is_equal = slice.equal(tracker.orig_data, v[:])
            case []byte: is_equal = slice.equal(tracker.orig_data, v[:])
        }

        if is_equal {
            delete(tracker.orig_data)
            continue
        }

        if !placed_nil {
            // Add nil undo item to delimit changes
            append(&undos, Editor_Undo_Item{})
            placed_nil = true
        }

        item := Editor_Undo_Item{
            data = tracker.orig_data,
            dest = tracker.data,
        }

        append(&undos, item)
    }

    clear(&undo_trackers)
}

editor_apply_undo_items :: proc(
    using ed: ^Editor, 
    // If this is 'undos', 'reverse_items' is 'redos' and vice versa
    items: ^[dynamic]Editor_Undo_Item, 
    reverse_items: ^[dynamic]Editor_Undo_Item
) {
    placed_nil := false

    for {
        item := pop_safe(items) or_break

        if item.dest == nil {
            break
        }

        if !placed_nil {
            // Add nil item to other stack to delimit changes
            append(reverse_items, Editor_Undo_Item{})
            placed_nil = true
        }

        // We also push the _current_ state of undo_item.dest onto the redo stack
        switch v in item.dest {
            case ^[dynamic]byte:
                reverse_item := Editor_Undo_Item{
                    data = slice.clone(v[:]),
                    dest = item.dest,
                }

                append(reverse_items, reverse_item)

                resize(v, len(item.data))
                copy(v[:], item.data)
                delete(item.data)

            case []byte:
                // HACK(Apaar): Copy-pasta from above, but meh
                reverse_item := Editor_Undo_Item{
                    data = slice.clone(v[:]),
                    dest = item.dest,
                }

                append(reverse_items, reverse_item)

                // Slices should only be tracked when the data does not change in size (even if it is modified).
                // If the size changes, then you better use a dynamic array.
                assert(len(v) == len(item.data))
                copy(v[:], item.data)
                delete(item.data)
        }
    }
}

editor_undo :: proc(using ed: ^Editor) {
    editor_apply_undo_items(ed, &undos, &redos)
}

editor_redo :: proc(using ed: ^Editor) {
    editor_apply_undo_items(ed, &redos, &undos)
}

