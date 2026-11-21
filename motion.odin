package main

import "core:bytes"
import "core:unicode"
import "core:unicode/utf8"
import rl "vendor:raylib"

Word_Motion :: enum {
    Back,
    End,
    Next,
}

key_to_word_motion :: proc(key: rl.KeyboardKey) -> (Word_Motion, bool) {
    #partial switch key {
        case .B: return .Back, true
        case .E: return .End, true
        case .W: return .Next, true
    }
    return {}, false
}

@(private="file")
Word_Class :: enum {
    Blank,
    Empty_Line,
    Keyword,
    Punctuation,
    Han,
    Hiragana,
    Katakana,
    Hangul,
    Emoji,
}

@(private="file")
word_at_line_start :: proc(buf: []byte, pos: int) -> bool {
    return pos == 0 || buf[pos - 1] == '\n'
}

@(private="file")
word_class :: proc(buf: []byte, pos: int, big_word: bool) -> Word_Class {
    if pos == len(buf) || buf[pos] == '\n' {
        return .Empty_Line if word_at_line_start(buf, pos) else .Blank
    }
    ch, _ := utf8.decode_rune(buf[pos:])
    if ch == ' ' || ch == '\t' || (ch >= 0x80 && unicode.is_space(ch)) do return .Blank
    if big_word do return .Keyword

    // Vim separates these common East Asian scripts even without whitespace.
    switch ch {
        case 0x3040..=0x309f: return .Hiragana
        case 0x30a0..=0x30ff, 0x31f0..=0x31ff, 0xff66..=0xff9f: return .Katakana
        case 0x3400..=0x4dbf, 0x4e00..=0x9fff, 0xf900..=0xfaff, 0x20000..=0x2fa1f: return .Han
        case 0xac00..=0xd7a3: return .Hangul
    }
    if ch == '_' || unicode.is_letter(ch) || unicode.is_number(ch) do return .Keyword
    // Use Odin's pictographic property for emoji instead of a Vim-specific table.
    if unicode.is_emoji_extended_pictographic(ch) && ch >= 0x2600 do return .Emoji
    return .Punctuation
}

@(private="file")
word_previous_char :: proc(buf: []byte, pos: int) -> int {
    pos := pos
    for pos > 0 {
        ch, size := utf8.decode_last_rune(buf[:pos])
        if !unicode.is_combining(ch) || pos == size || buf[pos - size - 1] == '\n' {
            return pos - size
        }
        pos -= size
    }
    return pos
}

@(private="file")
word_next_char :: proc(buf: []byte, pos: int) -> int {
    ch, size := utf8.decode_rune(buf[pos:])
    next := pos + size
    if ch != '\n' {
        for next < len(buf) {
            mark, size := utf8.decode_rune(buf[next:])
            if !unicode.is_combining(mark) do break
            next += size
        }
    }
    return next
}

@(private="package")
word_caret_start :: proc(buf: []byte, pos: int) -> int {
    pos := clamp(pos, 0, len(buf))
    // Other editor motions can set a byte column inside a UTF-8 character.
    for pos > 0 && pos < len(buf) && (buf[pos] & 0xc0) == 0x80 {
        pos -= 1
    }
    for pos > 0 && pos < len(buf) && buf[pos - 1] != '\n' {
        ch, _ := utf8.decode_rune(buf[pos:])
        if !unicode.is_combining(ch) do break
        pos = word_previous_char(buf, pos)
    }
    return pos
}

@(private="file")
word_destination :: proc(buf: []byte, start: int, motion: Word_Motion, big_word: bool, deleting := false) -> int {
    if motion == .Back {
        if start == 0 do return start
        pos := word_previous_char(buf, start)
        for pos > 0 && word_class(buf, pos, big_word) == .Blank {
            pos = word_previous_char(buf, pos)
        }
        class := word_class(buf, pos, big_word)
        if class == .Blank || class == .Empty_Line do return pos
        for pos > 0 {
            prev := word_previous_char(buf, pos)
            if word_class(buf, prev, big_word) != class do break
            pos = prev
        }
        return pos
    }

    if start == len(buf) do return start
    pos := word_next_char(buf, start)
    if motion == .Next {
        class := word_class(buf, start, big_word)
        if deleting && class == .Empty_Line do return pos
        if class != .Blank && class != .Empty_Line {
            for pos < len(buf) && word_class(buf, pos, big_word) == class {
                pos = word_next_char(buf, pos)
            }
        }
        for pos < len(buf) && word_class(buf, pos, big_word) == .Blank {
            // With an operator, w does not consume the newline after a word.
            if deleting && buf[pos] == '\n' do return pos
            pos = word_next_char(buf, pos)
        }
        if deleting do return pos
    } else {
        // Stepping first makes e advance even when already at a word's end.
        for pos < len(buf) {
            class := word_class(buf, pos, big_word)
            if class != .Blank && class != .Empty_Line do break
            pos = word_next_char(buf, pos)
        }
        if pos < len(buf) {
            class := word_class(buf, pos, big_word)
            for next := word_next_char(buf, pos); next < len(buf) && word_class(buf, next, big_word) == class; next = word_next_char(buf, pos) {
                pos = next
            }
        }
    }

    // When there is no next word, Vim stops on the last character (or on the
    // final empty line). Opal also permits an existing caret at the buffer end.
    if pos == len(buf) && !word_at_line_start(buf, pos) do return word_previous_char(buf, pos)
    return pos
}

word_motion_target :: proc(buf: []byte, pos: int, motion: Word_Motion, big_word: bool) -> int {
    return word_destination(buf, word_caret_start(buf, pos), motion, big_word)
}

// Insertion carets land between characters, including after the last word.
@(private="package")
word_edit_target :: proc(buf: []byte, pos: int, backwards: bool) -> int {
    pos := pos
    if backwards do return word_destination(buf, pos, .Back, false)

    for pos < len(buf) {
        class := word_class(buf, pos, false)
        if class != .Blank && class != .Empty_Line do break
        pos = word_next_char(buf, pos)
    }
    if pos == len(buf) do return pos
    class := word_class(buf, pos, false)
    for pos < len(buf) && word_class(buf, pos, false) == class {
        pos = word_next_char(buf, pos)
    }
    return pos
}

// Return the half-open byte selection rather than changing editor state here.
word_delete_range :: proc(buf: []byte, pos: int, motion: Word_Motion, big_word: bool) -> [2]int {
    start := word_caret_start(buf, pos)
    dest := word_destination(buf, start, motion, big_word, deleting = true)
    low, high := min(start, dest), max(start, dest)
    exclusive_end := word_next_char(buf, high) if motion == .End else high
    first_line_start := bytes.last_index_byte(buf[:low], '\n') + 1
    last_line_start := bytes.last_index_byte(buf[:high], '\n') + 1
    if first_line_start == last_line_start do return {low, exclusive_end}

    in_indent := true
    for b in buf[first_line_start:low] {
        if b != ' ' && b != '	' {
            in_indent = false
            break
        }
    }
    if motion != .End && high == last_line_start {
        // Exclusive motions ending at column zero leave that line untouched.
        return {first_line_start, high} if in_indent else {low, high - 1}
    }

    // A multiline delete that would leave only indentation becomes linewise.
    if in_indent {
        tail := exclusive_end
        for tail < len(buf) && (buf[tail] == ' ' || buf[tail] == '	') do tail += 1
        if tail == len(buf) do return {max(0, first_line_start - 1), tail}
        if buf[tail] == '\n' do return {first_line_start, tail + 1}
    }
    return {low, exclusive_end}
}
