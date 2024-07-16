package main

import "core:testing"

@(test)
test_command_parser :: proc(t: ^testing.T) {
    cmd_src := "w hello.txt"
    cmd := command_parse(&cmd_src)

    testing.expect_value(t, cmd, Command_Write{"hello.txt", false})

    cmd_src = "wq hello.txt"
    cmd = command_parse(&cmd_src)

    testing.expect_value(t, cmd, Command_Write{"hello.txt", true})

    cmd_src = "e hello.txt"
    cmd = command_parse(&cmd_src)

    testing.expect_value(t, cmd, Command_Edit{"hello.txt"})

    cmd_src = "e  "
    bad_cmd, ok := command_parse(&cmd_src)

    testing.expect_value(t, ok, false)

    cmd_src = "e \"hello world.txt\""
    cmd = command_parse(&cmd_src)

    testing.expect_value(t, cmd, Command_Edit{"hello world.txt"})
}
