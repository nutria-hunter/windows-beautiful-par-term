"""Find the frames in a grab that contain something the other frames do not.

The terminal's background is an animated shader, so no two frames are identical. What a composition
box adds is different in kind: a compact, bright, *stable* region that is absent from most frames.
So the model is the per-pixel median over time (which keeps the slowly drifting mural and drops
anything transient), and each frame is scored by how many of its pixels deviate from that model.

Usage: python analyze_grab.py --dir ..\\outputs\\ime-preedit\\grab [--top 6]
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

DEVIATION = 40


def load_frames(directory):
    try:
        names = sorted(n for n in os.listdir(directory) if n.endswith(".png"))
    except OSError as exc:
        print(f"FAIL: cannot list {directory}: {exc}")
        sys.exit(1)
    if len(names) < 3:
        print(f"FAIL: need at least 3 frames, found {len(names)}")
        sys.exit(1)
    frames = []
    for name in names:
        try:
            with Image.open(os.path.join(directory, name)) as handle:
                frames.append(np.asarray(handle.convert("L")))
        except OSError as exc:
            print(f"FAIL: cannot read {name}: {exc}")
            sys.exit(1)
    return names, frames


def scaled(value, factor):
    """Scaled dimension, refusing to continue on a value that cannot be converted."""
    try:
        return max(1, int(value * factor))
    except (TypeError, ValueError) as exc:
        print(f"FAIL: cannot scale {value!r}: {exc}")
        sys.exit(1)


def as_int(value, what):
    """Numpy scalar to int, refusing to continue on a value that cannot be converted."""
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        print(f"FAIL: cannot read {what} as an integer: {exc}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", required=True)
    parser.add_argument("--top", type=int, default=6)
    parser.add_argument(
        "--stride", type=int, default=3, help="frames sampled for the median"
    )
    args = parser.parse_args()

    names, frames = load_frames(args.dir)
    sampled = frames[:: max(1, args.stride)]
    model = np.median(np.stack(sampled), axis=0)
    print(
        f"{len(frames)} frames, model from {len(sampled)} of them, deviation > {DEVIATION}"
    )

    scored = []
    for index, frame in enumerate(frames):
        deviating = np.abs(frame.astype(np.int16) - model) > DEVIATION
        count = as_int(deviating.sum(), "deviating pixels")
        scored.append((count, index, deviating))

    scored.sort(key=lambda item: -item[0])
    print()
    print("most deviating frames (count, frame, bbox):")
    shown = []
    for count, index, deviating in scored[: args.top]:
        ys, xs = np.nonzero(deviating)
        if len(ys) == 0:
            print(f"  {names[index]}: 0 px")
            continue
        bbox = (
            as_int(xs.min(), "bbox left"),
            as_int(ys.min(), "bbox top"),
            as_int(xs.max(), "bbox right"),
            as_int(ys.max(), "bbox bottom"),
        )
        print(
            f"  {names[index]}: {count:6d} px  bbox={bbox} "
            f"({bbox[2] - bbox[0] + 1}x{bbox[3] - bbox[1] + 1})"
        )
        shown.append((index, bbox, count))

    if not shown:
        print("nothing deviated; no box-shaped region in this grab")
        return 0

    # Save the strongest frame, the model, and a zoomed side by side around its region.
    index, bbox, _count = shown[0]
    pad = 24
    x0 = max(bbox[0] - pad, 0)
    y0 = max(bbox[1] - pad, 0)
    x1 = min(bbox[2] + pad, frames[index].shape[1] - 1)
    y1 = min(bbox[3] + pad, frames[index].shape[0] - 1)

    out = args.dir
    Image.fromarray(frames[index]).save(os.path.join(out, "_best.png"))
    Image.fromarray(model.astype(np.uint8)).save(os.path.join(out, "_model.png"))
    left = frames[index][y0 : y1 + 1, x0 : x1 + 1]
    right = model[y0 : y1 + 1, x0 : x1 + 1].astype(np.uint8)
    separator = np.full((left.shape[0], 3), 255, dtype=np.uint8)
    joined = np.concatenate((left, separator, right), axis=1)
    crop = Image.fromarray(joined)
    zoom = max(1, min(6, 700 // max(crop.width, 1)))
    crop = crop.resize(
        (crop.width * zoom, crop.height * zoom), Image.Resampling.NEAREST
    )
    crop.save(os.path.join(out, "_compare.png"))
    print()
    print(
        f"saved {out}\\_best.png (frame {names[index]}), _model.png, _compare.png (left=frame, right=model)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
