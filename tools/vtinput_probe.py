"""Log the raw bytes this child receives, mimicking what a TUI does.

The previous key probe turned window-input mode on, which disables VT input and
therefore breaks the very path being tested. This one does the opposite: it puts the
console in raw VT-input mode — exactly what a TUI such as pi does — and then reads
stdin, so whatever arrives here is what pi would have received.

Usage: python vtinput_probe.py [seconds]
"""

import ctypes
import os
import sys
import time
from ctypes import wintypes
from pathlib import Path

LOG = r"C:\Users\jky72\par-term\galaxy-work\outputs\vtinput.log"
STD_INPUT_HANDLE = -10
ENABLE_PROCESSED_INPUT = 0x0001
ENABLE_LINE_INPUT = 0x0002
ENABLE_ECHO_INPUT = 0x0004
ENABLE_EXTENDED_FLAGS = 0x0080
ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200

KERNEL32 = ctypes.WinDLL("kernel32", use_last_error=True)
KERNEL32.GetStdHandle.argtypes = [wintypes.DWORD]
KERNEL32.GetStdHandle.restype = wintypes.HANDLE
KERNEL32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
KERNEL32.WaitForSingleObject.restype = wintypes.DWORD
WAIT_OBJECT_0 = 0x00000000


def emit(line: str) -> None:
    print(line, flush=True)
    try:
        with Path(LOG).open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError as exc:
        print(f"PROBE log write failed: {exc}", flush=True)


def parse_seconds(argv: list[str]) -> float:
    if len(argv) <= 1:
        return 20.0
    try:
        return float(argv[1])
    except ValueError:
        print(f"seconds must be a number, got {argv[1]!r}")
        raise SystemExit(2) from None


def main() -> int:
    seconds = parse_seconds(sys.argv)
    handle = KERNEL32.GetStdHandle(STD_INPUT_HANDLE)
    mode = wintypes.DWORD()
    if not KERNEL32.GetConsoleMode(handle, ctypes.byref(mode)):
        emit(f"PROBE GetConsoleMode FAILED err={ctypes.get_last_error()}")
        return 1
    # Raw VT input: no line buffering, no echo, and VT sequences instead of records.
    wanted = (
        (mode.value & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT))
        | ENABLE_EXTENDED_FLAGS
        | ENABLE_VIRTUAL_TERMINAL_INPUT
    ) & ~0x0100
    if not KERNEL32.SetConsoleMode(handle, wanted):
        emit(
            f"PROBE SetConsoleMode FAILED err={ctypes.get_last_error()} (wanted 0x{wanted:04X})"
        )
        return 1
    emit(f"PROBE VT-input mode 0x{wanted:04X}; reading stdin for {seconds:.0f}s")
    emit(f"PROBE size={os.get_terminal_size().columns}x{os.get_terminal_size().lines}")

    fd = 0
    deadline = time.time() + seconds
    total = 0
    while time.time() < deadline:
        # A console handle cannot be put in non-blocking mode, so wait on it first and
        # only read once input is actually pending.
        if KERNEL32.WaitForSingleObject(handle, 100) != WAIT_OBJECT_0:
            continue
        try:
            chunk = os.read(fd, 256)
        except OSError as exc:
            emit(f"PROBE read error: {exc}")
            break
        if chunk:
            total += len(chunk)
            emit(f"PROBE bytes #{total}: {chunk.hex(' ')}  repr={chunk!r}")
    emit(f"PROBE done: {total} bytes received")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
