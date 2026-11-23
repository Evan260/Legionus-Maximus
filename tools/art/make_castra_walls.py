"""Builds the fort's two wall strips from the palisade picture's own pixels, so they repeat without a seam:
wall_tile.png runs east-west and side_tile.png runs north-south, and a copy of each per fort ground (wall_tile_sand.png
and so on) has its bank repainted in that ground by fort_ground.py. Run once; the atlas reads them all from raw/castra."""
from pathlib import Path

import numpy as np
from PIL import Image

import fort_ground

RAW = Path(__file__).parent / "raw" / "castra"
PERIOD = 4
STAKES = 8
SLOPE = 0.2
# A 4 by 4 ordered dither, so a bank thinned towards its edge lets the ground through in an even pattern that tiles.
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])


def level(a):
    """The palisade picture with its slant taken out, so the bank runs straight."""
    out = np.zeros((a.shape[0] + 12, a.shape[1], 4), np.uint8)
    for x in range(a.shape[1]):
        s = int(round(SLOPE * (57 - x)))
        for y in range(a.shape[0]):
            if 0 <= y - s + 8 < out.shape[0]:
                out[y - s + 8, x] = a[y, x]
    return out


# How a repainted bank settles into its ground over its last rows or columns, outermost first: how far each is brought
# to the ground's middle colour, and how much of it is kept by the dither.
SETTLE = ((1.0, 0.25), (0.8, 0.5), (0.55, 0.75), (0.3, 1.0))


def settle(tile, rows, cols, ease, keep, colour):
    """Brings the given rows and columns `ease` of the way to `colour` and clears all but `keep` of them in the dither's pattern."""
    ys, xs = np.meshgrid(np.arange(tile.shape[0])[rows], np.arange(tile.shape[1])[cols], indexing="ij")
    tile[ys, xs, :3] = (tile[ys, xs, :3] * (1 - ease) + colour * ease).round().astype(np.uint8)
    gone = BAYER[ys % 4, xs % 4] >= keep * 16
    tile[ys[gone], xs[gone], 3] = 0


def wall_tile(a, pal=None):
    # The stakes start every 4 columns from column 6, so a tile cut from column 18 ends on a whole stake.
    x0, w = 18, PERIOD * STAKES
    tile = a[10:44, x0:x0 + w].copy()
    bank = slice(29 - 10, 43 - 10)
    # The last columns of the bank fade into the columns just before the tile's start, so one tile runs into the next.
    for t in range(w - 8, w):
        k = (t - (w - 9)) / 9.0
        before = a[29:43, x0 + t - w].astype(float)
        tile[bank, t] = (tile[bank, t].astype(float) * (1 - k) + before * k).astype(np.uint8)
    if pal:
        # The bank starts just under the stakes' feet and their shadow, and its foot settles into the ground it is painted for.
        tile[18:] = fort_ground.repaint(tile[18:], pal)
        for k, (ease, keep) in enumerate(SETTLE):
            settle(tile, slice(-1 - k, -k or None), slice(None), ease, keep, pal["middle"])
    return tile


def side_tile(a, height=36, step=6, pal=None):
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
    if pal:
        tile = fort_ground.repaint(tile, pal)
        for k, (ease, keep) in enumerate(SETTLE):
            settle(tile, slice(None), slice(k, k + 1), ease, keep, pal["middle"])
            settle(tile, slice(None), slice(w - 1 - k, w - k), ease, keep, pal["middle"])
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
    for ground, province in fort_ground.variants().items():
        pal = fort_ground.palette(province)
        Image.fromarray(wall_tile(a, pal)).save(RAW / f"wall_tile_{ground}.png")
        Image.fromarray(side_tile(a, pal=pal)).save(RAW / f"side_tile_{ground}.png")


if __name__ == "__main__":
    main()
