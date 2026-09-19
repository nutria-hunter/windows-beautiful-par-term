"""Bake a procedural layer of the starbound shader into a texture the shader can just sample.

Old hardware drew this kind of scene with texture fetches; the shader recomputes it per pixel every
frame. Baking moves the layers that barely move (star dust, and the star field once its cloud field
is extracted too) into PNGs, so the art pays a fetch instead of hundreds of ALU ops - the same
trade the 2D pipelines of that era made.

The layer functions are copied verbatim out of the art, so what gets baked is the art's own code,
not a re-implementation of it. The harness then renders it at 4K and writes the PNG.

Usage: python bake_layers.py [dust|stars]
"""

import os
import re
import subprocess
import sys

WORK = r"C:\Users\jky72\par-term\galaxy-work"
SHADERS = os.path.join(WORK, "shaders")
OUTPUTS = os.path.join(WORK, "outputs")
SOURCE = os.path.join(SHADERS, "kanagawa-starbound.glsl")
HARNESS = os.path.join(WORK, "work", "render_check.py")

SIGNATURE = re.compile(
    r"(?m)^[ \t]*(?:vec[234]|float|int|void|bool|mat[234])[ \t]+(\w+)[ \t]*\([^)]*\)[ \t]*\{"
)


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


def extract(text, name):
    """The verbatim definition of `name`, or None."""
    for match in SIGNATURE.finditer(text):
        if match.group(1) != name:
            continue
        depth = 1
        index = match.end()
        while index < len(text) and depth:
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
            index += 1
        return text[match.start() : index]
    return None


def list_dir(path):
    """Names in a directory, or an empty list when it cannot be read."""
    try:
        return os.listdir(path)
    except OSError as error:
        print(f"cannot list {path}: {error}")
        return []


# Uniforms the extracted layers read, with the values the app runs them at.
# The harness declares the standard par-term uniforms itself, so only the art's own knobs are
# declared here; redeclaring iTime or iResolution fails to compile.
UNIFORMS = """
uniform float iStarGain;
uniform float iTwinkle;
uniform float iPixelSize;
uniform float iDrift;
"""

LAYERS = {
    "dust": {
        "functions": ["hash21", "starDust"],
        # starDust works in physical pixels and reads no cloud field, so it bakes faithfully.
        "body": "    vec2 pixel = fragCoord;\n    fragColor = vec4(starDust(pixel, vec3(0.0)), 1.0);\n",
    },
}


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "dust"
    layer = LAYERS.get(which)
    if layer is None:
        print(f"unknown layer '{which}'; known: {', '.join(LAYERS)}")
        return 1
    art = read_text(SOURCE)
    if art is None:
        return 1

    pieces = []
    for name in layer["functions"]:
        body = extract(art, name)
        if body is None:
            print(f"function '{name}' not found in the art")
            return 1
        pieces.append(body)
        print(f"extracted {name} ({len(body)} B)")

    shader = (
        "/*! par-term shader metadata\n"
        f"name: Baked {which}\n"
        "description: Layer baked out of the starbound art for texture reuse.\n"
        "version: 1.0.0\n"
        "defaults:\n"
        "  animation_speed: 1.0\n"
        "  brightness: 1.0\n"
        "  text_opacity: 1.0\n"
        "  full_content: false\n"
        "  auto_dim_under_text: false\n"
        "*/\n"
        + UNIFORMS
        + "\n"
        + "\n\n".join(pieces)
        + "\n\nvoid mainImage(out vec4 fragColor, in vec2 fragCoord) {\n"
        + layer["body"]
        + "}\n"
    )
    path = os.path.join(SHADERS, f"bake-{which}.glsl")
    if not write_text(path, shader):
        return 1
    print(f"wrote {path} ({len(shader)} B)")

    try:
        proc = subprocess.run(
            [sys.executable, HARNESS, path, f"tag=bake-{which}"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError as error:
        print(f"harness did not start: {error}")
        return 1
    found = re.search(r'"gpu_ms_median"\s*:\s*([0-9.]+)', proc.stdout)
    if found:
        print(f"baked layer renders in {found.group(1)} ms at 4K")
    else:
        print("harness reported no timing; last lines:")
        print("\n".join(proc.stdout.splitlines()[-6:]))
    made = [
        name
        for name in list_dir(OUTPUTS)
        if name.startswith(f"bake-{which}") or f"bake-{which}" in name
    ]
    for name in made:
        print(f"  output: {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
