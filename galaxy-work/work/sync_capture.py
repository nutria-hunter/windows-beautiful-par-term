"""Screenshot a window at each phase a probe publishes, to see whether a half-applied frame showed.

Pairs with `sync_probe.mjs`: the probe writes its phase name to a file and holds a synchronized
update open, and this takes a picture while the update is still open. If the terminal honours
DEC 2026 the "inside" pictures must still show the previous frame; if they already show the new
content, every streaming repaint is being presented in pieces.

Usage: python sync_capture.py --pid 1234 --phase <phase-file> --out <dir>
"""

import argparse
import ctypes
import os
import sys
import time
from ctypes import wintypes

import numpy as np
from PIL import ImageGrab

user32 = ctypes.windll.user32
user32.SetProcessDPIAware()
WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", wintypes.LONG),
        ("top", wintypes.LONG),
        ("right", wintypes.LONG),
        ("bottom", wintypes.LONG),
    ]


def largest_window(pid):
    best_area = 0
    best_rect = None
    best_hwnd = None

    def callback(hwnd, _lparam):
        nonlocal best_area, best_rect, best_hwnd
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            rect = RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            area = (rect.right - rect.left) * (rect.bottom - rect.top)
            if area > best_area:
                best_area = area
                best_rect = rect
                best_hwnd = hwnd
        return True

    user32.EnumWindows(WNDENUMPROC(callback), 0)
    return best_hwnd, best_rect


def read_phase(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--phase", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--seconds", type=float, default=20.0)
    args = parser.parse_args()

    try:
        os.makedirs(args.out, exist_ok=True)
    except OSError as exc:
        print(f"FAIL: cannot create {args.out}: {exc}")
        sys.exit(1)

    window = largest_window(args.pid)
    if window is None or window[0] is None:
        print(f"FAIL: no visible window for pid {args.pid}")
        sys.exit(1)
    hwnd, rect = window
    # Raise the window before measuring: the screen region belongs to whatever is on top, and a
    # capture of a window that is behind another one measures the wrong pixels entirely.
    HWND_TOPMOST = -1
    SWP_NOSIZE, SWP_NOMOVE, SWP_NOACTIVATE = 0x0001, 0x0002, 0x0010
    user32.SetWindowPos(
        hwnd,
        wintypes.HWND(HWND_TOPMOST),
        0,
        0,
        0,
        0,
        SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE,
    )
    time.sleep(0.4)
    box = (rect.left, rect.top, rect.right, rect.bottom)
    print(f"window={box} size={box[2] - box[0]}x{box[3] - box[1]}")

    deadline = time.time() + args.seconds
    seen = {}
    while time.time() < deadline:
        phase = read_phase(args.phase)
        if phase in ("blank", "inside", "after"):
            seen.setdefault(phase, 0)
            seen[phase] += 1
            if seen[phase] <= (3 if phase == "inside" else 2):
                name = f"{phase}-{seen[phase]}.png"
                try:
                    image = ImageGrab.grab(bbox=box, all_screens=True)
                    image.save(os.path.join(args.out, name))
                except OSError as exc:
                    print(f"FAIL: cannot save {name}: {exc}")
                    sys.exit(1)
                # A signature per frame: identical numbers across phases mean the region is not the
                # window under test at all (something else is drawn on top).
                sample = np.asarray(image.convert("L"))[80:, :]
                print(f"  saved {name} bright={(sample > 140).mean():.4f}")
        elif phase == "done":
            print(f"phase done; counts={seen}")
            return
        time.sleep(0.03)
    print(f"timeout; counts={seen}")


if __name__ == "__main__":
    main()
