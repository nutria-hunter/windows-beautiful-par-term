"""Grab the terminal window repeatedly, so whatever is on screen can be inspected afterwards.

The IME composition box cannot be photographed on request: it lives only while the terminal has
focus, and asking for a screenshot is a click that closes it. It also does not appear to be a
top-level window (watching for one found nothing), so the screen is the only place it can be
caught.

This just records frames - no trigger, no coordination with whoever is typing. The frames are
downscaled and written as PNGs; a separate pass finds the ones that differ from the rest, which is
where an extra box would show up.

Usage: python grab_frames.py --pid 37376 --seconds 180 --fps 1 --out ..\\outputs\\ime-preedit\\grab
"""

import argparse
import ctypes
import os
import sys
import time
from ctypes import wintypes

from PIL import ImageGrab

user32 = ctypes.windll.user32
user32.SetProcessDPIAware()
WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
SCALE = 0.5


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", wintypes.LONG),
        ("top", wintypes.LONG),
        ("right", wintypes.LONG),
        ("bottom", wintypes.LONG),
    ]


def largest_window(pid):
    found = []

    def callback(hwnd, _lparam):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            rect = RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            found.append(((rect.right - rect.left) * (rect.bottom - rect.top), rect))
        return True

    user32.EnumWindows(WNDENUMPROC(callback), 0)
    if not found:
        return None
    found.sort(key=lambda item: -item[0])
    return found[0][1]


def scaled(value, factor):
    """Scaled dimension, refusing to continue on a value that cannot be converted."""
    try:
        return max(1, int(value * factor))
    except (TypeError, ValueError) as exc:
        print(f"FAIL: cannot scale {value!r}: {exc}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=180.0)
    parser.add_argument("--fps", type=float, default=1.0)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    rect = largest_window(args.pid)
    if rect is None:
        print(f"FAIL: no visible window for pid {args.pid}")
        return 1
    box = (rect.left, rect.top, rect.right, rect.bottom)
    print(
        f"grabing {box} ({box[2] - box[0]}x{box[3] - box[1]}) at {args.fps} fps -> {args.out}"
    )

    try:
        os.makedirs(args.out, exist_ok=True)
    except OSError as exc:
        print(f"FAIL: cannot create {args.out}: {exc}")
        return 1

    interval = 1.0 / max(args.fps, 0.1)
    deadline = time.time() + args.seconds
    index = 0
    written = 0
    while time.time() < deadline:
        if largest_window(args.pid) is None:
            print("window closed; stopping")
            break
        try:
            image = ImageGrab.grab(bbox=box, all_screens=True)
        except OSError as exc:
            print(f"FAIL: cannot grab the screen: {exc}")
            return 1
        small = image.convert("L").resize(
            (scaled(image.width, SCALE), scaled(image.height, SCALE))
        )
        path = os.path.join(args.out, f"f{index:04d}.png")
        small.save(path)
        written += 1
        index += 1
        wait = deadline - time.time()
        if wait <= 0:
            break
        time.sleep(min(interval, wait))

    print(f"done: {written} frames in {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
