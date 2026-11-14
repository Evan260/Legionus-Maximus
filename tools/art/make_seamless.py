"""Makes a square ground texture repeat without seams: the texture is shifted half a tile so its edges meet in the
middle, and a wavy band over that join is filled from the unshifted texture, whose middle has no seam.

Usage: python tools/art/make_seamless.py ground.png --out ground_tile.png
"""
import argparse

import numpy as np
from PIL import Image

p = argparse.ArgumentParser()
p.add_argument("image")
p.add_argument("--out", required=True)
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
Image.fromarray(rolled).save(a.out)
print("saved", a.out)
