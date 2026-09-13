"""Report the terminal geometry this child actually sees.

Run inside a terminal to compare what the terminal *thinks* its grid is against
what the child is told. The child also enters the alternate screen and draws a
box sized from its own view, so a mismatch is visible in a screenshot as well as
in the printed numbers.

Usage: python winsize_probe.py [label]
"""

import os
import shutil
import sys
import time

# Findings also go to a file: the child's view is the evidence, and reading it from
# disk beats transcribing it out of a screenshot.
LOG_PATH = r"C:\Users\jky72\par-term\galaxy-work\outputs\probe.log"


def emit(line: str) -> None:
    """Write one finding to stdout and to the log file."""
    print(line, flush=True)
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError as exc:
        print(f"PROBE log write failed: {exc}", flush=True)


def report(tag: str) -> None:
    """Print every geometry source a TUI might consult."""
    try:
        size = os.get_terminal_size()
        os_size = f"{size.columns}x{size.lines}"
    except OSError as exc:
        os_size = f"ERR({exc})"
    try:
        shutil_size = shutil.get_terminal_size()
        shutil_str = f"{shutil_size.columns}x{shutil_size.lines}"
    except Exception as exc:  # noqa: BLE001 - probe must never abort
        shutil_str = f"ERR({exc})"
    env_cols = os.environ.get("COLUMNS", "<unset>")
    env_lines = os.environ.get("LINES", "<unset>")
    emit(
        f"PROBE {tag}: os.get_terminal_size={os_size} "
        f"shutil={shutil_str} COLUMNS={env_cols} LINES={env_lines}"
    )


def draw_box(cols: int, rows: int) -> None:
    """Draw a box using rows/cols as this child believes them.

    If the believed size is larger than the real grid, the box is clipped or
    scrolls; if smaller, it leaves a visible gap.
    """
    out = ["\x1b[2J\x1b[H"]
    out.append("+" + "-" * max(cols - 2, 0) + "+")
    for _ in range(max(rows - 2, 0)):
        out.append("|" + " " * max(cols - 2, 0) + "|")
    out.append("+" + "-" * max(cols - 2, 0) + "+")
    out.append(f"\x1b[{rows};1HBOX believes {cols}x{rows}")
    sys.stdout.write("\n".join(out))
    sys.stdout.flush()


def main() -> None:
    label = sys.argv[1] if len(sys.argv) > 1 else "default"
    emit(f"PROBE pid={os.getpid()} label={label} ---")
    report("before-alt")

    # Every TUI enters the alternate screen; this is the transition the pulse targets.
    sys.stdout.write("\x1b[?1049h")
    sys.stdout.flush()
    time.sleep(2.0)
    report("after-alt")

    try:
        size = os.get_terminal_size()
        draw_box(size.columns, size.lines)
    except OSError as exc:
        emit(f"PROBE draw_box skipped: {exc}")

    time.sleep(4.0)
    report("final")
    sys.stdout.write("\x1b[?1049l")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
