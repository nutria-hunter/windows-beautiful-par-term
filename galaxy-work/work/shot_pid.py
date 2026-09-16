"""Grab the largest visible window of one pid and save a crop, to see what text is on it.

Usage: python shot_pid.py --pid 36652 --out shot.png [--box 0,0,420,120]
"""

import argparse
import ctypes
import sys
from ctypes import wintypes

from PIL import ImageGrab

user32 = ctypes.windll.user32
user32.SetProcessDPIAware()
WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


class RECT(ctypes.Structure):
    _fields_ = [
        ("l", wintypes.LONG),
        ("t", wintypes.LONG),
        ("r", wintypes.LONG),
        ("b", wintypes.LONG),
    ]


def largest_window(pid):
    found = []

    def callback(hwnd, _lparam):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            rect = RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            found.append(((rect.r - rect.l) * (rect.b - rect.t), rect))
        return True

    user32.EnumWindows(WNDENUMPROC(callback), 0)
    if not found:
        return None
    found.sort(key=lambda item: -item[0])
    return found[0][1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--box", default="")
    args = parser.parse_args()

    rect = largest_window(args.pid)
    if rect is None:
        print(f"FAIL: no visible window for pid {args.pid}")
        return 1
    image = ImageGrab.grab(bbox=(rect.l, rect.t, rect.r, rect.b), all_screens=True)
    if args.box:
        try:
            x0, y0, x1, y1 = (int(v) for v in args.box.split(","))
        except ValueError:
            print(f"FAIL: --box must be x0,y0,x1,y1 (got {args.box!r})")
            return 1
        image = image.crop((x0, y0, x1, y1)).resize(((x1 - x0) * 2, (y1 - y0) * 2))
    image.save(args.out)
    print(
        f"saved {args.out} {image.size} from rect=({rect.l},{rect.t},{rect.r},{rect.b})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
