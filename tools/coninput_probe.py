"""Log the console input records this child receives, plus the size it reads.

Answers the question the whole resize-pulse approach depends on: does ConPTY
deliver a window-buffer-size event to the child when the terminal resizes (or when
the terminal re-asserts the same size)? If it does, a resize pulse can wake a TUI
that waits for a size event. If it does not, that mechanism cannot work at all.

Usage: python coninput_probe.py [label] [seconds]
"""

import ctypes
import os
import sys
import time
from ctypes import wintypes

LOG = r"C:\Users\jky72\par-term\galaxy-work\outputs\coninput.log"
STD_INPUT_HANDLE = -10
ENABLE_PROCESSED_INPUT = 0x0001
ENABLE_LINE_INPUT = 0x0002
ENABLE_ECHO_INPUT = 0x0004
ENABLE_WINDOW_INPUT = 0x0008
ENABLE_MOUSE_INPUT = 0x0010
ENABLE_INSERT_MODE = 0x0020
ENABLE_QUICK_EDIT_MODE = 0x0040
ENABLE_EXTENDED_FLAGS = 0x0080
ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200
# Only these are legal for an input handle. ConPTY leaves 0x0100 (ENABLE_AUTO_POSITION,
# an output-only flag) set on the input mode, and passing it back makes SetConsoleMode
# fail with ERROR_INVALID_PARAMETER, so the mode has to be masked before reuse.
INPUT_MODE_FLAGS = (
    ENABLE_PROCESSED_INPUT
    | ENABLE_LINE_INPUT
    | ENABLE_ECHO_INPUT
    | ENABLE_WINDOW_INPUT
    | ENABLE_MOUSE_INPUT
    | ENABLE_INSERT_MODE
    | ENABLE_QUICK_EDIT_MODE
    | ENABLE_EXTENDED_FLAGS
    | ENABLE_VIRTUAL_TERMINAL_INPUT
)
WINDOW_BUFFER_SIZE_EVENT = 0x0004
KEY_EVENT = 0x0001
MOUSE_EVENT = 0x0002

KERNEL32 = ctypes.WinDLL("kernel32", use_last_error=True)


class COORD(ctypes.Structure):
    _fields_ = [("X", ctypes.c_short), ("Y", ctypes.c_short)]


class KEY_EVENT_RECORD(ctypes.Structure):
    _fields_ = [
        ("bKeyDown", wintypes.BOOL),
        ("wRepeatCount", wintypes.WORD),
        ("wVirtualKeyCode", wintypes.WORD),
        ("wVirtualScanCode", wintypes.WORD),
        ("uChar", wintypes.WCHAR),
        ("dwControlKeyState", wintypes.DWORD),
    ]


class WINDOW_BUFFER_SIZE_RECORD(ctypes.Structure):
    _fields_ = [("dwSize", COORD)]


class INPUT_RECORD_EVENT(ctypes.Union):
    _fields_ = [
        ("KeyEvent", KEY_EVENT_RECORD),
        ("WindowBufferSizeEvent", WINDOW_BUFFER_SIZE_RECORD),
        ("Padding", ctypes.c_byte * 16),
    ]


class INPUT_RECORD(ctypes.Structure):
    _fields_ = [("EventType", wintypes.WORD), ("Event", INPUT_RECORD_EVENT)]


