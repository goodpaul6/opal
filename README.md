# Opal Notebook

A native alternative to Obsidian. Only has the features I care about.

## Canvas

Launch Opal to start a blank board, or pass a `.canvas` filename to reopen one.

- Double-click empty space to create a Markdown card. You can also press `n` or use **New card**.
- Drag a card to move it, or drag its bottom-right handle to resize it. To connect cards, drag from a side handle and release near the side you want on the destination card.
- Double-click an arrow or select it and press Enter to edit its label in place with the same editor as a card. Enter adds a line break. Press Cmd/Ctrl+Enter or click outside to finish. An empty label removes it.
- Drag empty space to pan. Scroll or hold Cmd/Ctrl+Plus or Minus to zoom the board. Press `f` to center the selection at the current zoom, or Shift+F to fit the whole board. Select a card or arrow and press Delete to remove it. On the board, Cmd/Ctrl+Z undoes a change and Cmd/Ctrl+Shift+Z redoes it.
- Card text, padding, and arrow labels scale with board zoom. Wrapping stays the same. Opal reuses glyphs while you scroll and sharpens the text at the new zoom when scrolling stops. The expanded editor uses the regular writing font size.
- Double-click a card or select it and press Enter to edit Markdown in place with Opal's Vim bindings. With a card selected or open, press Cmd/Ctrl+Shift+Enter for a full-page editor. Press the shortcut again or choose **Collapse** to return to the same card in place. Click outside an inline editor, choose **Done**, press Cmd/Ctrl+Enter, or use `:q` to finish editing. The card stores its text inside the canvas file.
- **Save** or Cmd/Ctrl+S saves the whole board from either view. **Open** or Cmd/Ctrl+O opens a board from the canvas view. Type or paste a path and press Enter when prompted.

Boards use [JSON Canvas 1.0](https://jsoncanvas.org/spec/1.0/). Pass a Markdown filename to Opal for the standalone editor, or launch with `--markdown` for a blank note.

### Keyboard canvas

- Use `h`/`j`/`k`/`l` or the arrow keys to select cards by direction. Use `b` to go left and `e` to go right. Hold Shift with the directional keys to pan. Press `i` to create a grid-aligned first card on an empty board or start writing in the selection. Press Enter to open the selected card in Normal mode. From the editor's Normal mode, Esc returns to the board.
- Press `a` to append a card to the right, `o` to open one below, or `O` to open one above. The new card uses the same grid-aligned size as the first card at the current zoom and opens for writing in place.
- Press `m` and use `h`/`j`/`k`/`l` to move a card one visible grid line at a time. Enter places it and Esc cancels.
- Press `r` to resize a card. Use `h`/`l` to narrow or widen it and `k`/`j` to shorten or lengthen it. Enter applies the size and Esc cancels.
- Press `g c` to start an arrow from the selected card. Navigate to an existing card and press Enter, or press `a`, `o`, or `O` to create and connect a new card. While connecting, hold Shift with `h`/`j`/`k`/`l` to choose the destination side, or hold Option/Alt to choose the source side.
- The same directional keys move between cards and arrows. Press Enter on a highlighted arrow to edit its label. Tab also works as a shortcut to a nearby arrow.
- Press `d` or `x` to remove the selected card or arrow, `u` to undo, or Ctrl+R to redo.

## Writing Markdown

In Normal mode, `c` followed by a motion replaces the motion's range and enters Insert mode. Use `cw` to change the rest of a word without consuming the following space, `ce` through the word end, `cc` for the current line, or `C` for the rest of the line. Use `c` in Visual mode to replace the selection. Undo reverts the deletion and replacement together.

In insert mode, press Enter at the end of a list item to continue it. Numbered lists increment and task lists start a fresh unchecked item. Press Enter on an empty item to leave the list, or Shift+Enter to insert a plain newline.

In insert mode and at the command prompt, Ctrl+W deletes the previous word. Alt+Left/Right or Alt+B/F move by word, and Alt+Backspace/Delete delete backward/forward by word. On macOS, use Option as Alt. Ctrl+A/Ctrl+E and Home/End move to the start/end of the line.

On macOS, Cmd+Backspace deletes to the start of the line and Cmd+Forward Delete deletes to the end. Cmd+Left/Right move to the start/end of the line, and Cmd+Up/Down move to the start/end of the document. In the command prompt, these use the ends of the prompt text.

In Normal mode, press `u` to undo and Ctrl+R to redo.

Press Shift+V in Normal mode to select whole lines. Extend the selection with `j`/`k` or ↑/↓, then press `y` to copy or `d` to cut the selection to the system clipboard. In Normal mode, `p` pastes after the caret or line and Shift+P pastes before it. In Visual mode, `p` replaces the selection. Ctrl/Cmd+C copies the selection, and Ctrl/Cmd+V pastes in Normal, Visual, or Insert mode.

Press `v` in Normal mode to select characters. Extend the selection with arrows, `h`/`j`/`k`/`l`, or word motions such as `w`, `b`, and `e`. Dragging in the note enters the same mode. Use `y`, `d`, or `p` as usual.

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

The trace writes one line to stderr per frame with input, including key repeats. It reports input handling, caret layout, page layout and drawing, status drawing, and raylib presentation and event polling. The total starts when Opal begins processing the frame. Idle Opal waits for events without submitting stationary frames. A separate line records atlas and metrics preparation whenever a font size is built. The first use of a style can include an atlas build, and the previous zoom level retains its atlases for quick toggling.

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
