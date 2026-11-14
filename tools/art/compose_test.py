"""Lays the art test's sprites out as one game screen: the legion marching east through a Germanian clearing while
barbarians close in from every side. Writes a still and a short looping clip.

Usage: python tools/art/compose_test.py
"""
import math
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "art_test" / "raw"
OUT = ROOT / "art_test"
FONT = Path(r"C:\Users\evand\Desktop\Farmus Maximus\game\assets\fonts\Silkscreen-Regular.ttf")
W, H, SCALE = 640, 360, 3
FRAMES = 48
MARCH = 0.45


def load_anim(folder):
    frames = [Image.open(p).convert("RGBA") for p in sorted((RAW / folder).glob("frame_*.png"))]
    # Every frame is anchored at the lowest opaque row of the whole cycle, so feet stay on the ground.
    feet = max(np.nonzero(np.asarray(f)[..., 3].any(1))[0][-1] for f in frames)
    return frames, feet


def sprite(path):
    im = Image.open(RAW / path).convert("RGBA")
    return [im], np.nonzero(np.asarray(im)[..., 3].any(1))[0][-1]


ANIMS = {
    "commander": load_anim("commander/t_walk_east"),
    "legionary": load_anim("legionary/t_walking_east"),
    "archer": load_anim("archer/t_walking_east"),
}
for kind in ("barbarian_club", "barbarian_spear"):
    for d in ("east", "north-west", "south-west"):
        ANIMS[f"{kind}:{d}"] = load_anim(f"{kind}/t_running_{d}")
ANIMS["barbarian_club:west"] = load_anim("barbarian_club/t_run_west")
ANIMS["barbarian_spear:west"] = load_anim("barbarian_spear/t_running_west")
PROPS = {n: sprite(p) for n, p in {
    "oak": "props2/oak.png", "fir": "props2/fir.png", "rock": "props2/rock.png", "log": "props2/log.png",
    "bush": "props/bush.png", "stones": "props/stones.png"}.items()}
COIN = Image.open(RAW / "props/coin.png").convert("RGBA")
PILUM = Image.open(RAW / "props2/pilum.png").convert("RGBA")
GROUND = Image.open(RAW / "ground/grass_tile5.png").convert("RGB")

rng = np.random.default_rng(11)
CX, CY = W * 0.5, H * 0.56

# The legion: the commander in the middle, legionaries in two ranks before him, archers behind.
legion = [("commander", 0, 0)]
for row, dx in ((0, 44), (1, 24)):
    for k in range(-2, 3):
        if row == 1 and k in (-2, 2):
            continue
        legion.append(("legionary", dx, k * 22 + (11 if row else 0)))
for k in (-1, 0, 1):
    legion.append(("archer", -30, k * 22))
for k in (-2, 2):
    legion.append(("legionary", 4, k * 22))

barbarians = []
for i in range(46):
    ang = rng.uniform(0, 2 * math.pi)
    dist = rng.uniform(80, 300)
    x, y = CX + math.cos(ang) * dist * 1.25, CY + math.sin(ang) * dist * 0.75
    kind = "barbarian_club" if rng.random() < 0.55 else "barbarian_spear"
    barbarians.append([x, y, kind, int(rng.integers(0, 8)), rng.uniform(0.7, 1.0)])

props = []
for i in range(26):
    name = rng.choice(["oak", "fir", "rock", "log", "bush", "stones", "bush", "stones", "fir"])
    x, y = rng.uniform(-60, W + 400), rng.uniform(-10, H + 30)
    if abs(y - CY) < 50 and -60 < x - CX < 400:
        continue
    props.append((name, x, y))
coins = [(rng.uniform(0, W + 300), rng.uniform(20, H - 10)) for _ in range(34)]


def direction(dx, dy):
    if dx >= 0:
        return "east"
    if abs(dy) < abs(dx) * 0.4:
        return "west"
    return "south-west" if dy > 0 else "north-west"


