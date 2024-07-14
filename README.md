# Opal Notebook

A native alternative to Obsidian. Only has the features I care about.

## TODO

- [x] Add central theme struct
- [x] Add status bar and display current mode
- [x] Add the ability to zoom in and out (with crisp fonts)
- [x] Add command input
* [x] Add `dw` action + motion from Vim
- [x] Add support for undo
- [x] Refactor undo code to be less clown
- [x] Add support for scrolling
- [x] Add support for redo
- [x] Add line wrapping
- [x] Factor our modifier keys into bit_field
- [x] Allow adjusting the bounds of the text display
- [x] Add margin to left and right side when rendering
- [ ] Break long individual tokens when wrapping
- [ ] Add support for saving and loading
- [ ] Add vim end-of-line/start-of-line jk nav behavior
- [ ] Add support for repeat (`.`), very tricky
- [ ] Show workspace tree when doing `:E`
- [ ] Correctly highlight markdown TODO lists
- [ ] Add command for new day file
- [ ] Add forward and backward search bindings
* [ ] Add support for pasting images
- [ ] Add command to push the current document to `opalnotebook.com`
- [ ] Detect conflicts document push similar to how Git's `--force-with-lease` works
- [ ] Create server for live collaborative editing (maybe using GGPO lol)?

## BUGS

- [ ] Little bug in Odin compiler where it lists `-build-mode:lib` twice in help
- [ ] I can transmute a `^[2]int` to `^[]byte` but I think that's incorrect since `^[2]int` doesn't have the same memory layout as a slice
