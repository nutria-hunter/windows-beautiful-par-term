"""Measure how exactly the procedural GLSL matches the baked sprite it came from.

Usage: python pf_match.py <sprite.png> <render-4k.png> [pp]
The render must be produced by the harness in galaxy-work/shaders/t-proc.glsl (2 screen px per
source pixel, centred). Prints exact-match and thresholded agreement, and writes a side-by-side.
Baked sprite = ground truth; this number is the only honest check on the emitter.
"""
import sys
import numpy as np
from PIL import Image

sprite, render = sys.argv[1], sys.argv[2]
pp = int(sys.argv[3]) if len(sys.argv) > 3 else 2
ref = np.asarray(Image.open(sprite).convert('RGBA')).astype(np.int16)
big = np.asarray(Image.open(render).convert('RGB')).astype(np.int16)
h, w = ref.shape[:2]
H, W = big.shape[:2]
ox, oy = int(W * 0.5 - w * pp), int(H * 0.5 - h * pp)
alpha = ref[:, :, 3] > 0
bg = np.array([8, 10, 16])
full = np.where(alpha[:, :, None], ref[:, :, :3], bg)
for flip in (False, True):
    got = np.zeros((h, w, 3), np.int16)
    for j in range(h):
        for i in range(w):
            y = oy + pp * j + pp // 2
            if flip:
                y = H - 1 - y
            got[j, i] = big[y, ox + pp * i + pp // 2]
    d = np.abs(got - full).max(axis=2)
    print('flip=%-5s exact %6.2f%%  <=2 %6.2f%%  <=8 %6.2f%%  max %3d'
          % (flip, 100 * (d == 0).mean(), 100 * (d <= 2).mean(), 100 * (d <= 8).mean(), d.max()))
    if not flip:
        Image.fromarray((d > 2).astype(np.uint8) * 255).resize((w * 3, h * 3), Image.Resampling.NEAREST).save('pf_diff.png')
        print('mismatch map -> pf_diff.png')