def shadow(canvas, x, y, w):
    a = np.asarray(canvas).copy()
    yy, xx = np.mgrid[0:H, 0:W]
    m = ((xx - x) / (w / 2)) ** 2 + ((yy - y) / (w / 5)) ** 2 <= 1
    a[m, :3] = (a[m, :3] * 0.62).astype(np.uint8)
    return Image.fromarray(a)


def hud(img, t):
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(str(FONT), 8)
    d.rectangle((8, 7, W - 9, 13), fill=(40, 26, 20))
    d.rectangle((9, 8, 9 + int((W - 19) * 0.62), 12), fill=(232, 176, 64))
    d.line((9, 8, 9 + int((W - 19) * 0.62), 8), fill=(255, 226, 150))
    for text, x, anchor in (("LEVEL 9", 10, "la"), ("08:42", W // 2, "ma"), ("LEGION 17", W - 10, "ra")):
        d.text((x + 1, 18), text, font=font, fill=(40, 26, 20), anchor=anchor)
        d.text((x, 17), text, font=font, fill=(255, 240, 200), anchor=anchor)
    d.text((W - 9, 30), "X 214", font=font, fill=(40, 26, 20), anchor="ra")
    d.text((W - 10, 29), "X 214", font=font, fill=(255, 240, 200), anchor="ra")
    img.alpha_composite(COIN, (W - 50, 26))


def frame(t):
    cam = t * MARCH
    ground = Image.new("RGB", (W, H))
    ox = int(cam) % GROUND.width
    for gx in range(-1, W // GROUND.width + 2):
        for gy in range(0, H // GROUND.height + 1):
            ground.paste(GROUND, (gx * GROUND.width - ox, gy * GROUND.height))
    img = ground.convert("RGBA")
    draws = []
    for x, y in coins:
        draws.append((y, "coin", x - cam, y))
    for name, x, y in props:
        draws.append((y, "prop:" + name, x - cam, y))
    for kind, dx, dy in legion:
        draws.append((CY + dy, kind, CX + dx, CY + dy, (t + int(dx + dy)) % 8))
    for b in barbarians:
        bx, by, kind, phase, speed = b
        tx, ty = bx - (CX + cam), by - CY
        dist = math.hypot(tx, ty)
        step = speed * 0.9 if dist > 88 else 0.0
        b[0] -= tx / dist * step - MARCH * (1 if step == 0 else 0)
        b[1] -= ty / dist * step
        draws.append((b[1], f"{kind}:{direction(-tx, -ty)}", b[0] - cam, b[1], (t + phase) % 8))
    for y, what, x, yy, *rest in sorted(draws, key=lambda d: d[0]):
        if what == "coin":
            img.alpha_composite(COIN, (int(x) - 8, int(yy) - 12))
            continue
        frames, feet = PROPS[what[5:]] if what.startswith("prop:") else ANIMS[what]
        im = frames[rest[0] % len(frames)] if rest else frames[0]
        w = 20 if not what.startswith("prop:") else int(im.width * 0.55)
        img = shadow(img, x, yy, w)
        img.alpha_composite(im, (int(x - im.width / 2), int(yy - feet)))
    # Pila fly out from the archers towards the barbarians ahead.
    for k in range(3):
        p = (t * 4 + k * 70) % 210
        img.alpha_composite(PILUM, (int(CX + 10 + p), int(CY - 40 - p * 0.35 + k * 30)))
    hud(img, t)
    return img.convert("RGB")


def main():
    frames = [frame(t) for t in range(FRAMES)]
    frames[30].resize((W * SCALE, H * SCALE), Image.NEAREST).save(OUT / "art_test_screen.png")
    tmp = OUT / "frames"
    tmp.mkdir(exist_ok=True)
    for i, f in enumerate(frames):
        f.resize((W * SCALE, H * SCALE), Image.NEAREST).save(tmp / f"f_{i:03d}.png")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "12", "-stream_loop", "2", "-i", str(tmp / "f_%03d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", str(OUT / "art_test_clip.mp4")], check=True)
    for p in tmp.glob("*.png"):
        p.unlink()
    tmp.rmdir()
    print("wrote", OUT / "art_test_screen.png", "and", OUT / "art_test_clip.mp4")


if __name__ == "__main__":
    main()
