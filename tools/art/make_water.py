"""Draws game/assets/water.png, the muddy Nile water of Aegyptus's canals, as a seamless 128 px tile with no PixelLab.

The body is a few shades of teal set by smooth noise that wraps at the tile's edges, and the ripples are short soft arcs
in lighter shades, each drawn wrapping round the edges so the tile repeats without a seam.
"""
import math
import random
from pathlib import Path

from PIL import Image

SIZE = 128
OUT = Path(__file__).resolve().parents[2] / "game" / "assets" / "water.png"
# Darkest to lightest body shades, then the two ripple shades.
BODY = [(40, 70, 64), (46, 80, 71), (53, 90, 78), (60, 99, 85)]
RIPPLE = [(74, 112, 97), (98, 136, 114)]


def wrap_noise(rng: random.Random) -> list[list[float]]:
    """Smooth noise in 0..1 made of sine waves with whole numbers of periods across the tile, so it wraps."""
    waves = []
    for _ in range(9):
        fx, fy = rng.randint(-3, 3), rng.randint(1, 3)
        waves.append((fx, fy, rng.random() * math.tau, rng.uniform(0.4, 1.0) / (abs(fx) + fy)))
    total = sum(w[3] for w in waves)
    grid = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            v = sum(a * math.sin(math.tau * (fx * x + fy * y) / SIZE + ph) for fx, fy, ph, a in waves)
            row.append(0.5 + 0.5 * v / total)
        grid.append(row)
    return grid


def main() -> None:
    rng = random.Random(7)
    noise = wrap_noise(rng)
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            # A little ordered dither between shades keeps the body soft without banding.
            v = noise[y][x] * (len(BODY) - 0.01) + ((x + 2 * y) % 4 - 1.5) * 0.05
            px[x, y] = BODY[max(0, min(len(BODY) - 1, int(v)))]
    # Ripples: shallow arcs a few pixels long, the lighter shade only along the crest of the longer ones.
    placed = []
    while len(placed) < 34:
        cx, cy = rng.randrange(SIZE), rng.randrange(SIZE)
        if any(min(abs(cx - a), SIZE - abs(cx - a)) < 16 and min(abs(cy - b), SIZE - abs(cy - b)) < 6 for a, b in placed):
            continue
        placed.append((cx, cy))
        length = rng.randint(6, 13)
        bend = rng.choice([-1, 1])
        for i in range(length):
            t = i / max(1, length - 1)
            dy = round(bend * 1.2 * (4 * t * (1 - t)))
            shade = RIPPLE[1] if length >= 9 and 0.3 < t < 0.7 else RIPPLE[0]
            px[(cx + i) % SIZE, (cy - dy) % SIZE] = shade
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
