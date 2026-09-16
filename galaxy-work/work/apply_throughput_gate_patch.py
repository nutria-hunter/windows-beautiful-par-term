"""Apply throughput-gate patch to frame_setup.rs (CRLF-preserving).

Background: maximize_throughput batching in about_to_wait only gates the
needs_redraw path. PTY-driven redraws arrive via direct request_redraw from
the tab refresh task and bypass it, so every streaming chunk renders its torn
intermediate state (scrolled text, footer not yet redrawn) -> footer judder.
Fix: enforce the throughput interval in should_render_frame, the one choke
point every frame passes through.
"""

import sys
from pathlib import Path

PATH = r"C:/Users/jky72/par-term/build/par-term/src/app/render_pipeline/frame_setup.rs"

OLD = "        let frame_interval = std::time::Duration::from_millis((1000 / target_fps.max(1)) as u64);\n"

NEW = (
    "        // When throughput batching is on, PTY-driven redraws (which arrive via\n"
    "        // direct `request_redraw` from the tab refresh task and bypass the\n"
    "        // `about_to_wait` batching gate) must also be coalesced here — this is\n"
    "        // the one choke point every frame passes through. Otherwise each\n"
    "        // streaming chunk renders its torn intermediate state (scrolled text\n"
    "        // with the footer not yet redrawn) and the footer visibly judders.\n"
    "        let mut interval_ms = (1000 / target_fps.max(1)) as u64;\n"
    "        if self.config.load().rendering.maximize_throughput {\n"
    "            interval_ms = interval_ms\n"
    "                .max(self.config.load().rendering.throughput_render_interval_ms as u64);\n"
    "        }\n"
    "        let frame_interval = std::time::Duration::from_millis(interval_ms);\n"
)


def main() -> int:
    path = Path(PATH)
    try:
        raw = path.read_bytes()
    except OSError as exc:
        print(f"FAIL: cannot read {PATH}: {exc}")
        return 1
    # Detect dominant newline style of the file.
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n") - crlf
    nl = "\r\n" if crlf >= lf else "\n"
    try:
        text = raw.decode("utf-8").replace("\r\n", "\n")
    except UnicodeDecodeError as exc:
        print(f"FAIL: not valid UTF-8: {exc}")
        return 1
    if OLD not in text:
        print("FAIL: old block not found")
        return 1
    occurrences = text.count(OLD)
    if occurrences != 1:
        print(f"FAIL: old block not unique: {occurrences}")
        return 1
    text = text.replace(OLD, NEW)
    out = text.replace("\n", nl).encode("utf-8")
    try:
        path.write_bytes(out)
    except OSError as exc:
        print(f"FAIL: cannot write {PATH}: {exc}")
        return 1
    style = "CRLF" if nl == "\r\n" else "LF"
    print(f"ok frame_setup.rs ({style})")
    return 0


sys.exit(main())
