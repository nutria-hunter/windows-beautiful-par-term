"""Record a live par-term window frame by frame, to measure footer stability.

The complaint is that the pi input footer vibrates while long output streams. That is a
temporal property of the window, so it has to be measured across frames: this grabs the window's
screen region at a fixed interval and keeps the frames, and `analyze_jitter.py` then tracks where
the footer sits in each one.

The window is only read, never moved or resized — it is the user's own session.

Usage:
    python capture_window.py --pid 28428 --seconds 25 --interval 0.15 --tag stream
"""

import argparse
import ctypes
import os
import sys
import time
from ctypes import wintypes

from PIL import ImageGrab

OUT_ROOT = r"C:\Users\jky72\par-term\galaxy-work\outputs\tui-jitter"

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


def windows_of(pid):
    found = []

    def callback(hwnd, _lparam):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            found.append(hwnd)
        return True

    user32.EnumWindows(WNDENUMPROC(callback), 0)
    return found


def largest_window(pid):
    best = (0, None)
    for hwnd in windows_of(pid):
        rect = RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(rect))
        area = (rect.right - rect.left) * (rect.bottom - rect.top)
        if area > best[0]:
            best = (area, rect)
    return best[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=25.0)
    parser.add_argument("--interval", type=float, default=0.15)
    parser.add_argument("--tag", default="stream")
    args = parser.parse_args()

    rect = largest_window(args.pid)
    if rect is None:
        print(f"FAIL: no visible window for pid {args.pid}")
        sys.exit(1)

    out_dir = os.path.join(OUT_ROOT, args.tag)
    try:
        os.makedirs(out_dir, exist_ok=True)
        existing = [name for name in os.listdir(out_dir) if name.endswith(".png")]
    except OSError as exc:
        print(f"FAIL: cannot prepare {out_dir}: {exc}")
        sys.exit(1)
    for name in existing:
        try:
            os.remove(os.path.join(out_dir, name))
        except OSError as exc:
            print(f"FAIL: cannot clear stale frame {name}: {exc}")
            sys.exit(1)

    box = (rect.left, rect.top, rect.right, rect.bottom)
    print(f"pid={args.pid} window={box} size={box[2] - box[0]}x{box[3] - box[1]}")
    print(f"saving to {out_dir}")

    deadline = time.time() + args.seconds
    index = 0
    next_at = time.time()
    while time.time() < deadline:
        frame = ImageGrab.grab(bbox=box, all_screens=True)
        try:
            frame.save(os.path.join(out_dir, f"frame-{index:04d}.png"))
        except OSError as exc:
            print(f"FAIL: cannot write frame {index}: {exc}")
            sys.exit(1)
        index += 1
        next_at += args.interval
        sleep_for = next_at - time.time()
        if sleep_for > 0:
            time.sleep(sleep_for)
    print(f"captured {index} frames")


if __name__ == "__main__":
    main()
