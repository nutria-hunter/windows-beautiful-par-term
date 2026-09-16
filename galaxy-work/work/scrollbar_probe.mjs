// Does the reported terminal width change when scrollback appears or is cleared?
//
// par-term hides the scrollbar while there is no scrollback and shows it once there is
// (`should_show_scrollbar`: `scrollback_len == 0` -> false), and its width is carved out of the
// grid. If that width reaches the PTY size, then every appearance or clearing of scrollback is a
// resize: the drawing application re-wraps its whole frame, which is exactly how a footer pinned
// near the bottom starts moving. The events are observable from inside the child, so no screenshot
// is needed.
//
// WRAP_PROBE_OUT is where the JSON result is written.
import fs from "node:fs";

const out = process.env.WRAP_PROBE_OUT;
if (!out) {
  process.stderr.write("WRAP_PROBE_OUT is not set\n");
  process.exit(2);
}

const log = { events: [], samples: [] };
const record = (label) =>
  log.samples.push({
    label,
    columns: process.stdout.columns,
    rows: process.stdout.rows,
  });

process.stdout.on("resize", () => {
  log.events.push({
    at: Date.now(),
    columns: process.stdout.columns,
    rows: process.stdout.rows,
  });
});

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

if (process.stdin.isTTY && typeof process.stdin.setRawMode === "function") {
  process.stdin.setRawMode(true);
}
process.stdin.resume();

process.stdout.write("\x1b[2J\x1b[H");
await sleep(300);
record("start (no scrollback)");

// Enough lines to fill the screen and push content into scrollback.
for (let i = 0; i < (process.stdout.rows || 24) * 3; i += 1) {
  process.stdout.write(`line ${i}\r\n`);
}
await sleep(500);
record("after 3 screens of output (scrollback present)");

// ED 3 clears the scrollback; par-term should then hide the scrollbar again.
process.stdout.write("\x1b[3J");
await sleep(500);
record("after clearing scrollback (ESC[3J)");

// And once more, to see whether the width returns to the first value or sticks.
for (let i = 0; i < (process.stdout.rows || 24) * 3; i += 1) {
  process.stdout.write(`again ${i}\r\n`);
}
await sleep(500);
record("after refilling scrollback");

log.resizeEventCount = log.events.length;
fs.writeFileSync(out, JSON.stringify(log, null, 2));
process.stdout.write("\x1b[2J\x1b[H");
