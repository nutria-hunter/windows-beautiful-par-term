"""Render a par-term background shader at 4K offscreen and report GPU time + stats.

Usage:  python render_check.py <shader-file-name> [...]
Reads from  galaxy-work/shaders/<name>, writes to galaxy-work/outputs/.
"""

import importlib
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE / "runtime"))

W, H = 3840, 2160
WARMUP = 4
SAMPLES = 10
FIXED_TIME = 12.0

VERT = """#version 330
void main(){vec2 p=vec2((gl_VertexID<<1)&2, gl_VertexID&2); gl_Position=vec4(p*2.0-1.0,0,1);}"""


def num(x, fallback=0.0):
    """Safe numeric conversion so a malformed value can never crash the run."""
    try:
        return float(x)
    except (TypeError, ValueError):
        return fallback


def whole(x, fallback=0):
    """Safe integer conversion with the same guarantee."""
    try:
        return int(round(float(x)))
    except (TypeError, ValueError):
        return fallback


def default_of(source, key):
    """Read a default from the metadata block, tolerating negatives."""
    hit = re.search(rf"^    {key}: (-?[0-9.]+)", source, re.M)
    if not hit:
        return None
    text = hit.group(1)
    is_int = re.search(rf"uniform int\s+{key}\s*;", source) is not None
    return whole(text) if is_int else num(text)


def build(ctx, source, w, h, over=None):
    frag = (
        "#version 330\nuniform vec2 iResolution;\nuniform float iTime;\n"
        "uniform float iBrightness;\nout vec4 color;\n"
        + source
        + "\nvoid main(){mainImage(color, vec2(gl_FragCoord.x, iResolution.y - gl_FragCoord.y));}"
    )
    prog = ctx.program(vertex_shader=VERT, fragment_shader=frag)
    for key in re.findall(r"uniform\s+(?:float|int)\s+(i\w+)\s*;", source):
        val = default_of(source, key)
        if key in prog and val is not None:
            prog[key].value = val
    for key, val in (over or {}).items():
        if key in prog:
            prog[key].value = whole(val) if isinstance(val, int) else num(val)
    if "iResolution" in prog:
        prog["iResolution"].value = (w, h)
    if "iBrightness" in prog:
        prog["iBrightness"].value = 1.0
    return prog


def parse_args(argv):
    """shader.glsl  [tag=NAME] [w=NNN] [h=NNN] [t=SECONDS] [iUniform=VALUE ...]"""
    shader = None
    over = {}
    tag = ""
    w, h = W, H
    t = FIXED_TIME
    for a in argv:
        if "=" in a and not a.endswith(".glsl"):
            k, v = a.split("=", 1)
            if k == "tag":
                tag = v
            elif k == "w":
                w = whole(v, W)
            elif k == "h":
                h = whole(v, H)
            elif k == "t":
                # Scene time for the capture. The scenery rides closed orbits, so a later moment
                # is the only way to photograph a body that is off-screen at the default time.
                t = num(v, FIXED_TIME)
            else:
                over[k] = whole(v) if re.fullmatch(r"-?\d+", v) else num(v)
        elif shader is None:
            shader = a
    return (shader or "tilted-spiral.glsl"), over, tag, w, h, t


def shade(ctx, prog, w, h, t):
    fb = ctx.simple_framebuffer((w, h), components=3)
    fb.use()
    prog["iTime"].value = t
    vao = ctx.vertex_array(prog, [])
    vao.render(vertices=3)
    ctx.finish()
    raw = fb.read(components=3)
    img = Image.frombytes("RGB", (w, h), raw).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    vao.release()
    fb.release()
    return img


def stats(arr):
    lum = arr @ np.array([0.2126, 0.7152, 0.0722])
    return {
        "black_fraction": num(np.mean(arr.max(axis=2) == 0)),
        "luma_median": num(np.median(lum)),
        "luma_p95": num(np.percentile(lum, 95)),
        "luma_p99": num(np.percentile(lum, 99)),
        "luma_max": num(lum.max()),
    }


def main():
    moderngl = importlib.import_module("moderngl")
    shader, over, tag, w, h, t = parse_args(sys.argv[1:])
    ctx = moderngl.create_standalone_context(require=330)
    report = {
        "renderer": ctx.info["GL_RENDERER"],
        "resolution": [w, h],
        "overrides": over,
        "results": {},
    }

    src = (ROOT / "shaders" / shader).read_text(encoding="utf-8")
    prog = build(ctx, src, w, h, over)
    fb = ctx.simple_framebuffer((w, h), components=3)
    fb.use()
    vao = ctx.vertex_array(prog, [])

    times = []
    for i in range(WARMUP + SAMPLES):
        prog["iTime"].value = t
        q = ctx.query(time=True)
        with q:
            vao.render(vertices=3)
        ctx.finish()
        if i >= WARMUP:
            times.append(num(q.elapsed) / 1e6)
    vao.release()

    img = shade(ctx, prog, w, h, t)
    stem = Path(shader).stem + ("-" + tag if tag else "")
    (ROOT / "outputs").mkdir(exist_ok=True)
    img.save(ROOT / "outputs" / f"{stem}-4k.png")
    if w >= 1200:
        img.resize((w // 2, h // 2), Image.Resampling.LANCZOS).save(
            ROOT / "outputs" / f"{stem}-half.png"
        )

    entry = {
        "gpu_ms_median": num(np.median(times)),
        "gpu_ms_p95": num(np.percentile(times, 95)),
        "gpu_ms_min": num(np.min(times)),
    }
    entry.update(stats(np.asarray(img).astype(float)))

    prog["iBrightness"].value = 0.0
    blank = np.asarray(shade(ctx, prog, 256, 144, t))
    entry["brightness_zero_is_black"] = bool(blank.max() == 0)
    prog["iBrightness"].value = 1.0

    report["results"][stem] = entry
    prog.release()
    ctx.release()

    out = ROOT / "outputs" / "validation.json"
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report["results"], indent=2))


if __name__ == "__main__":
    main()
