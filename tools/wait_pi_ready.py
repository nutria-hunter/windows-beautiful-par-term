"""Wait until pi's TUI is interactive inside a par-term window.

Why this exists: the harness must not type before pi has laid out its input row. Typing
too early silently invalidates a run (the keys arrive at node's stdin but never reach the
TUI), and a fixed sleep cannot work because pi's startup ranges from ~1 to ~3 minutes.

Readiness is sampled from the window pixels. pi paints its input row as a wide, uniformly
filled band before any text is typed, and that row only exists once the TUI has laid out.
The band is matched by *shape* (a mostly-single-colour bright row in the lower half) rather
than an exact RGB, so changing the theme does not break the check. If no band is ever
found, the harness falls back to "the window content stopped changing", so a theme whose
input row is dark still terminates instead of burning the whole timeout.

Usage: python wait_pi_ready.py <pid> [timeout_seconds] [--out shot.png]
Exit codes: 0 ready, 1 timed out.
"""

import ctypes
import ctypes.wintypes as wt
import hashlib
import sys
import time

from PIL import ImageGrab

user32 = ctypes.windll.user32
user32.SetProcessDPIAware()

POLL_SECONDS = 1.5
STABLE_POLLS_FOR_FALLBACK = 4
BAND_STREAK_REQUIRED = 2
BAND_WIDTH_FRACTION = 0.5
BAND_MIN_BRIGHTNESS = 120
# A window that has not painted yet comes back flat and near-white.
PAINTED_MEAN_MAX = 160
PAINTED_MIN_COLORS = 32


def find_window(pid):
    """Largest visible top-level window of `pid` (par-term owns a tiny helper too)."""
    found = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)
    def _cb(hwnd, _lparam):
        owner = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value != pid or not user32.IsWindowVisible(hwnd):
            return True
        rect = wt.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(rect))
        area = (rect.right - rect.left) * (rect.bottom - rect.top)
        found.append((area, rect))
        return True

    user32.EnumWindows(_cb, 0)
    if not found:
        return None
    _, rect = max(found, key=lambda item: item[0])
    return (rect.left, rect.top, rect.right, rect.bottom)


def grab(rect):
    return ImageGrab.grab(bbox=rect, all_screens=True).convert("RGB")


def is_painted(image):
    """Reject the frame Windows reports for a window that has not painted yet.

    An unpainted HWND reads back as a flat, near-white image, and a blank row of that image
    satisfies the input-row test below (one colour covering the full width, bright). That is
    how a run can report "ready" a fraction of a second after launch and then type into a
    terminal that has not started: the capture showed no window at all. A painted par-term
    window is dark (the background shader) with brighter text over it, so requiring a dark
    mean plus a spread of colours rejects the empty frame.
    """
    small = image.resize((64, 36))
    colors = small.getcolors(maxcolors=1 << 16) or []
    if len(colors) < PAINTED_MIN_COLORS:
        return False
    mean = sum((c[0] + c[1] + c[2]) / 3 * n for n, c in colors) / (64 * 36)
    return mean < PAINTED_MEAN_MAX


def has_input_band(image):
    """True when a wide, uniform, bright row exists in the lower half of the image."""
    width, height = image.size
    if width < 200 or height < 100:
        return False
    for y in range(height // 2, height - 4, 2):
        colors = image.crop((0, y, width, y + 1)).getcolors(maxcolors=1 << 16)
        if not colors:
            continue
        count, color = max(colors)
        if count < width * BAND_WIDTH_FRACTION:
            continue
        if max(color) >= BAND_MIN_BRIGHTNESS:
            return True
    return False


def main(argv):
    if len(argv) < 2:
        print("usage: python wait_pi_ready.py <pid> [timeout_seconds] [--out shot.png]")
        return 2
    try:
        pid = int(argv[1])
    except ValueError:
        print(f"pid must be an integer, got {argv[1]!r}")
        return 2
    timeout = 300.0
    if len(argv) > 2 and not argv[2].startswith("--"):
        try:
            timeout = float(argv[2])
        except ValueError:
            print(f"timeout must be a number, got {argv[2]!r}")
            return 2
    out = None
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]

    started = time.time()
    last_hash = None
    stable = 0
    band_streak = 0
    while time.time() - started < timeout:
        rect = find_window(pid)
        if rect is None:
            print("no visible window yet")
            time.sleep(POLL_SECONDS)
            continue
        image = grab(rect)
        painted = is_painted(image)
        # Require the row on two consecutive samples: one transient frame is not evidence that
        # the TUI has settled, and typing on the strength of it wastes the whole run.
        band_streak = band_streak + 1 if painted and has_input_band(image) else 0
        if band_streak >= BAND_STREAK_REQUIRED:
            print(f"ready: input row detected after {time.time() - started:.1f}s")
            if out:
                image.save(out)
            return 0
        digest = hashlib.sha256(image.tobytes()).hexdigest()
        stable = stable + 1 if painted and digest == last_hash else 0
        last_hash = digest
        if stable >= STABLE_POLLS_FOR_FALLBACK:
            print(
                f"ready (fallback: content stable for "
                f"{stable * POLL_SECONDS:.0f}s, no input row matched) "
                f"after {time.time() - started:.1f}s"
            )
            if out:
                image.save(out)
            return 0
        time.sleep(POLL_SECONDS)

    print(f"timeout: no input row within {timeout:.0f}s")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
