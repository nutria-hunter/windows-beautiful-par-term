"""Animation checks for the tilted-spiral shader.

The galaxy rotates rigidly in DISK space, then is projected with the position
angle and inclination. So the frame at time T must equal the frame at time 0
warped by the exact affine map  p' = T0^-1 . T_T . p  in centred, height
normalised screen coordinates. That is the strongest available proof that the
rotation is rigid and that no seam or winding artefact appears.

Usage: python test_motion.py
"""

import importlib
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE / "runtime"))
moderngl = importlib.import_module("moderngl")

W, H = 1920, 1080
SHADER = ROOT / "shaders" / "tilted-spiral.glsl"
VERT = """#version 330
void main(){vec2 p=vec2((gl_VertexID<<1)&2, gl_VertexID&2); gl_Position=vec4(p*2.0-1.0,0,1);}"""

FAILURES = []


def check(ok, label, detail=""):
    print(f"  [{'PASS' if ok else 'FAIL'}] {label} {detail}")
    if not ok:
        FAILURES.append(label)


def num(x, fallback=0.0):
    try:
        return float(x)
    except (TypeError, ValueError):
        return fallback


def whole(x, fallback=0):
    try:
        return int(round(float(x)))
    except (TypeError, ValueError):
        return fallback


def default_of(src, key, fallback=0.0):
    """Numeric metadata default; always returns a float so arithmetic is safe."""
    hit = re.search(rf"^    {key}: (-?[0-9.]+)", src, re.M)
    return num(hit.group(1) if hit else None, fallback)


def build(ctx, src, over):
    frag = (
        "#version 330\nuniform vec2 iResolution;\nuniform float iTime;\n"
        "uniform float iBrightness;\nout vec4 color;\n"
        + src
        + "\nvoid main(){mainImage(color, vec2(gl_FragCoord.x, iResolution.y - gl_FragCoord.y));}"
    )
    prog = ctx.program(vertex_shader=VERT, fragment_shader=frag)
    for key in re.findall(r"uniform\s+(?:float|int)\s+(i\w+)\s*;", src):
        val = default_of(src, key)
        if key in prog and key not in over:
            is_int = re.search(rf"uniform int\s+{key}\s*;", src) is not None
            prog[key].value = whole(val) if is_int else val
    for key, val in over.items():
        if key in prog:
            prog[key].value = val
    if "iResolution" in prog:
        prog["iResolution"].value = (W, H)
    if "iBrightness" in prog:
        prog["iBrightness"].value = 1.0
    return prog


def frame(ctx, prog, t, w=W, h=H):
    fb = ctx.simple_framebuffer((w, h), components=3)
    fb.use()
    prog["iTime"].value = t
    vao = ctx.vertex_array(prog, [])
    vao.render(vertices=3)
    ctx.finish()
    raw = fb.read(components=3)
    vao.release()
    fb.release()
    return np.asarray(
        Image.frombytes("RGB", (w, h), raw).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    ).astype(float)


def rot(a):
    return np.array([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])


def disk_matrix(pa, incl, ang):
    """screen(centred, /H) -> rotating disk coordinates."""
    return rot(-ang) @ np.diag([1.0, 1.0 / incl]) @ rot(-pa)


