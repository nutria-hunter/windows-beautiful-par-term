// Ask the terminal (through par-term's ConPTY) how it actually handles line wrapping.
//
// The complaint is that pi's input footer vibrates whenever long output wraps. A footer that moves
// by one row per wrapped line is what happens when the terminal's wrap/cursor semantics differ from
// what the drawing application assumed - a full-width line that the terminal treats as "one extra
// row", a pending-wrap cursor that a following CR LF moves two rows instead of one, or a wide
// character counted as one cell by the app and two by the terminal. All of those are measurable
// without a screenshot: write a known string and ask the terminal where the cursor is (CPR, ESC[6n).
//
// Results are written as JSON to WRAP_PROBE_OUT so the value can be read back without a human
// watching the window.
import fs from "node:fs";

const out = process.env.WRAP_PROBE_OUT;
if (!out) {
  process.stderr.write("WRAP_PROBE_OUT is not set\n");
  process.exit(2);
}

const result = {
  believes: { columns: process.stdout.columns, rows: process.stdout.rows },
  steps: [],
};

let pending = [];
process.stdin.resume();
process.stdin.on("data", (chunk) => {
  pending.push(chunk.toString("latin1"));
});

// A console in cooked (line) mode buffers input until Enter, so a device reply written by the
// terminal would sit in the buffer unseen - raw mode is what makes the answer readable at all.
if (process.stdin.isTTY && typeof process.stdin.setRawMode === "function") {
  process.stdin.setRawMode(true);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function readCpr() {
  const text = pending.join("");
  pending = [];
  const match = /\x1b\[(\d+);(\d+)R/.exec(text);
  if (!match) return null;
  return { row: Number(match[1]), col: Number(match[2]) };
}

// Returns the cursor position the terminal reports after `label`, or null when it stayed silent.
async function probe(label, writeAction) {
  writeAction();
  process.stdout.write("\x1b[6n");
  let cpr = null;
  for (let attempt = 0; attempt < 8 && cpr === null; attempt += 1) {
    await sleep(100);
    cpr = readCpr();
  }
  result.steps.push({ label, cpr });
  return cpr;
}

const cols = process.stdout.columns || 80;
const rows = process.stdout.rows || 24;

process.stdout.write("\x1b[2J\x1b[H");
await sleep(150);

await probe("home", () => {});
await probe(`${cols} x 'x' (full row)`, () =>
  process.stdout.write("x".repeat(cols)),
);
await probe("then one more 'y' (forces the pending wrap)", () =>
  process.stdout.write("y"),
);
await probe("then CR LF", () => process.stdout.write("\r\n"));
await probe("wide char U+D55C (Hangul, East Asian Width = 2)", () =>
  process.stdout.write("\uD55C"),
);
await probe("wide char then CR LF", () => process.stdout.write("\r\n"));
await probe(`full row of U+D55C (${Math.floor(cols / 2)} chars)`, () =>
  process.stdout.write("\uD55C".repeat(Math.floor(cols / 2))),
);
await probe("then one ASCII 'z' after that full wide row", () =>
  process.stdout.write("z"),
);

result.columnsUsed = cols;
result.rowsUsed = rows;
fs.writeFileSync(out, JSON.stringify(result, null, 2));
process.stdout.write("\x1b[2J\x1b[H");
