"""Measure how the active tab pill sits inside the tab strip.

Reports the air above and below the pill so the strip can be checked for the
top-heavy look that came from insetting the pill twice.

Usage: python check_pill_symmetry.py <png> [x]
`x` is a column through the active pill (default 60).
"""

import sys
from pathlib import Path

from PIL import Image

CHANNELS = 3
BAR = (19, 19, 25)  # translucent strip background over black
PILL = (42, 42, 55)  # sumiInk3 pill fill
BORDER = (84, 84, 109)  # window border / pill hairline
TOLERANCE = 3
# The captures were taken at 1.5x; keep the physical numbers primary and show the
# logical equivalents for readability.
SCALE = 1.5


def matches(pixel: tuple[int, int, int], target: tuple[int, int, int]) -> bool:
    return all(abs(a - b) <= TOLERANCE for a, b in zip(pixel, target, strict=True))


def parse_column(argv: list[str]) -> int:
    """Read the optional column argument, rejecting junk with a clear message."""
    if len(argv) <= 2:
        return 60
    try:
        return int(argv[2])
    except ValueError:
        print(f"column must be an integer, got {argv[2]!r}")
        raise SystemExit(2) from None


def main() -> int:
    path = Path(sys.argv[1])
    column = parse_column(sys.argv)
    image = Image.open(path).convert("RGB")
    width, height = image.size
    data = image.tobytes()

    def pixel_at(x: int, y: int) -> tuple[int, int, int]:
        offset = (y * width + x) * CHANNELS
        return (data[offset], data[offset + 1], data[offset + 2])

    # The strip is everything above the first terminal pixel; the terminal shows the
    # galaxy, which is near-black but not the strip's own colour.
    strip_end = None
    for y in range(height):
        if y > 4 and pixel_at(column, y) == (0, 0, 0):
            strip_end = y
            break

    # Only the strip can hold the pill: below it the galaxy renders, and its dark
    # tones fall inside the fill tolerance.
    scan_height = strip_end if strip_end is not None else height
    pill_rows = [y for y in range(scan_height) if matches(pixel_at(column, y), PILL)]
    bar_rows = [y for y in range(scan_height) if matches(pixel_at(column, y), BAR)]
    border_rows = [
        y for y in range(scan_height) if matches(pixel_at(column, y), BORDER)
    ]

    if not pill_rows:
        print("no pill found in this column")
        return 1

    # The pill's painted extent includes its hairline border.
    top = min(pill_rows)
    bottom = max(pill_rows)
    if border_rows:
        top = min(top, min(border_rows))
        bottom = max(bottom, max(border_rows))

    print(f"capture {width}x{height}, column x={column}")
    print(f"strip ends at y={strip_end} (row 0..1 is the window border)")
    print(
        f"pill painted rows {top}..{bottom}  height={bottom - top + 1}px "
        f"({(bottom - top + 1) / SCALE:.1f} logical)"
    )
    if bar_rows:
        print(f"strip background rows {min(bar_rows)}..{max(bar_rows)}")
    print(f"air above pill: {top - 2}px ({(top - 2) / SCALE:.1f} logical)")
    if strip_end is not None:
        print(
            f"air below pill: {strip_end - 1 - bottom}px "
            f"({(strip_end - 1 - bottom) / SCALE:.1f} logical)"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
