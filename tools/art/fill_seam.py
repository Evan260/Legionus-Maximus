"""Scatters the tile's own leaves and flowers into the repainted seam bands and matches their brightness, so the
band does not show as a plain stripe once the ground repeats.

Usage: python tools/art/fill_seam.py tile.png --band 116 140 --out tile_fixed.png
"""
import argparse

import numpy as np
from PIL import Image
from scipy import ndimage

p = argparse.ArgumentParser()
p.add_argument("tile")
p.add_argument("--band", nargs=2, type=int, default=(116, 140))
p.add_argument("--seed", type=int, default=3)
p.add_argument("--out", required=True)
a = p.parse_args()

img = np.array(Image.open(a.tile).convert("RGB")).astype(int)
H, W, _ = img.shape
b0, b1 = a.band
in_band = np.zeros((H, W), bool)
in_band[b0:b1, :] = True
in_band[:, b0:b1] = True

# Leaves are warmer than the grass and flowers are much paler, so either stands out by colour alone.
r, g, bl = img[..., 0], img[..., 1], img[..., 2]
decal = ((r > g + 8) & (r > 70)) | (img.sum(-1) > 400)
labels, n = ndimage.label(ndimage.binary_dilation(decal, iterations=1))
pieces = []
for i, sl in enumerate(ndimage.find_objects(labels), 1):
    h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
    if 3 <= h <= 14 and 3 <= w <= 14 and not in_band[sl].any():
        pieces.append((sl, labels[sl] == i))

# The band is brought back to the tile's own colour, channel by channel, since it comes back a shade greener.
gain = img[~in_band].mean(0) / img[in_band].mean(0)
img[in_band] = np.clip(img[in_band] * gain, 0, 255).astype(int)

rng = np.random.default_rng(a.seed)
# The tile's own density of leaves is kept inside the band.
want = int(len(pieces) * in_band.mean() / max(1e-6, 1 - in_band.mean()))
placed = 0
for _ in range(want * 20):
    if placed >= want:
        break
    sl, m = pieces[rng.integers(len(pieces))]
    h, w = m.shape
    y, x = int(rng.integers(0, H - h)), int(rng.integers(0, W - w))
    if not in_band[y:y + h, x:x + w].all():
        continue
    src = img[sl]
    dst = img[y:y + h, x:x + w]
    dst[m] = src[m]
    placed += 1
Image.fromarray(img.astype(np.uint8)).save(a.out)
print(f"placed {placed} of {len(pieces)} pieces, colour gain {np.round(gain, 3)}")
