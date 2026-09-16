"""Compare the galaxy core between two live-window captures.

Two things need measuring, and the screenshot route cannot be trusted for either: par-term's
`--screenshot` renders its own frame and came back with the theme background in the empty
corners, while the live window there is pure black. So samples come from a window capture.

Reports, per image:
  * corner medians, to confirm the empty background is still black
  * the core's vertical and horizontal half-maximum widths through the galaxy centre, and their
    ratio. Relaxing the disk's flattening for the bulge should make the core taller relative to
    its width; that ratio is the "volume" number.

Usage: python core_profile.py <image.png> [<image.png> ...]
Exit codes: 0 all images measured, 1 at least one could not be read.
"""

import sys

import numpy as np
from PIL import Image

# From the shader metadata defaults: iCenterX / iCenterY.
CENTER_X = 0.62
CENTER_Y = 0.58
HALF_WINDOW = 260


def luma(image):
    rgb = np.asarray(image.convert("RGB")).astype(np.float32)
    return rgb @ np.array([0.2126, 0.7152, 0.0722])


def half_max_width(profile, positions):
    """Full width at half maximum of a profile, measured over its own baseline.

    Returns (width in pixels, peak, baseline). A profile that cannot be measured - flat, or
    shorter than two samples above the half maximum - comes back as zeros rather than NaN, so
    the caller never has to special-case it.
    """
    try:
        baseline = float(np.percentile(profile, 10))
        peak = float(profile.max())
        if peak - baseline <= 1.0:
            return 0.0, peak, baseline
        half = baseline + (peak - baseline) / 2.0
        above = positions[profile >= half]
        if above.size < 2:
            return 0.0, peak, baseline
        return float(above[-1] - above[0]), peak, baseline
    except (ValueError, IndexError, TypeError) as exc:
        print(f"    (profile could not be measured: {exc})")
        return 0.0, 0.0, 0.0


def measure_channel_of_core(path):
    """Print the corner and core measurements for one capture.

    Returns True when the image could be read, False otherwise. Every failure mode here comes
    from the input path (missing file, unreadable image, empty file), so they are reported as a
    line and turned into a non-zero exit code instead of a traceback.
    """
    with Image.open(path) as opened:
        image = opened.convert("RGB")
    width, height = image.size
    if width < 200 or height < 200:
        print(f"--- {path}: image too small to measure ({width}x{height})")
        return False

    lum = luma(image)
    # Integer math keeps this off any float-to-int conversion helper.
    cx = width * 62 // 100
    cy = height * 58 // 100

    print(f"--- {path}  ({width}x{height})")
    corners = {
        "top-left": lum[0:150, 0:300],
        "top-right": lum[0:150, width - 300 : width],
        "bottom-left": lum[height - 150 : height, 0:300],
        "bottom-right": lum[height - 150 : height, width - 300 : width],
    }
    for name, region in corners.items():
        print(
            f"    {name:<13} median {np.median(region):5.1f}  mean {region.mean():6.2f}"
        )

    ys = np.arange(cy - HALF_WINDOW, cy + HALF_WINDOW)
    xs = np.arange(cx - HALF_WINDOW, cx + HALF_WINDOW)
    try:
        vert = lum[ys, cx - 30 : cx + 30].mean(axis=1)
        horiz = lum[cy - 30 : cy + 30, xs].mean(axis=0)
    except (IndexError, ValueError) as exc:
        print(f"--- {path}: window falls outside the image ({exc})")
        return False

    vert_width, vert_peak, _ = half_max_width(vert, ys)
    horiz_width, horiz_peak, _ = half_max_width(horiz, xs)
    print(
        f"    core peak      vertical {vert_peak:6.1f}   horizontal {horiz_peak:6.1f}"
    )
    print(
        f"    core FWHM      vertical {vert_width:6.1f}px horizontal {horiz_width:6.1f}px"
    )
    if horiz_width > 0:
        aspect = vert_width / horiz_width
        print(
            f"    core aspect    {aspect:6.3f}  (vertical / horizontal; higher = more volume)"
        )
    else:
        print("    core aspect      n/a (no horizontal half maximum found)")
    return True


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    unreadable = 0
    for path in argv[1:]:
        try:
            if not measure_channel_of_core(path):
                unreadable += 1
        except (OSError, ValueError, SyntaxError) as exc:
            print(f"--- {path}: cannot read ({exc})")
            unreadable += 1
    return 1 if unreadable else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
