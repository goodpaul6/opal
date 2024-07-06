package main

import rl "vendor:raylib"

Theme_Font :: enum {
    H1,
    BODY
}

Theme :: struct {
    fonts: [Theme_Font]rl.Font,
}

