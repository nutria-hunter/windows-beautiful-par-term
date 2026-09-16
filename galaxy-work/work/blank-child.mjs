// A child that prints one Hangul syllable and goes quiet.
//
// Used by the preedit screenshot harness. Two things matter:
//
// 1. The terminal only publishes a cursor position once the child has written something - with a
//    totally silent child the preedit overlay is skipped as "no cursor cell".
// 2. Printing Hangul puts a *committed* syllable on the grid in the same window as the composing
//    one the overlay draws. Both are the same character in the same font, so their glyph heights
//    are directly comparable, which is how the overlay's font size is checked against the grid's.
process.stdout.write("\n한\n");
process.stdin.resume();
process.stdin.on("data", () => {});
