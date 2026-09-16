"""Probe whether par-term receives Ime::Preedit, by driving a real Korean IME composition.

The platform IME only converts keys for the *foreground* window, and Windows refuses to let a
background process raise one, so this either works while the target window is genuinely in front
or it does nothing at all. It therefore never sends a key unless GetForegroundWindow() already
equals the target: a failed raise must not dump the letters into whatever the user is looking at.

Conversion mode is read through ImmGetConversionStatus (attached to the target's thread, because a
background thread has no HIMC of its own). If the IME is not already in Hangul mode, VK_HANGUL is
tapped once and the mode is re-read, so 'gks' composes 한 instead of typing literal letters.

Usage: python ime_inject_probe.py --pid 7320 [--keys gks]
"""

import argparse
import ctypes
import sys
import time
from ctypes import wintypes

user32 = ctypes.windll.user32
imm32 = ctypes.windll.imm32
kernel32 = ctypes.windll.kernel32

WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

VK_HANGUL = 0x15
KEYEVENTF_KEYUP = 0x0002
INPUT_KEYBOARD = 1
IME_CMODE_HANGUL = 0x0001


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", wintypes.LONG),
        ("top", wintypes.LONG),
        ("right", wintypes.LONG),
        ("bottom", wintypes.LONG),
    ]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD),
        ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG),
        ("dy", wintypes.LONG),
        ("mouseData", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]


class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [
        ("uMsg", wintypes.DWORD),
        ("wParamL", wintypes.WORD),
        ("wParamH", wintypes.WORD),
    ]


class INPUT(ctypes.Structure):
    # All three variants must be present: SendInput rejects the call outright unless
    # cbSize is exactly sizeof(INPUT) for this architecture (40 bytes on x64, sized by
    # the largest member, MOUSEINPUT).
    class _U(ctypes.Union):
        _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT), ("hi", HARDWAREINPUT)]

    _anonymous_ = ("u",)
    _fields_ = [("type", wintypes.DWORD), ("u", _U)]


def largest_window(pid):
    best = {"area": 0, "hwnd": None}

    def callback(hwnd, _lparam):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            rect = RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            area = (rect.right - rect.left) * (rect.bottom - rect.top)
            if area > best["area"]:
                best["area"], best["hwnd"] = area, hwnd
        return True

    user32.EnumWindows(WNDENUMPROC(callback), 0)
    return best["hwnd"]


def conversion_mode(hwnd):
    """Read the target thread's IME conversion status, or None when it has no context."""
    target_thread = user32.GetWindowThreadProcessId(hwnd, None)
    current_thread = kernel32.GetCurrentThreadId()
    attached = bool(user32.AttachThreadInput(current_thread, target_thread, True))
    try:
        himc = imm32.ImmGetContext(hwnd)
        if not himc:
            return None
        conv, sentence = wintypes.DWORD(), wintypes.DWORD()
        ok = imm32.ImmGetConversionStatus(
            himc, ctypes.byref(conv), ctypes.byref(sentence)
        )
        imm32.ImmReleaseContext(hwnd, himc)
        return conv.value if ok else None
    finally:
        if attached:
            user32.AttachThreadInput(current_thread, target_thread, False)


def raise_window(hwnd):
    """Try to bring `hwnd` to the foreground.

    A background process is refused by the foreground lock, so this attaches to the thread that
    currently owns the foreground (which is what the lock actually keys on) for the duration of
    the call. Returns nothing: the caller always re-reads GetForegroundWindow to decide.
    """
    current = kernel32.GetCurrentThreadId()
    foreground = user32.GetForegroundWindow()
    fg_thread = user32.GetWindowThreadProcessId(foreground, None) if foreground else 0
    target_thread = user32.GetWindowThreadProcessId(hwnd, None)

    attached = []
    for thread in {fg_thread, target_thread}:
        if (
            thread
            and thread != current
            and user32.AttachThreadInput(current, thread, True)
        ):
            attached.append(thread)
    try:
        user32.ShowWindow(hwnd, 9)  # SW_RESTORE
        user32.BringWindowToTop(hwnd)
        user32.SetForegroundWindow(hwnd)
        user32.SetFocus(hwnd)
    finally:
        for thread in attached:
            user32.AttachThreadInput(current, thread, False)


def tap(vk):
    """Send one key down+up. Only called once the target is confirmed foreground."""
    for flags in (0, KEYEVENTF_KEYUP):
        inp = INPUT()
        inp.type = INPUT_KEYBOARD
        inp.ki = KEYBDINPUT(vk, 0, flags, 0, None)
        if user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT)) != 1:
            raise OSError(
                f"SendInput failed for vk=0x{vk:02x}: error={ctypes.GetLastError()} "
                f"sizeof(INPUT)={ctypes.sizeof(INPUT)}"
            )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument(
        "--keys", default="gks", help="letters to tap ('gks' composes 한)"
    )
    parser.add_argument("--delay", type=float, default=0.25)
    args = parser.parse_args()

    hwnd = largest_window(args.pid)
    if not hwnd:
        print(f"FAIL: no visible window for pid {args.pid}")
        return 1
    print(f"target hwnd={hwnd}")

    raise_window(hwnd)
    time.sleep(0.6)
    foreground = user32.GetForegroundWindow()
    if foreground != hwnd:
        print(
            f"ABORT: target is not foreground (fg={foreground}) — no key was sent. "
            "Click the window and re-run, or type by hand."
        )
        return 1

    mode = conversion_mode(hwnd)
    print(f"conversion mode={mode!r} (None = no IME context)")
    if mode is not None and not (mode & IME_CMODE_HANGUL):
        print("IME is not in Hangul mode; tapping VK_HANGUL once")
        tap(VK_HANGUL)
        time.sleep(args.delay)
        mode = conversion_mode(hwnd)
        print(f"conversion mode after toggle={mode!r}")
        if mode is not None and not (mode & IME_CMODE_HANGUL):
            print("ABORT: could not reach Hangul mode — no letters sent.")
            return 1

    letters = [ord(ch.upper()) for ch in args.keys]
    for vk in letters:
        if user32.GetForegroundWindow() != hwnd:
            print(f"ABORT mid-sequence at vk=0x{vk:02x}: foreground changed.")
            return 1
        tap(vk)
        time.sleep(args.delay)
    print(f"sent {args.keys!r} to hwnd={hwnd}")

    # Leave no composition open.
    time.sleep(0.4)
    if user32.GetForegroundWindow() == hwnd:
        tap(0x1B)  # VK_ESCAPE cancels a pending composition
    print("done — now read the IME lines out of the debug log")
    return 0


if __name__ == "__main__":
    sys.exit(main())
