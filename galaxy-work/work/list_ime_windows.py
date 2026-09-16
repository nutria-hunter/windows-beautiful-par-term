"""List every top-level window that could be drawing an IME composition box.

Windows 11 draws the composition UI for a TSF-based IME from `TextInputHost.exe`, in a window that
belongs to *that* process - so nothing an application does with the IME flags (`ISC_SHOWUI*`) or
with its own IME UI window can hide it. This distinguishes the two cases while a composition is
actually open:

- a window owned by `TextInputHost.exe` (or another process) sitting near the caret  -> TSF UI
  element, out of the application's control (needs TSF integration, or the legacy IME).
- a window owned by par-term itself, returned by `ImmGetDefaultIMEWnd`              -> the legacy
  IMM32 UI window, which `ime_composition::hide_ime_ui` hides.

Usage: python list_ime_windows.py --pid <par-term pid>      (hold a composition open, then run)
"""

import argparse
import ctypes
import sys
from ctypes import wintypes

user32 = ctypes.windll.user32
imm32 = ctypes.windll.imm32
kernel32 = ctypes.windll.kernel32
psapi = ctypes.windll.psapi
user32.SetProcessDPIAware()
WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

PROCESS_QUERY_LIMITED_INFORMATION = 0x1000


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", wintypes.LONG),
        ("top", wintypes.LONG),
        ("right", wintypes.LONG),
        ("bottom", wintypes.LONG),
    ]


def process_name(pid):
    """Executable name for a pid, or a placeholder when it cannot be opened."""
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return f"pid:{pid} (no access)"
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


def title(hwnd):
    buf = ctypes.create_unicode_buffer(256)
    user32.GetWindowTextW(hwnd, buf, 256)
    return buf.value


def describe(hwnd, label):
    rect = RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    owner = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
    print(
        f"{label}: hwnd=0x{hwnd:x} class={class_name(hwnd)!r} title={title(hwnd)!r} "
        f"owner={process_name(owner.value)} "
        f"rect=({rect.left},{rect.top})-({rect.right},{rect.bottom}) "
        f"size={rect.right - rect.left}x{rect.bottom - rect.top} "
        f"visible={bool(user32.IsWindowVisible(hwnd))}"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True, help="par-term's pid")
    parser.add_argument(
        "--scan-host",
        action="store_true",
        help="also list every visible window owned by TextInputHost.exe",
    )
    args = parser.parse_args()

    target = None
    found = []

    def callback(hwnd, _lparam):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == args.pid and user32.IsWindowVisible(hwnd):
            rect = RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            found.append(((rect.right - rect.left) * (rect.bottom - rect.top), hwnd))
        return True

    user32.EnumWindows(WNDENUMPROC(callback), 0)
    if found:
        found.sort(key=lambda item: -item[0])
        target = found[0][1]
        describe(target, "largest par-term window")
        # The legacy IMM32 UI window for this window's thread, when it has one.
        ime_ui = imm32.ImmGetDefaultIMEWnd(target)
        if ime_ui:
            describe(ime_ui, "ImmGetDefaultIMEWnd")
        else:
            print("ImmGetDefaultIMEWnd: none (no legacy IME UI window for this thread)")
    else:
        print(f"FAIL: no visible window for pid {args.pid}")

    if args.scan_host:
        print()
        print("--- visible windows owned by TextInputHost.exe ---")
        hosts = []

        def host_callback(hwnd, _lparam):
            owner = wintypes.DWORD()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
            if process_name(owner.value).lower() == "textinputhost.exe":
                hosts.append(hwnd)
            return True

        user32.EnumWindows(WNDENUMPROC(host_callback), 0)
        for hwnd in hosts:
            describe(hwnd, "  TextInputHost window")
        if not hosts:
            print("  none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
