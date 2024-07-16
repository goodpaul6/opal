package main

import "core:os"
import "core:strings"
import "core:fmt"

// I separated this out into its own file because command.odin is more about parsing?
// Who knows...

// TODO(Apaar): Return error enum
command_run :: proc(cmd: ^Command, ed: ^Editor) -> bool {
    switch c in cmd {
        case Command_Edit: {
            assert(c.filename != "")

            data := os.read_entire_file(c.filename, context.temp_allocator) or_return

            // Fix up line endings
            text := string(data)

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

            os.write_entire_file(filename, transmute([]u8)s) or_return
            editor_set_filename(ed, filename)

            if c.quit {
                // TODO(Apaar): Just close the buffer? Splits? Idk
                ed.exit_requested = true
            }

            return true
        }
    }

    return false
}
