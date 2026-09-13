"""Locate the tab bar's window-control buttons in a screenshot.

Self-calibrating: instead of assuming a DPI scale, it finds the three Kanagawa
control colours in the capture and reports their centres in image coordinates.

Only the tab strip is searched, and only the largest blob of each colour is
reported. A plain centroid over the whole top of the image is not enough: the
galaxy renders just below the strip and its warm tones fall inside the colour
tolerance, which drags the centroid away from the button.

Usage: python find_buttons.py <png>
Prints: NAME x y count
"""

import sys
from pathlib import Path

from PIL import Image

# The controls take their colours from the theme, so match the Kanagawa accents.
TARGETS = {
    "close": (195, 64, 67),  # theme.red    #C34043
    "maximize": (118, 148, 106),  # theme.green  #76946A
    "minimize": (192, 163, 110),  # theme.yellow #C0A36E
}
TOLERANCE = 26
CHANNELS = 3
# The strip is the only place the controls can be. 44px clears the tallest bar at
# the 1.5x scale this was built for while stopping short of terminal content.
STRIP_HEIGHT = 44
# A 12px control is ~250 physical px at 1.5x; anything much smaller is noise.
MIN_BLOB = 100


def close_to(pixel: tuple[int, int, int], target: tuple[int, int, int]) -> bool:
    return all(abs(a - b) <= TOLERANCE for a, b in zip(pixel, target, strict=True))


def largest_blob(
    mask: list[list[bool]], width: int, height: int
) -> list[tuple[int, int]]:
    """Return the biggest 4-connected component of `mask`."""
    seen = [[False] * width for _ in range(height)]
    best: list[tuple[int, int]] = []
    for start_y in range(height):
        for start_x in range(width):
            if not mask[start_y][start_x] or seen[start_y][start_x]:
                continue
            stack = [(start_x, start_y)]
            seen[start_y][start_x] = True
            blob: list[tuple[int, int]] = []
            while stack:
                x, y = stack.pop()
                blob.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if (
                        0 <= nx < width
                        and 0 <= ny < height
                        and mask[ny][nx]
                        and not seen[ny][nx]
                    ):
                        seen[ny][nx] = True
                        stack.append((nx, ny))
            if len(blob) > len(best):
                best = blob
    return best


def main() -> int:
    path = Path(sys.argv[1])
    image = Image.open(path).convert("RGB")
    width, height = image.size
    # Raw bytes rather than `image.load()`: the pixel-access object is typed as
    # possibly-None, and flat indexing keeps this a single pass.
    data = image.tobytes()
    strip_height = min(STRIP_HEIGHT, height)

    def pixel_at(x: int, y: int) -> tuple[int, int, int]:
        offset = (y * width + x) * CHANNELS
        return (data[offset], data[offset + 1], data[offset + 2])

    for name, target in TARGETS.items():
        mask = [
            [close_to(pixel_at(x, y), target) for x in range(width)]
            for y in range(strip_height)
        ]
        blob = largest_blob(mask, width, strip_height)
        if len(blob) < MIN_BLOB:
            print(f"{name} MISSING count={len(blob)}")
            continue
        cx = sum(point[0] for point in blob) / len(blob)
        cy = sum(point[1] for point in blob) / len(blob)
        print(f"{name} {cx:.1f} {cy:.1f} count={len(blob)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