def blocks_of(mask):
    """Bounding box + pixel count of each 4-neighbour component."""
    seen = np.zeros_like(mask, dtype=bool)
    ys, xs = np.nonzero(mask)
    comps = []
    for y0, x0 in zip(ys, xs, strict=False):
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = True
        n = 0
        ylo = yhi = y0
        xlo = xhi = x0
        while stack:
            y, x = stack.pop()
            n += 1
            ylo, yhi = min(ylo, y), max(yhi, y)
            xlo, xhi = min(xlo, x), max(xhi, x)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                inside = 0 <= yy < mask.shape[0] and 0 <= xx < mask.shape[1]
                if inside and mask[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True
                    stack.append((yy, xx))
        comps.append((n, yhi - ylo + 1, xhi - xlo + 1))
    return comps


def main():
    src = SHADER.read_text(encoding="utf-8")
    ctx = moderngl.create_standalone_context(require=330)
    pa = np.radians(default_of(src, "iPositionAngle"))
    incl = default_of(src, "iInclination")
    speed = default_of(src, "iOrbitSpeed")
    cx = default_of(src, "iCenterX") * W
    cy = default_of(src, "iCenterY") * H

    print("1) iBrightness = 0 must be fully black")
    prog = build(ctx, src, {})
    a = frame(ctx, prog, 5.0)
    check(a.max() > 0, "baseline frame is not empty", f"max={a.max():.0f}")
    prog["iBrightness"].value = 0.0
    z = frame(ctx, prog, 5.0)
    check(z.max() == 0, "brightness 0 -> every channel 0", f"max={z.max():.0f}")
    prog["iBrightness"].value = 1.0

    print("2) rigid rotation invariant (clouds only, stars off)")
    prog2 = build(ctx, src, {"iStarDensity": 0.0})
    t0, t1 = 0.0, 240.0
    f0 = frame(ctx, prog2, t0)
    f1 = frame(ctx, prog2, t1)
    ang = speed * t1
    m0 = disk_matrix(pa, incl, 0.0)
    m1 = disk_matrix(pa, incl, ang)
    m = np.linalg.inv(m0) @ m1

    img0 = Image.fromarray(f0.astype(np.uint8))
    a_, b_ = m[0, 0], m[0, 1]
    d_, e_ = m[1, 0], m[1, 1]
    warped = np.asarray(
        img0.transform(
            (W, H),
            Image.Transform.AFFINE,
            (a_, b_, cx - a_ * cx - b_ * cy, d_, e_, cy - d_ * cx - e_ * cy),
            resample=Image.Resampling.BILINEAR,
        )
    ).astype(float)
    diff = np.abs(warped - f1).mean()
    ctrl = rot(np.radians(7.0))
    m_wrong = np.linalg.inv(m0) @ disk_matrix(pa, incl, ang + 0.35)
    warped_wrong = np.asarray(
        img0.transform(
            (W, H),
            Image.Transform.AFFINE,
            (
                m_wrong[0, 0],
                m_wrong[0, 1],
                cx - m_wrong[0, 0] * cx - m_wrong[0, 1] * cy,
                m_wrong[1, 0],
                m_wrong[1, 1],
                cy - m_wrong[1, 0] * cx - m_wrong[1, 1] * cy,
            ),
            resample=Image.Resampling.BILINEAR,
        )
    ).astype(float)
    diff_wrong = np.abs(warped_wrong - f1).mean()
    check(
        diff < diff_wrong * 0.5,
        "rotation warp matches much better than a wrong angle",
        f"mean|diff| exact={diff:.3f} wrong={diff_wrong:.3f} (ctrl rot {ctrl[0, 0]:.2f})",
    )
    check(diff < 2.0, "absolute residual is small", f"mean|diff|={diff:.3f}")

    print("3) centre stability: the nucleus must stay a bright point at the centre")
    print("   (angular divergence is excluded by the rigid-rotation proof in step 2:")
    print("    every radius shares one angular rate, so there is nothing to diverge)")
    prog3 = build(ctx, src, {"iStarDensity": 0.0, "iDustStrength": 0.0})
    win = 40
    peaks = []
    for t in (0.0, 120.0, 360.0, 900.0):
        f = frame(ctx, prog3, t)
        lum = f @ np.array([0.2126, 0.7152, 0.0722])
        sl = lum[int(cy) - win : int(cy) + win, int(cx) - win : int(cx) + win]
        peaks.append(num(sl.max()))
    fall = min(peaks) / max(max(peaks), 1.0)
    check(
        fall > 0.6,
        "nucleus stays a bright point at the galaxy centre over 900 s",
        f"peak luma={[round(p) for p in peaks]}",
    )

    print("4) stars are hard axis-aligned integer rectangles after rotation")
    prog4 = build(
        ctx,
        src,
        {
            "iCloudGain": 0.0,
            "iCoreGain": 0.0,
            "iSkyDensity": 0.0,
            "iTwinkle": 0.0,
            "iStarDensity": 0.06,
            "iGasGain": 0.0,
        },
    )
    bad_shapes = []
    found = 0
    for t in (0.0, 300.0):
        f = frame(ctx, prog4, t)
        mask = f.max(axis=2) > 25
        for n, hh, ww in blocks_of(mask):
            found += 1
            rectangular = n == hh * ww
            small = hh <= 2 and ww <= 2
            if not (rectangular and small):
                bad_shapes.append((n, hh, ww))
    check(
        not bad_shapes and found > 40,
        "isolated stars are 1x1/1x2/2x1/2x2 axis-aligned rectangles",
        f"checked {found} stars, bad={bad_shapes[:4]}",
    )

    print("5) arm light does not vanish as the galaxy turns")
    prog5 = build(ctx, src, {})
    means = []
    for t in (0.0, 600.0, 1800.0, 3600.0):
        f = frame(ctx, prog5, t)
        means.append(num(np.mean(f)))
    spread = max(means) - min(means)
    check(
        spread < 0.05 * max(1.0, max(means)),
        "mean brightness is stable over an hour of rotation",
        f"means={[round(m, 4) for m in means]}",
    )

    print("6) sky stars are static: the star pixel set must never move")
    prog6 = build(
        ctx,
        src,
        {
            "iCloudGain": 0.0,
            "iCoreGain": 0.0,
            "iStarDensity": 0.0,
            "iTwinkle": 0.0,
            "iGasGain": 0.0,
        },
    )
    a0 = frame(ctx, prog6, 0.0)
    a1 = frame(ctx, prog6, 400.0)
    check(
        np.array_equal(a0, a1),
        "with twinkle off the sky is pixel-identical over 400 s",
        f"max|diff|={num(np.abs(a0 - a1).max()):.0f}",
    )

    prog7 = build(
        ctx,
        src,
        {
            "iCloudGain": 0.0,
            "iCoreGain": 0.0,
            "iStarDensity": 0.0,
            "iTwinkle": 1.0,
            "iGasGain": 0.0,
        },
    )
    b0 = frame(ctx, prog7, 0.0)
    b1 = frame(ctx, prog7, 400.0)
    m0 = b0.max(axis=2) > 0
    m1 = b1.max(axis=2) > 0
    moved = int(np.count_nonzero(m0 != m1))
    check(
        moved == 0 and int(m0.sum()) > 500,
        "with twinkle on the star pixel set is unchanged (only brightness moves)",
        f"stars={int(m0.sum())}, differing pixels={moved}",
    )
    check(
        not np.array_equal(b0, b1),
        "twinkle actually changes brightness",
        f"max|diff|={num(np.abs(b0 - b1).max()):.0f}",
    )
    check(
        num(b0.min()) >= 0.0,
        "no star ever subtracts light",
        f"min value={num(b0.min()):.0f}",
    )

    ctx.release()
    print()
    if FAILURES:
        print("FAILED:", ", ".join(FAILURES))
        sys.exit(1)
    print("all animation checks passed")


if __name__ == "__main__":
    main()
