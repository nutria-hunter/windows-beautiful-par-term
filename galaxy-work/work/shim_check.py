"""Measure how much a fast mover boils: align two frames by phase correlation, then look at the
residual. A sprite placed on the pixel grid translates exactly, so the residual stays near zero; one
placed at fractional coordinates repaints its whole silhouette every frame."""
import sys

import numpy as np
from PIL import Image

BOX = (620, 1100, 1520, 1900)


def lum(tag):
    img = Image.open(f"../outputs/kanagawa-starbound-{tag}-4k.png").convert("L")
    return np.asarray(img).astype(np.float32)[BOX[1] : BOX[3], BOX[0] : BOX[2]]


def report(tag_a, tag_b):
    a, b = lum(tag_a), lum(tag_b)
    spec = np.fft.rfft2(a) * np.conj(np.fft.rfft2(b))
    spec /= np.abs(spec) + 1e-6
    corr = np.fft.irfft2(spec, a.shape)
    dy, dx = np.unravel_index(int(np.argmax(corr)), corr.shape)
    shifted = np.roll(np.roll(b, dy, axis=0), dx, axis=1)
    d = np.abs(a - shifted)
    frac = float((d > 8).mean() * 100.0)
    print(f"{tag_a} -> {tag_b}: 정렬 시프트 dx={dx} dy={dy}  잔차 {frac:.2f}%")
    return frac


if __name__ == "__main__":
    report(sys.argv[1], sys.argv[2])
