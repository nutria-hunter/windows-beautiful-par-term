// Capture child: records every byte a terminal sends it, as hex, one chunk per line.
//
// Used to verify input paths objectively instead of by reading screenshots: the shell or TUI
// under test is replaced by this, so what the terminal actually delivered can be diffed against
// the expected UTF-8 bytes (e.g. "한" is ed959c). par-term sets IME_CAPTURE_OUT in the
// environment before launching, and the child inherits it.
import fs from "node:fs";

const out = process.env.IME_CAPTURE_OUT;
if (!out) {
  process.stderr.write("IME_CAPTURE_OUT is not set\n");
  process.exit(2);
}
fs.writeFileSync(out, "");

process.stdin.resume();
process.stdin.on("data", (data) =>
  fs.appendFileSync(out, `${data.toString("hex")}\n`),
);
