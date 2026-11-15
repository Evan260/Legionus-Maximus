"""Turns the Pro Flash cliff strip in tools/art/raw/ravine/ into the seamless ravine lip the game draws along each gorge.

The strip's two ends are blended with an ordered dither over BLEND columns so it repeats without a seam, and the empty
rows above the rocks are cut off. Writes game/assets/ravine_edge.png.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools/art/raw/ravine/edge_12.png"
OUT = ROOT / "game/assets/ravine_edge.png"
BLEND = 32
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def main():
    im = Image.open(SOURCE).convert("RGBA")
    w, h = im.size
    first = next(y for y in range(h) if any(im.getpixel((x, y))[3] > 128 for x in range(w)))
    im = im.crop((0, first, w, h))
    h = im.height
    tile = w - BLEND
    out = Image.new("RGBA", (tile, h))
    for y in range(h):
        for x in range(tile):
            if x < BLEND:
                # The start of the tile fades from the strip's far end into its own start, so the right edge meets the left.
                t = (x + 0.5) / BLEND
                own = BAYER[y % 4][x % 4] / 16.0 < t
                out.putpixel((x, y), im.getpixel((x, y)) if own else im.getpixel((tile + x, y)))
            else:
                out.putpixel((x, y), im.getpixel((x, y)))
    out.save(OUT)
    print("saved", OUT, out.size)


if __name__ == "__main__":
    main()
