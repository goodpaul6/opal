# Opal Notebook

A native alternative to Obsidian. Only has the features I care about.

## TODO

- [x] Add central theme struct
- [x] Add status bar and display current mode
- [x] Add the ability to zoom in and out (with crisp fonts)
- [x] Add command input
* [x] Add `dw` action + motion from Vim
- [x] Add support for undo
- [ ] Refactor undo code to be less clown
- [ ] Add support for redo
- [ ] Show workspace tree when doing `:E`
- [ ] Correctly highlight markdown TODO lists
- [ ] Add command for new day file
- [ ] Add forward and backward search bindings
* [ ] Add support for pasting images
- [ ] Create server for collaborative editing (maybe using ENet)?

## BUGS

- [ ] Little bug in Odin compiler where it lists `-build-mode:lib` twice in help
- [ ] I can transmute a `^[2]int` to `^[]byte` but I think that's incorrect since `^[2]int` doesn't have the same memory layout as a slice
