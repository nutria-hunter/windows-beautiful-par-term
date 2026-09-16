"""Fail if any moving object places itself outside `placeAt`.

The mural's motion rule is structural, not stylistic: an object's origin is snapped to the physical
pixel grid and its local lattice quantised, then sampled per fragment (`placeAt`). A raw
`pixel - something` offset instead re-samples the 4px block grid while the object slides, which makes
the boundary boil - the shimmer that kept coming back. This script is the guard: run it before every
install, and a regression shows up as a build failure rather than as "it jitters again".

Usage: python check_placement.py <shader.glsl>
"""

import io
import re
import sys

# Offsets that are allowed to be raw: effect/target positions, not object silhouettes.
ALLOWED = re.compile(r"pixel-(hitPt|shipPx|tp|dcenter|stPx|ppos|limb)|dp-|p2p")


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    bad = []
    try:
        text = io.open(path, encoding="utf-8").read()
    except OSError as exc:
        print(f"FAIL: cannot read {path}: {exc}")
        return 1
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split("//")[0]
        for match in re.finditer(r"\bpixel\s*-\s*[A-Za-z_][A-Za-z0-9_]*", code):
            if not ALLOWED.search(match.group(0)):
                bad.append((number, line.strip()))
    if bad:
        print("FAIL: object placement outside placeAt():")
        for number, line in bad:
            print(f"  L{number}: {line}")
        return 1
    print("placement OK: every object silhouette goes through placeAt()")
    return 0


if __name__ == "__main__":
    sys.exit(main())
