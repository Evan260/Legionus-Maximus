"""Makes the app icon: the commander's crested helmet close up on a red tile with a gold rim, bold enough to read at taskbar size.

Usage: python tools/art/make_icon.py
Writes game/icon.png (256 px) and game/icon.ico (16 to 256 px).
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "art_test" / "raw" / "commander" / "south.png"
RED = (150, 28, 24, 255)
DARK = (60, 12, 10, 255)
GOLD = (232, 176, 64, 255)
GOLD_LIGHT = (255, 226, 150, 255)


def tile(size):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = max(2, size // 6)
    d.rounded_rectangle((0, 0, size - 1, size - 1), r, fill=DARK)
    rim = max(1, size // 16)
    d.rounded_rectangle((rim, rim, size - 1 - rim, size - 1 - rim), max(1, r - rim), fill=GOLD)
    inner = rim * 2
    d.rounded_rectangle((inner, inner, size - 1 - inner, size - 1 - inner), max(1, r - inner), fill=RED)
    if size >= 32:
        d.line((inner + 1, inner + 1, size - inner - 2, inner + 1), fill=GOLD_LIGHT, width=max(1, size // 64))
    return im


def helmet():
    src = Image.open(SRC).convert("RGBA")
    box = src.getbbox()
    # The head and crest are the top part of the figure; the crop is square so it scales evenly.
    h = (box[3] - box[1]) * 0.42
    cx = (box[0] + box[2]) / 2
    side = int(round(h))
    left = int(round(cx - side / 2))
    return src.crop((left, box[1], left + side, box[1] + side))


def main():
    head = helmet()
    big = tile(256)
    inner = 256 - 2 * 28
    scale = inner // head.width
    art = head.resize((head.width * scale, head.height * scale), Image.NEAREST)
    shadow = Image.new("RGBA", art.size, (0, 0, 0, 0))
    shadow.paste((20, 6, 4, 200), mask=art.split()[3])
    x = (256 - art.width) // 2
    y = (256 - art.height) // 2 + 6
    big.alpha_composite(shadow, (x + 6, y + 6))
    big.alpha_composite(art, (x, y))
    big.save(ROOT / "game" / "icon.png")
    sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = []
    for s in sizes:
        f = tile(s)
        a = head.resize((round(s * 0.78), round(s * 0.78)), Image.NEAREST if s >= 64 else Image.LANCZOS)
        f.alpha_composite(a, ((s - a.width) // 2, (s - a.height) // 2 + max(0, s // 32)))
        frames.append(f)
    frames[-1].save(ROOT / "game" / "icon.ico", sizes=[(s, s) for s in sizes], append_images=frames[:-1])
    print("icon written")


if __name__ == "__main__":
    main()
