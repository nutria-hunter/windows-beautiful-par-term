"""Measure how far the IME composition sits from the committed text on the same row.

Used with `same-row-child.mjs`, which prints one committed syllable and leaves the cursor in the
next cell: both glyphs are then in one row, so a vertical misplacement is a straight subtraction
rather than a guess. The composition is identified as the ink the seeded capture has and the
baseline capture does not (the overlay is the only difference between them), and the committed
syllable as the ink just to its left.

Usage: python measure_align.py --tag dy5
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

OUT = r"C:\Users\jky72\par-term\galaxy-work\outputs\ime-preedit"
INK = 140


def as_int(value, what):
    """Numpy scalar to int, refusing to continue on a value that cannot be converted."""
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        print(f"FAIL: cannot read {what} as an integer: {exc}")
        sys.exit(1)


def load(tag, kind):
    if os.sep in tag or (os.altsep and os.altsep in tag):
        print(f"FAIL: tag must not contain path separators: {tag!r}")
        sys.exit(1)
    path = os.path.join(OUT, f"preedit-{tag}-{kind}.png")
    try:
        with Image.open(path) as handle:
            return np.asarray(handle.convert("L")).astype(np.int16)
    except OSError as exc:
        print(f"FAIL: cannot read {path}: {exc}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument(
        "--left", type=int, default=40, help="px to search left of the overlay"
    )
    args = parser.parse_args()

    baseline = load(args.tag, "baseline")
    seeded = load(args.tag, "seeded")
    base_mask = baseline > INK
    seed_mask = seeded > INK

    overlay = seed_mask & ~base_mask
    ys, xs = np.nonzero(overlay)
    if len(ys) == 0:
        print(f"{args.tag}: no overlay ink found")
        return 1
    overlay_left = as_int(xs.min(), "overlay left edge")

    # The underline is drawn for the whole cell, so it is wider than a glyph and would drag the
    # bottom of the box down; ignore rows whose ink run is close to the widest row seen.
    first_row = as_int(ys.min(), "overlay top")
    last_row = as_int(ys.max(), "overlay bottom")
    row_width = {}
    for y in range(first_row, last_row + 1):
        row_width[y] = as_int(overlay[y].sum(), f"overlay ink in row {y}")
    widest = max(row_width.values()) if row_width else 0
    glyph_rows = [y for y, width in row_width.items() if width < max(4, widest // 2)]
    composing_top = min(glyph_rows) if glyph_rows else first_row
    composing_bottom = max(glyph_rows) if glyph_rows else last_row

    # The committed syllable: ink in the seeded frame, left of the overlay, in nearby rows.
    band_top = max(composing_top - 25, 0)
    band_bottom = min(composing_bottom + 25, seeded.shape[0])
    left_edge = max(overlay_left - args.left, 0)
    left = seed_mask[
        band_top:band_bottom, left_edge : max(overlay_left - 2, left_edge + 1)
    ]
    left_ys, _left_xs = np.nonzero(left)
    if len(left_ys) == 0:
        print(f"{args.tag}: no committed glyph found left of the overlay")
        return 1
    committed_top = as_int(left_ys.min(), "committed top") + band_top
    committed_bottom = as_int(left_ys.max(), "committed bottom") + band_top

    print(
        f"{args.tag}: committed y={committed_top}..{committed_bottom}  "
        f"composing y={composing_top}..{composing_bottom}  "
        f"offset top={committed_top - composing_top:+d} "
        f"bottom={committed_bottom - composing_bottom:+d} px"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
