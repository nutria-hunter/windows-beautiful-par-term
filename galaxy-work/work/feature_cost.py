"""Measure what each part of the starbound shader costs, by stubbing the function out.

The ways to make a procedural shader cheaper are not interchangeable: culling a loop that never
runs on most pixels buys nothing, while replacing per-pixel noise with a texture fetch is a large
win only if the noise is actually hot. So each candidate function gets an early `return`, the
variant is rendered by the OpenGL harness and its GPU time is compared with the untouched shader.

Usage: python feature_cost.py            (writes outputs/feature-cost.json)
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

ZERO = {
    "void": None,
    "float": "0.0",
    "int": "0",
    "bool": "false",
    "vec2": "vec2(0.0)",
    "vec3": "vec3(0.0)",
    "vec4": "vec4(0.0)",
    "mat2": "mat2(0.0)",
    "mat3": "mat3(0.0)",
    "mat4": "mat4(0.0)",
}

# Bodies mentioning these are candidate hot spots worth measuring one at a time.
KEYWORDS = (
    "nebula",
    "fbm",
    "noise",
    "planet",
    "city",
    "star",
    "asteroid",
    "opera",
    "incursion",
    "structure",
    "ship",
    "comet",
    "meteor",
    "warp",
    "wake",
)

SIGNATURE = re.compile(
    r"(?m)^[ \t]*((?:vec[234]|float|int|void|bool|mat[234]))[ \t]+(\w+)[ \t]*\(([^)]*)\)[ \t]*\{"
)


def read_text(path):
    """File contents, or None when the file is not readable."""
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except OSError as error:
        print(f"cannot read {path}: {error}")
        return None


def write_text(path, text):
    """True when the file was written."""
    try:
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        return True
    except OSError as error:
        print(f"cannot write {path}: {error}")
        return False


def functions(text):
    """(name, match end offset) for each function definition, in file order."""
    return [(m.group(2), m.end()) for m in SIGNATURE.finditer(text)]


def body_of(text, start):
    """The brace-balanced body that starts at `start`."""
    depth = 1
    index = start
    while index < len(text) and depth:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    return text[start:index]


def stub(text, name):
    """`text` with `name`'s body replaced by an immediate return, or None if it is absent."""
    for match in SIGNATURE.finditer(text):
        if match.group(2) != name:
            continue
        value = ZERO.get(match.group(1), "0.0")
        statement = "return;" if value is None else f"return {value};"
        return (
            text[: match.end()]
            + f"\n    {statement} // feature-cost probe\n"
            + text[match.end() :]
        )
    return None


def measure(shader_path, tag):
    """Median GPU milliseconds for one shader, or None when the harness did not report any."""
    try:
        proc = subprocess.run(
            [sys.executable, HARNESS, shader_path, f"tag={tag}"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError as error:
        print(f"harness did not start for {tag}: {error}")
        return None
    found = re.search(r'"gpu_ms_median"\s*:\s*([0-9.]+)', proc.stdout)
    if not found:
        print(f"no gpu_ms_median in the harness output for {tag}")
        return None
    try:
        return float(found.group(1))
    except ValueError:
        return None


def main():
    text = read_text(SOURCE)
    if text is None:
        return 1
    definitions = functions(text)
    candidates = [
        name
        for name, end in definitions
        if len(body_of(text, end)) > 800
        and any(key in body_of(text, end).lower() for key in KEYWORDS)
    ]
    # Biggest first: the costly ones are almost always the large ones.
    candidates.sort(key=lambda name: -len(body_of(text, dict(definitions)[name])))
    candidates = candidates[:12]

    if not write_text(os.path.join(OUTPUTS, "cost-base.glsl"), text):
        return 1
    base = measure(SOURCE, "cost-base")
    if base is None:
        print("baseline measurement failed; nothing to compare against")
        return 1
    print(f"baseline {base:.3f} ms  ({len(text)} B, {len(definitions)} functions)")

    rows = [{"variant": "baseline", "stubbed": None, "gpu_ms": base, "delta_ms": 0.0}]
    for name in candidates:
        variant = stub(text, name)
        if variant is None:
            continue
        path = os.path.join(SHADERS, f"cost-{name}.glsl")
        if not write_text(path, variant):
            continue
        measured = measure(path, f"cost-{name}")
        if measured is None:
            continue
        delta = base - measured
        share = delta / base * 100.0
        rows.append(
            {
                "variant": f"cost-{name}",
                "stubbed": name,
                "gpu_ms": measured,
                "delta_ms": delta,
            }
        )
        print(
            f"  {name:22s} {measured:6.3f} ms   saves {delta:+6.3f} ms  ({share:5.1f}%)"
        )

    write_text(
        os.path.join(OUTPUTS, "feature-cost.json"),
        json.dumps({"shader": SOURCE, "results": rows}, indent=2),
    )
    print("wrote outputs/feature-cost.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
