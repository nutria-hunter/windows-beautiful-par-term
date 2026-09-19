"""Second round: stub the helpers the two event systems call, plus the hash, and measure each.

The first round showed incursionEvent (39.9%) and shipEvent (29.9%) dominating, but culling their
screen bands did not move the total: on the measured frame the bands cover most of the window. So
the cost sits in the helpers they call - schedules, wrecks, shields, sprite transforms - and one of
those has to be the one to rewrite. Same method: stub, render with the OpenGL harness, compare.

Usage: python feature_cost2.py           (writes outputs/feature-cost2.json)
"""

import json
import os
import re
import subprocess
import sys

WORK = r"C:\Users\jky72\par-term\galaxy-work"
SHADERS = os.path.join(WORK, "shaders")
OUTPUTS = os.path.join(WORK, "outputs")
SOURCE = os.path.join(SHADERS, "kanagawa-starbound.glsl")
HARNESS = os.path.join(WORK, "work", "render_check.py")

TARGETS = [
    "shipSchedule",
    "incursionSchedule",
    "operaPulse",
    "hullWreck",
    "operaShield",
    "damagedHull",
    "hullImpact",
    "warpTrail",
    "operaShip",
    "armorLight",
    "stationPoint",
    "hash21",
]

ZERO = {"void": None, "float": "0.0", "int": "0", "bool": "false", "vec2": "vec2(0.0)",
        "vec3": "vec3(0.0)", "vec4": "vec4(0.0)", "mat2": "mat2(0.0)", "mat3": "mat3(0.0)", "mat4": "mat4(0.0)"}
SIGNATURE = re.compile(r"(?m)^[ \t]*((?:vec[234]|float|int|void|bool|mat[234]))[ \t]+(\w+)[ \t]*\(([^)]*)\)[ \t]*\{")


def read_text(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except OSError as error:
        print(f"cannot read {path}: {error}")
        return None


def write_text(path, text):
    try:
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        return True
    except OSError as error:
        print(f"cannot write {path}: {error}")
        return False


def stub(text, name):
    for match in SIGNATURE.finditer(text):
        if match.group(2) != name:
            continue
        value = ZERO.get(match.group(1), "0.0")
        statement = "return;" if value is None else f"return {value};"
        return text[: match.end()] + f"\n    {statement} // feature-cost probe\n" + text[match.end():]
    return None


def measure(path, tag):
    try:
        proc = subprocess.run([sys.executable, HARNESS, path, f"tag={tag}"], capture_output=True,
                              text=True, encoding="utf-8", errors="replace", check=False)
    except OSError as error:
        print(f"harness did not start for {tag}: {error}")
        return None
    found = re.search(r'"gpu_ms_median"\s*:\s*([0-9.]+)', proc.stdout)
    try:
        return float(found.group(1)) if found else None
    except ValueError:
        return None


def main():
    text = read_text(SOURCE)
    if text is None:
        return 1
    base = measure(SOURCE, "cost2-base")
    if base is None:
        print("baseline measurement failed")
        return 1
    print(f"baseline {base:.3f} ms")
    rows = [{"variant": "baseline", "stubbed": None, "gpu_ms": base, "delta_ms": 0.0}]
    for name in TARGETS:
        variant = stub(text, name)
        if variant is None:
            print(f"  {name:20s} not found")
            continue
        path = os.path.join(SHADERS, f"cost2-{name}.glsl")
        if not write_text(path, variant):
            continue
        measured = measure(path, f"cost2-{name}")
        if measured is None:
            continue
        delta = base - measured
        rows.append({"variant": f"cost2-{name}", "stubbed": name, "gpu_ms": measured, "delta_ms": delta})
        print(f"  {name:20s} {measured:6.3f} ms   saves {delta:+6.3f} ms ({delta / base * 100:5.1f}%)")
    write_text(os.path.join(OUTPUTS, "feature-cost2.json"),
               json.dumps({"shader": SOURCE, "results": rows}, indent=2))
    print("wrote outputs/feature-cost2.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
