"""Makes a square ground texture repeat without seams: the texture is shifted half a tile so its edges meet in the
middle, and a wavy band over that join is filled from the unshifted texture, whose middle has no seam.

Usage: python tools/art/make_seamless.py ground.png --out ground_tile.png [--value 0.9 --saturation 0.95]
"""
import argparse

import numpy as np
from PIL import Image

p = argparse.ArgumentParser()
p.add_argument("image")
p.add_argument("--out", required=True)
# A ground that comes out brighter than Germania's is scaled down so the units on it stay easy to read.
p.add_argument("--value", type=float, default=1.0)
p.add_argument("--saturation", type=float, default=1.0)
a = p.parse_args()

orig = np.array(Image.open(a.image).convert("RGB"))
n = orig.shape[0]
half = n // 2
rolled = np.roll(np.roll(orig, half, 0), half, 1)
yy, xx = np.mgrid[0:n, 0:n]


def band(across, along, seed):
    # A wavy edge keeps the join from lining up into a straight stripe once the tile repeats.
    width = n / 25 + n / 50 * np.sin(along / 9.0 + seed) + n / 85 * np.sin(along / 4.3 + 2 * seed)
    return np.abs(across - half - n / 42 * np.sin(along / 17.0 + 3 * seed)) < width


mask = band(yy, xx, 0.3) | band(xx, yy, 1.7)
rolled[mask] = orig[mask]
hsv = np.array(Image.fromarray(rolled).convert("HSV")).astype(float)
hsv[..., 1] *= a.saturation
hsv[..., 2] *= a.value
Image.fromarray(np.clip(hsv, 0, 255).astype(np.uint8), "HSV").convert("RGB").save(a.out)
print("saved", a.out)
