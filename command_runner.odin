package main

import "core:os"
import "core:strings"
import "core:fmt"

// I separated this out into its own file because command.odin is more about parsing?
// Who knows...

// TODO(Apaar): Return error enum
command_run :: proc(cmd: ^Command, ed: ^Editor) -> bool {
    if ed.canvas != nil do return canvas_card_command(ed.canvas, ed, cmd)
    switch c in cmd {
        case Command_Edit: {
            assert(c.filename != "")

            data, err := os.read_entire_file(c.filename, context.temp_allocator)
            if err != nil do return false

            // Fix up line endings
            text := string(data)

            display_invalidate_from(ed, 0)
            strings.builder_reset(&ed.sb)

            for line in strings.split_lines_iterator(&text) {
                strings.write_string(&ed.sb, line)
                strings.write_byte(&ed.sb, '\n')
            }

            editor_clamp_cursor_to_buffer(ed)
            editor_set_filename(ed, c.filename)

            return true
        }

        case Command_Write: {
            s := editor_get_text(ed)

            filename := ""

            if c.filename != "" {
                filename = c.filename
            } else {
                filename = strings.to_string(ed.filename)
            }

            if filename == "" {
                fmt.eprintln("No filename")
                return false
            }

            fmt.println("Writing to file", filename)

            if os.write_entire_file(filename, s) != nil do return false
            editor_set_filename(ed, filename)

            if c.quit {
                // TODO(Apaar): Just close the buffer? Splits? Idk
                ed.exit_requested = true
            }

            return true
        }

        case Command_Quit: ed.exit_requested = true
    }

    return false
}
