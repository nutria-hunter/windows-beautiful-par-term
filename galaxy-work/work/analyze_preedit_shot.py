"""Measure what the IME preedit overlay painted, without assuming where the cursor is.

A whole-frame diff is useless on its own: the window runs an animated background shader, so every
pixel differs between two captures. The overlay is the one thing that is *bright* where nothing
bright was, though - the preedit is drawn in the theme foreground while the mural behind it stays
dark - so the measurement is: threshold both captures to ink, and look at the ink that only the
seeded capture has.

This replaces an earlier version that measured a fixed box at the window's top-left. That box was
the tab bar, not the cursor cell, so it reported "UNRELIABLE - baseline already has ink" for every
run, including runs where the overlay had painted correctly. The cursor can be anywhere (the child
decides), so the measurement must find it instead of being told where it is.

Used both ways round: with no composition the seeded-only ink must be empty, with a composition it
must hold one glyph. epaint's replacement character (U+25FB, a hollow square) is what a missing
CJK glyph looks like, so the crop is kept for visual inspection rather than judged by shape here.

Usage: python analyze_preedit_shot.py shipped
"""

import os
import sys

import numpy as np
from PIL import Image

OUT = r"C:\Users\jky72\par-term\galaxy-work\outputs\ime-preedit"

# Ink: clearly brighter than the mural, which is near-black in the terminal area.
INK_LUMA = 140
# One glyph at 100% DPI is ~150-400 px; at 175% it is several times that. Anything below this is
# shader noise, not a glyph.
MIN_GLYPH_PX = 60


def load(tag, kind):
    path = f"{OUT}/preedit-{tag}-{kind}.png"
    try:
        with Image.open(path) as handle:
            return np.asarray(handle.convert("RGB")).astype(np.int16), path
    except OSError as exc:
        print(f"FAIL: cannot read {path}: {exc}")
        sys.exit(1)


def ink_mask(image):
    """Bright pixels, as a bool mask, plus the luma array for peak reporting."""
    luma = image.mean(axis=2)
    return luma > INK_LUMA, luma


def as_int(value, what):
    """Numpy scalar to int, refusing to continue on a value that cannot be converted."""
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        print(f"FAIL: cannot read {what} as an integer: {exc}")
        sys.exit(1)


def as_float(value, what):
    """Numpy scalar to float, refusing to continue on a value that cannot be converted."""
    try:
        return float(value)
    except (TypeError, ValueError) as exc:
        print(f"FAIL: cannot read {what} as a float: {exc}")
        sys.exit(1)


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else "shipped"
    baseline, base_path = load(tag, "baseline")
    seeded, seed_path = load(tag, "seeded")

    base_mask, _ = ink_mask(baseline)
    seed_mask, seed_luma = ink_mask(seeded)

    only_seeded = seed_mask & ~base_mask
    only_baseline = base_mask & ~seed_mask
    base_px = as_int(base_mask.sum(), "baseline ink")
    seed_px = as_int(seed_mask.sum(), "seeded ink")
    added = as_int(only_seeded.sum(), "seeded-only ink")
    removed = as_int(only_baseline.sum(), "baseline-only ink")

    print(
        f"frames   : {os.path.basename(base_path)}  vs  {os.path.basename(seed_path)}"
    )
    print(f"ink      : baseline={base_px:6d} px   seeded={seed_px:6d} px")
    print(f"delta    : +{added} px only in seeded   -{removed} px only in baseline")

    if added == 0:
        print()
        print(
            "verdict: FAIL - the seeded composition painted no ink anywhere in the window"
        )
        return

    ys, xs = np.nonzero(only_seeded)
    box = (
        as_int(xs.min(), "new-ink left"),
        as_int(ys.min(), "new-ink top"),
        as_int(xs.max(), "new-ink right"),
        as_int(ys.max(), "new-ink bottom"),
    )
    peak = as_float(seed_luma[only_seeded].max(), "peak luma")
    print(f"new ink  : bbox={box}  peak_luma={peak:.1f}")

    # Side-by-side, zoomed, so the glyph is readable. Padded around the change so the
    # surrounding cell (and the underline) is visible too.
    pad = 12
    x0 = max(box[0] - pad, 0)
    y0 = max(box[1] - pad, 0)
    x1 = min(box[2] + pad, seeded.shape[1])
    y1 = min(box[3] + pad, seeded.shape[0])
    left = seeded[y0:y1, x0:x1].astype(np.uint8)
    right = baseline[y0:y1, x0:x1].astype(np.uint8)
    separator = np.full((left.shape[0], 3, 3), 255, dtype=np.uint8)
    joined = np.concatenate((left, separator, right), axis=1)
    crop = Image.fromarray(joined)
    zoom = max(1, min(8, 600 // max(crop.width, 1)))
    crop = crop.resize(
        (crop.width * zoom, crop.height * zoom), Image.Resampling.NEAREST
    )
    crop_path = f"{OUT}/preedit-{tag}-crop.png"
    crop.save(crop_path)

    glyph_like = added >= MIN_GLYPH_PX
    print()
    print(
        f"verdict: {'PASS' if glyph_like else 'WEAK'} - {added} px of new ink at the composition, "
        f"{box[2] - box[0] + 1}x{box[3] - box[1] + 1} px"
    )
    print(f"crop    : {crop_path}  (left = composing, right = same window with none)")


if __name__ == "__main__":
    main()