def emit(line: str) -> None:
    print(line, flush=True)
    try:
        with open(LOG, "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError as exc:
        print(f"PROBE log write failed: {exc}", flush=True)


def current_size() -> str:
    try:
        size = os.get_terminal_size()
        return f"{size.columns}x{size.lines}"
    except OSError as exc:
        return f"ERR({exc})"


def parse_seconds(argv: list[str]) -> float:
    """Read the optional duration argument, rejecting junk with a clear message."""
    if len(argv) <= 2:
        return 20.0
    try:
        return float(argv[2])
    except ValueError:
        print(f"seconds must be a number, got {argv[2]!r}")
        raise SystemExit(2) from None


def main() -> int:
    label = sys.argv[1] if len(sys.argv) > 1 else "run"
    seconds = parse_seconds(sys.argv)

    handle = KERNEL32.GetStdHandle(STD_INPUT_HANDLE)
    emit(f"PROBE {label} --- stdin handle={handle} size_at_start={current_size()}")

    mode = wintypes.DWORD()
    if not KERNEL32.GetConsoleMode(handle, ctypes.byref(mode)):
        emit(
            f"PROBE GetConsoleMode FAILED err={ctypes.get_last_error()} "
            "(stdin is not a console handle -> the child cannot receive size events)"
        )
        return 1
    emit(f"PROBE console input mode before = 0x{mode.value:04X}")

    # ENABLE_WINDOW_INPUT is what makes the console queue resize records. Which
    # combinations ConPTY accepts is not obvious (the full-mode attempt failed with
    # ERROR_INVALID_PARAMETER), so try several and report each outcome.
    base = mode.value & INPUT_MODE_FLAGS
    candidates = {
        "mode|WINDOW": base | ENABLE_WINDOW_INPUT,
        "raw+WINDOW": (
            base & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT)
        )
        | ENABLE_WINDOW_INPUT,
        "raw+WINDOW+EXT": (
            base
            & ~(
                ENABLE_LINE_INPUT
                | ENABLE_ECHO_INPUT
                | ENABLE_PROCESSED_INPUT
                | ENABLE_QUICK_EDIT_MODE
                | ENABLE_INSERT_MODE
            )
        )
        | ENABLE_WINDOW_INPUT
        | ENABLE_EXTENDED_FLAGS,
        "WINDOW only": ENABLE_WINDOW_INPUT | ENABLE_EXTENDED_FLAGS,
    }
    accepted = None
    for name, candidate in candidates.items():
        if KERNEL32.SetConsoleMode(handle, candidate):
            emit(f"PROBE mode '{name}' ACCEPTED (0x{candidate:04X})")
            accepted = candidate
            break
        emit(
            f"PROBE mode '{name}' rejected: 0x{candidate:04X} err={ctypes.get_last_error()}"
        )

    if accepted is None:
        emit(
            "PROBE no window-input mode accepted -> this child cannot receive "
            "console size events; a resize event cannot reach it at all"
        )
        return 2
    emit(f"PROBE console input mode after  = 0x{accepted:04X} (window input enabled)")

    record = INPUT_RECORD()
    read = wintypes.DWORD()
    deadline = time.time() + seconds
    seen = 0
    last_reported = ""

    while time.time() < deadline:
        available = wintypes.DWORD()
        if not KERNEL32.GetNumberOfConsoleInputEvents(handle, ctypes.byref(available)):
            emit(
                f"PROBE GetNumberOfConsoleInputEvents FAILED err={ctypes.get_last_error()}"
            )
            break
        if available.value == 0:
            # No blocking wait: re-check the clock so the probe always stops.
            time.sleep(0.05)
            size = current_size()
            if size != last_reported:
                emit(f"PROBE size changed -> {size}")
                last_reported = size
            continue
        if not KERNEL32.ReadConsoleInputW(
            handle, ctypes.byref(record), 1, ctypes.byref(read)
        ):
            emit(f"PROBE ReadConsoleInputW FAILED err={ctypes.get_last_error()}")
            break
        if record.EventType == WINDOW_BUFFER_SIZE_EVENT:
            size = record.Event.WindowBufferSizeEvent.dwSize
            seen += 1
            emit(
                f"PROBE WINDOW_BUFFER_SIZE_EVENT #{seen}: {size.X}x{size.Y} "
                f"(os.get_terminal_size={current_size()})"
            )
        elif record.EventType == KEY_EVENT:
            key = record.Event.KeyEvent
            if key.bKeyDown:
                emit(
                    f"PROBE key record: vk=0x{key.wVirtualKeyCode:02X} char={key.uChar!r}"
                )
        else:
            emit(f"PROBE record type=0x{record.EventType:04X}")

    emit(
        f"PROBE done: {seen} window-size events in {seconds:.0f}s, final size={current_size()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
