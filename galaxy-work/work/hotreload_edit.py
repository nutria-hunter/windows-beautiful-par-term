"""Make one obvious colour change in the installed shader, or put it back.

Used by hotreload_probe.ps1: a running par-term must show the change without being restarted,
so the change has to be impossible to miss on screen (and trivially reversible).

Usage: python hotreload_edit.py <installed.glsl> <canonical.glsl> break|restore
"""

import shutil
import sys
from pathlib import Path

REAL = "vec3(65, 82, 99) / 255.0"  # ink level 5: the brightest nebula band
FAKE = "vec3(230, 70, 70) / 255.0"  # deliberately wrong: it cannot be missed on screen


def read_text(path):
    """Read a shader file, refusing to continue if it cannot be read."""
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except OSError as exc:
        print(f"FAIL: cannot read {path}: {exc}")
        sys.exit(1)


def write_text(path, text):
    """Write a shader file, refusing to continue if it cannot be written."""
    try:
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
    except OSError as exc:
        print(f"FAIL: cannot write {path}: {exc}")
        sys.exit(1)


def glsl_path(raw, what):
    """Accept only .glsl paths, so this helper can never be pointed at other files."""
    path = Path(raw)
    if path.suffix != ".glsl":
        print(f"FAIL: {what} must be a .glsl file, got {raw}")
        sys.exit(1)
    return path


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        return 1
    installed = glsl_path(sys.argv[1], "installed shader")
    canonical = glsl_path(sys.argv[2], "canonical shader")
    mode = sys.argv[3]
    if mode == "break":
        text = read_text(canonical)
        if text.count(REAL) == 0:
            print("FAIL: colour marker not found in the canonical shader")
            return 1
        write_text(installed, text.replace(REAL, FAKE))
        print("broke: brightest ink band is now red")
    elif mode == "restore":
        try:
            shutil.copyfile(canonical, installed)
        except OSError as exc:
            print(f"FAIL: cannot restore {installed}: {exc}")
            return 1
        print("restored")
    else:
        print("FAIL: mode must be break or restore")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
