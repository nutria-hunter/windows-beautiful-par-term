// A child that prints one Hangul syllable and leaves the cursor in the NEXT CELL of the same row.
//
// The trailing newline matters: with it, the composition overlay lands on the row below the
// committed syllable, so their vertical placement can only be compared across rows. Without it,
// both sit on one row in adjacent cells and a baseline or size difference in the overlay is
// directly measurable - and directly visible in the capture.
//
// It also gives the terminal a committed syllable to compare against at all, which is what makes
// "the composition looks like a different font" checkable rather than a matter of opinion.
process.stdout.write("\n한");
process.stdin.resume();
process.stdin.on("data", () => {});
