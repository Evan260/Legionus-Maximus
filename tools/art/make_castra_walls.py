"""Builds the fort's two wall strips from the palisade picture's own pixels, so they repeat without a seam:
wall_tile.png runs east-west and side_tile.png runs north-south. Run once; the atlas reads both from raw/castra."""
from pathlib import Path

import numpy as np
from PIL import Image

RAW = Path(__file__).parent / "raw" / "castra"
PERIOD = 4
STAKES = 8
SLOPE = 0.2


def level(a):
    """The palisade picture with its slant taken out, so the bank runs straight."""
    out = np.zeros((a.shape[0] + 12, a.shape[1], 4), np.uint8)
    for x in range(a.shape[1]):
        s = int(round(SLOPE * (57 - x)))
        for y in range(a.shape[0]):
            if 0 <= y - s + 8 < out.shape[0]:
                out[y - s + 8, x] = a[y, x]
    return out


def wall_tile(a):
    # The stakes start every 4 columns from column 6, so a tile cut from column 18 ends on a whole stake.
    x0, w = 18, PERIOD * STAKES
    tile = a[10:44, x0:x0 + w].copy()
    bank = slice(29 - 10, 43 - 10)
    # The last columns of the bank fade into the columns just before the tile's start, so one tile runs into the next.
    for t in range(w - 8, w):
        k = (t - (w - 9)) / 9.0
        before = a[29:43, x0 + t - w].astype(float)
        tile[bank, t] = (tile[bank, t].astype(float) * (1 - k) + before * k).astype(np.uint8)
    return tile


def side_tile(a, height=36, step=6):
    stakes = [a[12:30, x:x + 5] for x in (18, 22, 26, 30)]
    grass = np.concatenate([a[30:37, 10:54], a[30:37, 10:54][::-1, ::-1]])
    earth = a[41, 20, :3]
    w = 16
    top = 18
    tile = np.zeros((top + height, w, 4), np.uint8)
    # The bank's grass top runs down the strip, cut from the front wall's grass and turned on its side, edged with earth.
    band = np.rot90(grass)[:height]
    for y in range(height):
        row = top - 2 + y
        tile[row, 2:w - 2] = band[y % band.shape[0], :w - 4]
        tile[row, 1, :3] = earth
        tile[row, w - 2, :3] = earth
        tile[row, 1, 3] = tile[row, w - 2, 3] = 255
        tile[row, 0, :3] = earth * 0.6
        tile[row, w - 1, :3] = earth * 0.6
        tile[row, 0, 3] = tile[row, w - 1, 3] = 255
    # Stakes from the far end to the near end, each foot a step lower, so the nearer stake hides all but the point of the one behind.
    for k in range(height // step):
        s = stakes[k % len(stakes)]
        foot = top + k * step + 2
        y0 = foot - s.shape[0]
        x0 = (w - s.shape[1]) // 2
        region = tile[y0:foot, x0:x0 + s.shape[1]]
        alpha = s[..., 3:4] > 0
        region[:] = np.where(alpha, s, region)
    return tile


def main():
    a = level(np.asarray(Image.open(RAW / "wall_h.png").convert("RGBA")))
    Image.fromarray(wall_tile(a)).save(RAW / "wall_tile.png")
    Image.fromarray(side_tile(a)).save(RAW / "side_tile.png")


if __name__ == "__main__":
    main()
