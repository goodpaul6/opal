# Opal Notebook

A native alternative to Obsidian. Only has the features I care about.

## Writing Markdown

In insert mode, press Enter at the end of a list item to continue it. Numbered lists increment and task lists start a fresh unchecked item. Press Enter on an empty item to leave the list, or Shift+Enter to insert a plain newline.

In insert mode and at the command prompt, Ctrl+W deletes the previous word. Alt+Left/Right or Alt+B/F move by word, and Alt+Backspace/Delete delete backward/forward by word. On macOS, use Option as Alt. Ctrl+A/Ctrl+E and Home/End move to the start/end of the line.

In Normal mode, press `u` to undo and Ctrl+R to redo.

## Rendering checks

Opal uses raylib. Capture a fixed-size PNG using the same editor renderer as the interactive window:

```sh
odin run . -thread-count:1 -- --screenshot fixtures/markdown-rendering.md /tmp/opal-markdown.png
```

Pass any Markdown file in place of the fixture. Append `--density 2` for a 1600×900 Retina reference with the same logical layout and native 2× glyphs. To exercise fractional and higher framebuffer scales, `--density` accepts 1 through 3 in quarter steps (for example, `--density 1.5` produces 1200×675). Use `--command 'w draft.md'` to capture the command line without executing it. Capture mode uses a hidden window and still needs a graphical session.

### Typing and zoom timings

```sh
odin run . -thread-count:1 -o:speed -define:OPAL_TRACE_INPUT=true
```

The trace writes one line to stderr per frame with input, including key repeats. It reports input handling, caret layout, page layout and drawing, status drawing, and raylib presentation and event polling. A separate line records atlas and metrics preparation whenever a font size is built. The first use of a style can include an atlas build, and the previous zoom level retains its atlases for quick toggling.

### Startup timings

Build once and run the binary with `--benchmark-startup` to time startup without including compilation. It opens a normal window and exits after presenting the first frame. The output breaks out platform window setup, font preparation, first draw, and presentation/event polling.

```sh
odin build . -thread-count:1 -o:speed
./opal --benchmark-startup
```

After changing the bundled Inter font or its atlas codepoints, regenerate its macOS kerning table with:

```sh
odin test . -thread-count:1 -define:OPAL_GENERATE_FONT_PAIRS=true -define:ODIN_TEST_NAMES=main.generate_inter_font_pairs
```

### Text edge contrast

On macOS, Opal strengthens partial glyph coverage when it builds the font atlas. The adjustment gives light text on dark backgrounds more edge contrast and preserves transparent pixels, solid ink, and glyph placement. To compare with the previous rendering, disable the adjustment and capture the same fixture.

```sh
odin run . -thread-count:1 -define:OPAL_TEXT_COVERAGE=false -- --screenshot fixtures/markdown-rendering.md /tmp/opal-coverage-off.png --density 2
```

## TODO

- [x] Add central theme struct
- [x] Add status bar and display current mode
- [x] Add the ability to zoom in and out (with crisp fonts)
- [x] Add command input
- [x] Add `dw` action + motion from Vim
- [x] Add support for undo
- [x] Refactor undo code to be less clown
- [x] Add support for scrolling
- [x] Add support for redo
- [x] Add line wrapping
- [x] Factor our modifier keys into bit_field
- [x] Allow adjusting the bounds of the text display
- [x] Add margin to left and right side when rendering
- [x] Break long individual tokens when wrapping
- [x] Add command parser
- [x] Add support for saving and loading
- [x] Add support for `gg` and `G`
- [x] Add support for `r`
- [x] Add support for `{` and `}` movements
- [x] Modify `wrapped_lines` to be a display data structure instead
- [x] Scroll cursor into view
- [x] Parse text into useful nodes before display gen
- [ ] Switch to GLFW + NanoVG instead
- [ ] Parse using `vendor:commonmark` instead
- [ ] Correctly highlight markdown TODO lists
- [ ] Add ability to flash status for a period of time
- [ ] Add tab completion to commands
- [ ] Refactor undo commit calls to always happen unless a bool is set
- [ ] Add vim end-of-line/start-of-line jk nav behavior
- [ ] Add support for repeat (`.`), very tricky just record keyboard lol
- [ ] Show workspace tree when doing `:E`
- [ ] Add command for new day file
- [ ] Add forward and backward search bindings
- [ ] Add support for copy/paste of text
- [ ] Add support for copy/paste of images
- [ ] Add command to push the current document to `opalnotebook.com`
- [ ] Detect conflicts document push similar to how Git's `--force-with-lease` works
- [ ] Create server for live collaborative editing (maybe using GGPO lol)?

## BUGS

- [ ] When there's a linewrap and a pre right after the wrap, it seems to swap modes
- [ ] Little bug in Odin compiler where it list  `-build-mode:lib` twice in help
- [ ] I can transmute a `^[2]int` to `^[]byte` but I think that's incorrect since `^[2]int` doesn't have the same memory layout as a slice
