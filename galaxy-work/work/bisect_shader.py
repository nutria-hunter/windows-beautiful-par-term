"""Bisect the starbound shader against par-term itself, to find where the background died.

The independent OpenGL harness and `shader-lint` both pass on files that par-term renders as an
empty screen (the loader translates GLSL to WGSL and a runtime that goes NaN paints nothing), so
par-term's own screenshot is the only oracle that matters here. Each candidate is copied over the
installed shader - `custom_shader` in config.yaml wins over `--shader`, so that is the only way to
switch what actually renders - and then photographed.

Content is measured away from the text area: the top-left corner is the PowerShell banner, so a
dark, flat middle band means "nothing was drawn", while stars and nebulae push it up.

Usage: python bisect_shader.py            (writes outputs/shader-bisect/)
"""

import os
import re
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image

WORK = r"C:\Users\jky72\par-term\galaxy-work"
SHADERS = os.path.join(WORK, "shaders")
INSTALLED = r"C:\Users\jky72\AppData\Roaming\par-term\shaders\kanagawa-starbound.glsl"
EXE = r"C:\Users\jky72\par-term\par-term.exe"
OUT = os.path.join(WORK, "outputs", "shader-bisect")

# Newest first: the regression lies between the last good candidate and the first bad one.
CANDIDATES = [
    "kanagawa-starbound.glsl",
    "kanagawa-starbound-before-startup-exit-fix.glsl",
    "kanagawa-starbound-before-space-opera.glsl",
    "kanagawa-starbound-before-ship-fx-v2.glsl",
    "kanagawa-starbound-before-recoil-warp.glsl",
    "kanagawa-starbound-before-crafted-fleet.glsl",
    "kanagawa-starbound-before-warp-art.glsl",
    "kanagawa-starbound-before-warp-coordinate-fix.glsl",
    "kanagawa-starbound-before-pfstation.glsl",
    "kanagawa-starbound-before-dark-refactor.glsl",
    "kanagawa-starbound-codex-6.0.0-orig.glsl",
    "kanagawa-starbound-v6.0.9-vanish.glsl",
    "kanagawa-starbound-v1.5.glsl",  # known-good control from 2026-09-13
]


def measure(path):
    try:
        with Image.open(path) as handle:
            image = handle.convert("RGB")
            array = np.asarray(image).astype(np.int16)
        # Middle band only: skips the shell banner at the top and the tab bar.
        band = array[array.shape[0] // 4 : array.shape[0] * 9 // 10, :]
        luma = band.mean(axis=2)
        return {
            "mean": float(luma.mean()),
            "p99": float(np.percentile(luma, 99)),
            "ink": float((luma > 25).mean()),
            "max": float(luma.max()),
        }
    except (OSError, TypeError, ValueError) as exc:
        print(f"    FAIL: cannot measure {path}: {exc}")
        return None


def main():
    try:
        os.makedirs(OUT, exist_ok=True)
    except OSError as exc:
        print(f"FAIL: cannot create {OUT}: {exc}")
        sys.exit(1)

    # Names may be given on the command line to run one slice of the range at a time.
    candidates = sys.argv[1:] or CANDIDATES

    try:
        with open(INSTALLED, "rb") as handle:
            original = handle.read()
    except OSError as exc:
        print(f"FAIL: cannot read the installed shader {INSTALLED}: {exc}")
        sys.exit(1)
    original_version = re.search(rb"version: (\S+)", original)
    print(
        f"installed backup kept in memory ({len(original)} bytes, version {original_version.group(1).decode() if original_version else '?'})"
    )
    results = []
    try:
        for name in candidates:
            source = os.path.join(SHADERS, name)
            if not os.path.exists(source):
                print(f"  {name}: missing, skipped")
                continue
            shutil.copy2(source, INSTALLED)
            shot = os.path.join(OUT, name.replace(".glsl", ".png"))
            if os.path.exists(shot):
                os.remove(shot)
            subprocess.run(
                [EXE, "--screenshot", shot, "--exit-after", "5"],
                capture_output=True,
                timeout=90,
                check=False,
            )
            stats = measure(shot)
            try:
                with open(source, encoding="utf-8", errors="replace") as handle:
                    text = handle.read(4000)
            except OSError as exc:
                print(f"    FAIL: cannot read {source}: {exc}")
                text = ""
            version = re.search(r"version:\s*(\S+)", text)
            label = version.group(1) if version else "?"
            results.append((name, label, stats))
            if stats:
                print(
                    f"  {name:58s} v{label:8s} mean={stats['mean']:6.2f} p99={stats['p99']:6.1f} "
                    f"ink={stats['ink'] * 100:5.2f}%"
                )
            else:
                print(f"  {name:58s} v{label:8s} no measurement")
    finally:
        try:
            with open(INSTALLED, "wb") as handle:
                handle.write(original)
        except OSError as exc:
            print(f"FAIL: could not restore the installed shader: {exc}")
        print("installed shader restored from memory")

    print()
    print(
        "=== bisect summary (ink = share of the middle band brighter than 25/255) ==="
    )
    for name, label, stats in results:
        flag = "EMPTY" if stats and stats["ink"] < 0.004 else "content"
        print(f"  {flag:7s} v{label:8s} {name}")


if __name__ == "__main__":
    main()
