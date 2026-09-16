// Hold a synchronized update open for seconds, so a screenshot can catch whether the terminal
// shows the half-applied frame.
//
// Synchronized output (DEC 2026) exists so that a multi-step repaint never becomes visible: the
// terminal must keep the previous frame until the closing ESC[?2026l arrives. par-term renders
// continuously (a background shader keeps frames coming at max_fps), so if the markers are lost -
// ConPTY re-renders the screen itself and is free to drop or reorder them - every intermediate step
// of a streaming repaint is presented as its own frame. That is a footer appearing to vibrate.
//
// Phases are published to a file so the capture side can screenshot inside the window without
// guessing at startup timing.
import fs from "node:fs";

const phaseFile = process.env.SYNC_PROBE_PHASE;
const outFile = process.env.WRAP_PROBE_OUT;
if (!phaseFile || !outFile) {
  process.stderr.write("SYNC_PROBE_PHASE and WRAP_PROBE_OUT must be set\n");
  process.exit(2);
}

const rows = process.stdout.rows || 24;
const cols = process.stdout.columns || 80;
const setPhase = (value) => fs.writeFileSync(phaseFile, value);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

if (process.stdin.isTTY && typeof process.stdin.setRawMode === "function") {
  process.stdin.setRawMode(true);
}
process.stdin.resume();

// Blank screen, outside any synchronized update.
process.stdout.write("\x1b[2J\x1b[H");
setPhase("blank");
await sleep(1500);

// A full screen of 'X' inside an update that stays open for a long time.
setPhase("inside");
process.stdout.write("\x1b[?2026h");
const line = "X".repeat(Math.max(1, cols - 1));
for (let row = 0; row < rows - 1; row += 1) {
  process.stdout.write(`\x1b[${row + 1};1H${line}`);
}
await sleep(7000);

// Closing marker: only now may the 'X' screen become visible.
process.stdout.write("\x1b[?2026l");
setPhase("after");
await sleep(700);

fs.writeFileSync(
  outFile,
  JSON.stringify(
    { cols, rows, insideSeconds: 7.0, phases: ["blank", "inside", "after"] },
    null,
    2,
  ),
);
setPhase("done");
