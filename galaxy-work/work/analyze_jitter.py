"""Track the pi footer's row across captured frames and report whether it oscillates.

The footer is the boxed input area at the bottom of the window. Its top edge is a long horizontal
run of box-drawing pixels, which is the only structure like it in the lower half of the window, so
locating it per frame is a matter of finding the row with the longest run of "ink" below the
midpoint. Oscillation is then counted as direction changes of that row over time — a footer that
merely scrolls up (monotonic) is not vibration.

Usage: python analyze_jitter.py stream
"""

import os
import sys

import numpy as np
from PIL import Image

OUT_ROOT = r"C:\Users\jky72\par-term\galaxy-work\outputs\tui-jitter"


def ink_mask(frame):
    rgb = frame.astype(np.int16)
    luma = rgb.mean(axis=2)
    # Ink is anything clearly lighter than the background mural, which is near-black in the lower half.
    return luma > 90


def longest_run(row_mask):
    if not row_mask.any():
        return 0
    # Longest contiguous run of True, vectorised: split on gaps.
    padded = np.concatenate(([False], row_mask, [False]))
    edges = np.diff(padded.astype(np.int8))
    starts = np.flatnonzero(edges == 1)
    ends = np.flatnonzero(edges == -1)
    if len(starts) == 0:
        return 0
    return max(int(end - start) for start, end in zip(starts, ends, strict=True))


def count_ink(mask):
    """Number of ink pixels in a frame; reports and stops the run if the array is unusable."""
    try:
        return int(np.count_nonzero(mask))
    except (TypeError, ValueError) as exc:
        print(f"FAIL: cannot count ink: {exc}")
        sys.exit(1)


def footer_row(mask):
    """Row of the footer's top border: longest horizontal ink run in the lower 40% of the window."""
    height = mask.shape[0]
    lower = slice(height * 55 // 100, height)
    region = mask[lower, :]
    best_row, best_len = None, 0
    for offset in range(region.shape[0]):
        run = longest_run(region[offset])
        if run > best_len:
            best_len, best_row = run, offset + lower.start
    # At least a quarter of the width has to be a single run for it to be a border, not text.
    if best_len < mask.shape[1] * 0.2:
        return None
    return best_row


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else "stream"
    directory = os.path.join(OUT_ROOT, tag)
    try:
        frames = sorted(f for f in os.listdir(directory) if f.endswith(".png"))
    except OSError as exc:
        print(f"FAIL: cannot list {directory}: {exc}")
        sys.exit(1)
    if not frames:
        print(f"FAIL: no frames in {directory}")
        sys.exit(1)

    rows = []
    for name in frames:
        try:
            with Image.open(os.path.join(directory, name)) as handle:
                mask = ink_mask(np.asarray(handle.convert("RGB")))
        except OSError as exc:
            print(f"FAIL: cannot read frame {name}: {exc}")
            sys.exit(1)
        ink = count_ink(mask)
        rows.append((name, footer_row(mask), ink))

    found = [(name, row) for name, row, _ in rows if row is not None]
    print(f"frames           : {len(rows)}  ({frames[0]} .. {frames[-1]})")
    print(f"frames w/ footer : {len(found)}")
    if not found:
        print("FAIL: the footer border was never located")
        return

    series = [row for _name, row in found]
    print(f"footer row range : {min(series)} .. {max(series)}")
    distinct = sorted(set(series))
    print(f"distinct rows    : {distinct}")
    print(f"most common      : {max(set(series), key=series.count)}")

    # Direction changes, ignoring repeats: a monotonic scroll has 0 or 1.
    compact = []
    for row in series:
        if not compact or compact[-1] != row:
            compact.append(row)
    changes = sum(
        1
        for index in range(1, len(compact) - 1)
        if (compact[index] - compact[index - 1]) * (compact[index + 1] - compact[index])
        < 0
    )
    print(f"transitions      : {len(compact) - 1}  (of {len(series)} frames)")
    print(f"direction changes: {changes}")
    print(
        "verdict          : "
        + (
            "VIBRATION (row reverses direction)"
            if changes >= 3
            else "stable / monotonic"
        )
    )

    for name, row, ink in rows[:12]:
        print(f"  {name}: row={row} ink={ink}")


if __name__ == "__main__":
    main()
