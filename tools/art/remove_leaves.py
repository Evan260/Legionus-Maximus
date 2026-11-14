"""Removes the fallen leaves from a seamless grass tile by filling each one with grass from a few pixels away, which
in noisy grass leaves no trace. The tile stays seamless because the copy wraps round its edges.

Usage: python tools/art/remove_leaves.py tile.png --out tile_clean.png
"""
import argparse

import numpy as np
from PIL import Image
from scipy import ndimage

p = argparse.ArgumentParser()
p.add_argument("tile")
p.add_argument("--out", required=True)
a = p.parse_args()

img = np.array(Image.open(a.tile).convert("RGB")).astype(int)
r, g, b = img[..., 0], img[..., 1], img[..., 2]
# Leaves are the only warm, orange-brown pixels in the grass.
leaf = ndimage.binary_dilation((r > g + 6) & (r > 60), iterations=2)
out = img.copy()
for dy, dx in ((7, 11), (-9, 6), (12, -8), (-6, -13), (15, 15), (-14, -3)):
    src = np.roll(np.roll(img, dy, 0), dx, 1)
    src_leaf = np.roll(np.roll(leaf, dy, 0), dx, 1)
    take = leaf & ~src_leaf
    out[take] = src[take]
    leaf = leaf & ~take
Image.fromarray(out.astype(np.uint8)).save(a.out)
print("saved", a.out, "pixels left unfilled:", int(leaf.sum()))
