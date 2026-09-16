"""Stack two shader renders into one A/B sheet, with a change map of where they differ.

Usage: python ab_compare.py <older-png> <newer-png> <out-png> [--width 900]
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

DIVIDER = 6


def as_number(value, what, kind):
    """Convert a value, refusing to continue on anything that cannot be converted."""
    try:
        return kind(value)
    except (TypeError, ValueError) as exc:
        print(f"FAIL: cannot read {what} as a number: {exc}")
        sys.exit(1)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 3:
        print(__doc__)
        return 1
    old_png, new_png, out_png = (Path(a) for a in args[:3])
    width = 900
    if "--width" in sys.argv:
        index = sys.argv.index("--width") + 1
        if index >= len(sys.argv):
            print("FAIL: --width needs a value")
            return 1
        width = as_number(sys.argv[index], "--width", int)

    old = Image.open(old_png).convert("RGB")
    new = Image.open(new_png).convert("RGB")
    if old.size != new.size:
        print(f"FAIL: size mismatch {old.size} vs {new.size}")
        return 1

    scale = width / old.size[0]
    height = as_number(round(old.size[1] * scale), "image height", int)

    def shrink(img):
        return np.asarray(img.resize((width, height), Image.Resampling.LANCZOS)).astype(
            np.int16
        )

    a, b = shrink(old), shrink(new)
    delta = np.abs(a - b).max(axis=2)
    changed_fraction = as_number((delta > 8).mean(), "changed fraction", float)
    peak = as_number(delta.max(), "peak delta", int)
    print(
        f"changed pixels (>8/255): {changed_fraction * 100.0:.2f}%   max delta: {peak}"
    )

    divider = np.full((DIVIDER, width, 3), 90, dtype=np.uint8)
    sheet = np.concatenate([a.astype(np.uint8), divider, b.astype(np.uint8)], axis=0)
    Image.fromarray(sheet).save(out_png)
    print(f"wrote {out_png}  (top: {old_png.name}, bottom: {new_png.name})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
