"""Makes a square ground texture repeat without seams: the texture is shifted half a tile so its edges meet in the
middle, and a wavy band over that join is filled from the unshifted texture, whose middle has no seam. A plant or stone
that the band's edge would cut is taken whole from one side.

Usage: python tools/art/make_seamless.py ground.png --out ground_tile.png [--value 0.9 --saturation 0.95]
"""
import argparse

import cv2
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


THING_MOST = 300


def things(img):
    """Each plant or stone as a labelled blob: pixels that stand out from the ground around them, grown by a pixel."""
    lum = img.astype(float).mean(-1)
    ground = cv2.GaussianBlur(lum, (0, 0), 6)
    out = (np.abs(lum - ground) > 24).astype(np.uint8)
    out = cv2.dilate(out, np.ones((3, 3), np.uint8))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(out, connectivity=8)
    # Larger blobs are the ground's own light and shade, which blends across the band's edge anyway.
    for k in range(1, count):
        if stats[k, cv2.CC_STAT_AREA] > THING_MOST:
            labels[labels == k] = 0
    return labels


def edge_of(mask):
    return mask ^ cv2.erode(mask.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)


mask = band(yy, xx, 0.3) | band(xx, yy, 1.7)
# A cut thing goes wholly to one side, the band's when the shifted texture's own join already breaks it, and each move can cut another, so this repeats.
mine, theirs = things(orig), things(rolled)
for _ in range(6):
    before = mask.copy()
    for labels, take in ((mine, True), (theirs, False)):
        rim = edge_of(mask)
        for k in np.unique(labels[rim]):
            if k == 0:
                continue
            blob = labels == k
            if blob[0].any() or blob[-1].any() or blob[:, 0].any() or blob[:, -1].any():
                continue
            broken = blob[half - 1:half + 1].any() or blob[:, half - 1:half + 1].any()
            mask = mask | blob if take or broken else mask & ~blob
    if (mask == before).all():
        break
rolled[mask] = orig[mask]
hsv = np.array(Image.fromarray(rolled).convert("HSV")).astype(float)
hsv[..., 1] *= a.saturation
hsv[..., 2] *= a.value
Image.fromarray(np.clip(hsv, 0, 255).astype(np.uint8), "HSV").convert("RGB").save(a.out)
print("saved", a.out)
