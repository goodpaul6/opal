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
- [x] Break long individual tokens when wrapping
- [x] Add command parser
- [x] Add support for saving and loading
- [x] Add support for `gg` and `G`
- [ ] Add support for `r`
- [ ] Add support for `{` and `}` movements
- [ ] Add ability to flash status for a period of time
- [ ] Add tab completion to commands
- [ ] Refactor undo commit calls to always happen unless a bool is set
- [ ] Add vim end-of-line/start-of-line jk nav behavior
- [ ] Add support for repeat (`.`), very tricky just record keyboard lol
- [ ] Show workspace tree when doing `:E`
- [ ] Correctly highlight markdown TODO lists
- [ ] Add command for new day file
- [ ] Add forward and backward search bindings
* [ ] Add support for copy/paste of text
* [ ] Add support for copy/paste of images
- [ ] Add command to push the current document to `opalnotebook.com`
- [ ] Detect conflicts document push similar to how Git's `--force-with-lease` works
- [ ] Create server for live collaborative editing (maybe using GGPO lol)?

## BUGS

- [ ] Little bug in Odin compiler where it lists `-build-mode:lib` twice in help
- [ ] I can transmute a `^[2]int` to `^[]byte` but I think that's incorrect since `^[2]int` doesn't have the same memory layout as a slice
