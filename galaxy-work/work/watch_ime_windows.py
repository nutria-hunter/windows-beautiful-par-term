"""Watch for an IME composition box appearing, without needing anyone to hold it.

A composition window lives only while the terminal has focus, so "type something and hold it while
you tell me" cannot work: reporting it requires clicking away, which is what closes it. This polls
instead, and prints only the changes, so the caller can type normally and read the answer
afterwards.

It answers one question: which process owns the box - `TextInputHost.exe` (a TSF UI element, which
no option of the application can hide) or par-term itself (the legacy IMM32 UI window, which
`ime_composition::hide_ime_ui` hides).

Candidate classes are the ones Windows IMEs use for their own UI: `IME`, `Default IME`,
`MSCTFIME UI`, `IME Toolbar`. Any window owned by `TextInputHost.exe` counts too.

Usage: python watch_ime_windows.py --pid 41812 --seconds 180
"""

import argparse
import ctypes
import sys
import time
from ctypes import wintypes

user32 = ctypes.windll.user32
imm32 = ctypes.windll.imm32
kernel32 = ctypes.windll.kernel32
dwmapi = ctypes.windll.dwmapi
user32.SetProcessDPIAware()
WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
DWMWA_CLOAKED = 14
IME_CLASSES = ("ime", "default ime", "msctfime ui", "ime toolbar", "ime ui")


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", wintypes.LONG),
        ("top", wintypes.LONG),
        ("right", wintypes.LONG),
        ("bottom", wintypes.LONG),
    ]


def process_name(pid):
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return f"pid:{pid}"
    try:
        buf = ctypes.create_unicode_buffer(260)
        size = wintypes.DWORD(len(buf))
        if kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
            return buf.value.rsplit("\\", 1)[-1]
        return f"pid:{pid}"
    finally:
        kernel32.CloseHandle(handle)


def class_name(hwnd):
    buf = ctypes.create_unicode_buffer(256)
    user32.GetClassNameW(hwnd, buf, 256)
    return buf.value


def cloaked(hwnd):
    value = wintypes.DWORD()
    if (
        dwmapi.DwmGetWindowAttribute(
            hwnd, DWMWA_CLOAKED, ctypes.byref(value), ctypes.sizeof(value)
        )
        != 0
    ):
        return None
    return bool(value.value)


def snapshot(pid, ime_ui_hwnd):
    """Map of interesting windows -> a description string, for change detection."""
    state = {}

    def consider(hwnd, owner_pid, why):
        rect = RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(rect))
        w = rect.right - rect.left
        h = rect.bottom - rect.top
        state[hwnd] = (
            f"{process_name(owner_pid)} class={class_name(hwnd)!r} ({why}) "
            f"{'visible' if user32.IsWindowVisible(hwnd) else 'hidden'} "
            f"cloaked={cloaked(hwnd)} at=({rect.left},{rect.top}) {w}x{h}"
        )

    def callback(hwnd, _lparam):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        name = process_name(owner.value).lower()
        if name == "textinputhost.exe":
            consider(hwnd, owner.value, "TextInputHost")
        elif owner.value == pid and class_name(hwnd).lower() in IME_CLASSES:
            consider(hwnd, owner.value, "par-term IME class")
        return True

    user32.EnumWindows(WNDENUMPROC(callback), 0)
    if ime_ui_hwnd:
        own = wintypes.DWORD()
        user32.GetWindowThreadProcessId(ime_ui_hwnd, ctypes.byref(own))
        consider(ime_ui_hwnd, own.value, "ImmGetDefaultIMEWnd")
    return state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=180.0)
    parser.add_argument("--interval", type=float, default=0.15)
    args = parser.parse_args()

    target = None
    found = []

    def find(hwnd, _lparam):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == args.pid and user32.IsWindowVisible(hwnd):
            rect = RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            found.append(((rect.right - rect.left) * (rect.bottom - rect.top), hwnd))
        return True

    user32.EnumWindows(WNDENUMPROC(find), 0)
    if not found:
        print(f"FAIL: no visible window for pid {args.pid}")
        return 1
    found.sort(key=lambda item: -item[0])
    target = found[0][1]
    ime_ui = imm32.ImmGetDefaultIMEWnd(target)
    print(
        f"watching pid={args.pid} (hwnd=0x{target:x}) for {args.seconds}s; ImmGetDefaultIMEWnd=0x{ime_ui:x}"
    )

    seen = {}
    previous = None
    deadline = time.time() + args.seconds
    while time.time() < deadline:
        current = snapshot(args.pid, ime_ui)
        for hwnd, desc in current.items():
            seen[hwnd] = seen.get(hwnd, 0) + 1
            if previous is None or previous.get(hwnd) != desc:
                print(f"[{time.strftime('%H:%M:%S')}] + 0x{hwnd:x} {desc}", flush=True)
        if previous is not None:
            for hwnd, desc in previous.items():
                if hwnd not in current:
                    print(
                        f"[{time.strftime('%H:%M:%S')}] - 0x{hwnd:x} {desc}", flush=True
                    )
        previous = current
        time.sleep(args.interval)

    print()
    print("most persistent windows (polls seen):")
    for hwnd, count in sorted(seen.items(), key=lambda item: -item[1])[:6]:
        print(f"  0x{hwnd:x}  {count} polls")
    return 0


if __name__ == "__main__":
    sys.exit(main())
