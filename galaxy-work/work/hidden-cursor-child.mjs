// A child that hides the terminal cursor, prints one Hangul syllable, and goes quiet.
//
// Mirrors what a TUI does: pi (and most TUIs) draw their own caret in a chat input box and turn
// DECTCEM off, so the terminal cursor is not where the text is being typed. The preedit overlay
// looks up its cell from the cursor position the render pipeline publishes, and that publication
// is visibility-gated - so this child is how "the composition does not show up in pi's chat input"
// gets reproduced outside pi.
process.stdout.write("\x1b[?25l\n한\n");
process.stdin.resume();
process.stdin.on("data", () => {});
