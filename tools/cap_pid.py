"""Capture the largest visible top-level window owned by a PID (DPI aware).

par-term owns more than one top-level window (a real one plus a 22x22 helper), so
"the last match" catches the helper and every capture comes out useless. Always
select by largest area, as the handoff notes.

Usage: python cap_pid.py <pid> <out.png>
"""

import ctypes
import ctypes.wintypes as wt
import sys

from PIL import ImageGrab

user32 = ctypes.windll.user32
user32.SetProcessDPIAware()

found = []


@ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)
def _cb(hwnd, _lparam):
    pid = wt.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if pid.value != target_pid or not user32.IsWindowVisible(hwnd):
        return True
    rect = wt.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    area = (rect.right - rect.left) * (rect.bottom - rect.top)
    found.append((area, hwnd, rect))
    return True


if len(sys.argv) < 3:
    print("usage: python cap_pid.py <pid> <out.png>")
    sys.exit(2)

try:
    target_pid = int(sys.argv[1])
except ValueError:
    print(f"pid must be an integer, got {sys.argv[1]!r}")
    sys.exit(2)

out = sys.argv[2]
user32.EnumWindows(_cb, 0)

if not found:
    print("no visible window for pid", target_pid)
    sys.exit(1)

area, hwnd, rect = max(found, key=lambda item: item[0])
print(
    f"window {hwnd} area={area} rect=({rect.left},{rect.top})-({rect.right},{rect.bottom})"
)
ImageGrab.grab(
    bbox=(rect.left, rect.top, rect.right, rect.bottom), all_screens=True
).save(out)
print("saved", out)
