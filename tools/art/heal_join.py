"""Heals the top and bottom edges of a ground texture where they meet as it repeats, for a texture whose join cuts
through a plant and so shows as a straight line across the field every tile.

The texture is turned so the join lies inside it, the stretch of the join where the two edges differ most is marked,
together with every plant that reaches into it, and that patch is painted over from the ground round it (OpenCV's
inpainting). It suits soft painted ground such as Sarmatia's; on grainy ground the painted patch shows as a smudge.

Usage: python tools/art/heal_join.py game/assets/grounds/sarmatia.png [--out OUT]
"""
import argparse

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

p = argparse.ArgumentParser()
p.add_argument("image")
p.add_argument("--out", help="where to write it (the image itself by default)")
args = p.parse_args()
src, out = args.image, args.out or args.image
a = np.asarray(Image.open(src).convert("RGB")).copy()
n = a.shape[0]
shift = 24
r = np.roll(a, shift, 0)  # the join now lies between rows shift-1 and shift
f = r.astype(float)
step = (f[shift] - f[shift - 1]).mean(axis=1)
step = np.convolve(np.concatenate([step[-8:], step, step[:8]]), np.ones(9) / 9, mode="same")[8:-8]
bad = np.abs(step) > 10
bad = ndimage.binary_dilation(bad, iterations=3)
mask = np.zeros(r.shape[:2], bool)
mask[shift - 6:shift + 6, bad] = True
# Whole blades of feather grass touching the band go too, so no tuft is left cut.
luma = f.mean(axis=2)
ground = ndimage.uniform_filter(luma, 21)
light = (luma - ground) > 6
near = np.zeros_like(mask)
near[shift - 28:shift + 28, :] = True
lab, k = ndimage.label(ndimage.binary_dilation(light & near, iterations=2))
for i in range(1, k + 1):
    blob = lab == i
    if (blob & mask).any():
        mask |= ndimage.binary_dilation(blob, iterations=3)
mask = ndimage.binary_dilation(mask, iterations=1)
healed = cv2.inpaint(r, mask.astype(np.uint8) * 255, 6, cv2.INPAINT_TELEA)
res = np.roll(healed, -shift, 0)
Image.fromarray(res).save(out)
print("healed %d pixels in columns %d..%d" % (mask.sum(), np.where(bad)[0].min(), np.where(bad)[0].max()))
