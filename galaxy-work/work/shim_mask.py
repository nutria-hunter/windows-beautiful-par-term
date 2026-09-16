"""Compare the rock masks of two frames at the belt's expected shift.

A sprite on the pixel grid translates as an exact copy, so its mask at t2, moved back by the belt's
motion, should overlap the mask at t1 almost perfectly. A sprite at fractional coordinates repaints
its outline every frame, so even the best whole-pixel shift leaves a ragged mismatch.
"""
import sys

import numpy as np
from PIL import Image

BOX = (620, 1100, 1520, 1900)


def rock_mask(tag):
    a = np.asarray(Image.open(f"../outputs/kanagawa-starbound-{tag}-4k.png").convert("RGB")).astype(np.int16)
    a = a[BOX[1] : BOX[3], BOX[0] : BOX[2]]
    r, g = a[:, :, 0], a[:, :, 1]
    m = ((np.abs(r - 96) < 26) & (np.abs(g - 92) < 26))
    m |= ((np.abs(r - 134) < 24) & (np.abs(g - 128) < 24))
    m |= ((np.abs(r - 52) < 14) & (np.abs(g - 50) < 14))
    m |= ((np.abs(r - 158) < 22) & (np.abs(g - 150) < 22))
    return m


def best_iou(tag_a, tag_b):
    m1, m2 = rock_mask(tag_a), rock_mask(tag_b)
    best = (0.0, 0)
    for shift in range(8, 72):
        m2s = np.roll(m2, shift, axis=1)
        union = int((m1 | m2s).sum())
        if union == 0:
            continue
        iou = int((m1 & m2s).sum()) / union
        if iou > best[0]:
            best = (iou, shift)
    return best, int(m1.sum()), int(m2.sum())


if __name__ == "__main__":
    (iou, shift), n1, n2 = best_iou(sys.argv[1], sys.argv[2])
    print(f"{sys.argv[1]} -> {sys.argv[2]}: 암석 픽셀 {n1}/{n2}, 최적 시프트 {shift}px, IoU {iou*100:.1f}%")
