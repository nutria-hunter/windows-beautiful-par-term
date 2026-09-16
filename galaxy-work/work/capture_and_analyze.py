"""Record a live par-term window and report whether its footer oscillates.

Self-contained on purpose: it is launched detached (no shell quoting to fight) and must print its
own verdict, because the measurement has to run *while* output streams into the window.

The footer is the boxed input area at the bottom. Its top border is a long horizontal run of ink,
which is unique enough in the lower half of the window to locate per frame. A footer that only
scrolls as content grows moves monotonically; vibration is the row changing direction.

Usage (Windows-style args, launched from cmd/PowerShell):
  python capture_and_analyze.py --pid 28428 --seconds 25 --interval 0.12
"""

import argparse
import ctypes
import os
import sys
import time
from ctypes import wintypes

import numpy as np
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


def largest_window(pid):
    best_area = 0
    best_rect = None

    def callback(hwnd, _lparam):
        nonlocal best_area, best_rect
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            rect = RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            area = (rect.right - rect.left) * (rect.bottom - rect.top)
            if area > best_area:
                best_area = area
                best_rect = rect
        return True

    user32.EnumWindows(WNDENUMPROC(callback), 0)
    return best_rect


def footer_row(mask):
    """Row of the footer border: longest horizontal ink run in the lower 45% of the frame."""
    height = mask.shape[0]
    lower = slice(height * 55 // 100, height)
    region = mask[lower, :]
    best_row, best_len = None, 0
    for offset in range(region.shape[0]):
        row = region[offset]
        padded = np.concatenate(([False], row, [False]))
        edges = np.diff(padded.astype(np.int8))
        starts = np.flatnonzero(edges == 1)
        ends = np.flatnonzero(edges == -1)
        if len(starts) == 0:
            continue
        try:
            run = max(int(end - start) for start, end in zip(starts, ends, strict=True))
        except (TypeError, ValueError) as exc:
            print(f"FAIL: cannot measure a run in row {offset}: {exc}")
            sys.exit(1)
        if run > best_len:
            best_len, best_row = run, offset + lower.start
    if best_len < mask.shape[1] * 0.2:
        return None
    return best_row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=25.0)
    parser.add_argument("--interval", type=float, default=0.12)
    parser.add_argument("--tag", default="stream")
    args = parser.parse_args()

    try:
        os.makedirs(OUT_ROOT, exist_ok=True)
    except OSError as exc:
        print(f"FAIL: cannot create {OUT_ROOT}: {exc}")
        sys.exit(1)

    rect = largest_window(args.pid)
    if rect is None:
        print(f"FAIL: no visible window for pid {args.pid}")
        sys.exit(1)
    print(f"pid={args.pid} rect=({rect.left},{rect.top},{rect.right},{rect.bottom})")
    print(
        f"capturing for {args.seconds}s at {args.interval}s -> measuring the footer row"
    )

    rows = []
    deadline = time.time() + args.seconds
    next_at = time.time()
    index = 0
    while time.time() < deadline:
        box = (rect.left, rect.top, rect.right, rect.bottom)
        try:
            image = ImageGrab.grab(bbox=box, all_screens=True)
        except OSError as exc:
            print(f"FAIL: cannot grab the screen: {exc}")
            sys.exit(1)
        mask = np.asarray(image.convert("L")).astype(np.int16) > 90
        row = footer_row(mask)
        rows.append(row)
        if index % 10 == 0:
            print(f"  frame {index:03d} footer_row={row}")
        index += 1
        next_at += args.interval
        wait = next_at - time.time()
        if wait > 0:
            time.sleep(wait)

    found = [row for row in rows if row is not None]
    print(f"frames={len(rows)} located={len(found)}")
    if not found:
        print("verdict: the footer border was never located; nothing to say")
        return

    compact = []
    for row in found:
        if not compact or compact[-1] != row:
            compact.append(row)
    changes = sum(
        1
        for index in range(1, len(compact) - 1)
        if (compact[index] - compact[index - 1]) * (compact[index + 1] - compact[index])
        < 0
    )
    print(f"row range={min(found)}..{max(found)} distinct={sorted(set(found))}")
    print(f"transitions={len(compact) - 1} direction_changes={changes}")
    print("VERDICT: " + ("VIBRATION" if changes >= 3 else "stable or monotonic"))


if __name__ == "__main__":
    main()
