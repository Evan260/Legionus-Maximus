"""Makes a square ground texture repeat without seams: the texture is shifted half a tile so its edges meet in the
middle, and a band over that join is filled from the unshifted texture, whose middle has no seam. Each edge of the band
follows the path where the two textures differ least, so it runs between the ground's mounds and tufts instead of across
them. A plant or stone that the band's edge would still cut is taken whole from one side.

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


# How far from the join each edge of the band may wander, and how near it must stay, in pixels.
REACH = 44
NEAR = 4


def cheapest_loop(cost):
    """For each row of cost, the column of the cheapest path from the top row to the bottom that steps at most a pixel
    aside each row and ends in the column it starts in, so the band meets itself where the tile repeats."""
    rows, cols = cost.shape
    best, path = np.inf, None
    for start in range(cols):
        acc = np.full(cols, np.inf)
        acc[start] = cost[0, start]
        back = np.zeros((rows, cols), int)
        for y in range(1, rows):
            ways = np.stack([np.r_[np.inf, acc[:-1]], acc, np.r_[acc[1:], np.inf]])
            back[y] = np.arange(cols) + ways.argmin(0) - 1
            acc = ways.min(0) + cost[y]
        if acc[start] < best:
            best, x, path = acc[start], start, [start]
            for y in range(rows - 1, 0, -1):
                x = back[y, x]
                path.append(x)
    return np.array(path[::-1])


def band(cost):
    """The band down the middle of the tile: between a path left of the join and one right of it."""
    left = half - REACH + cheapest_loop(cost[:, half - REACH:half - NEAR])
    right = half + NEAR + cheapest_loop(cost[:, half + NEAR:half + REACH])
    return (xx >= left[:, None]) & (xx < right[:, None])


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


mine, theirs = things(orig), things(rolled)
# The band's edge runs where the two textures look most alike, and goes round the plants and stones of either.
cost = np.abs(rolled.astype(float) - orig).sum(-1) + 2000.0 * ((mine > 0) | (theirs > 0))
across = band(cost)
mask = across | band((cost * ~across).T).T
# A cut thing goes wholly to one side, the band's when the shifted texture's own join already breaks it, and each move can cut another, so this repeats.
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
