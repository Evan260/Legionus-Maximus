"""Packs every unit animation, prop and pickup into one atlas, so the game draws the whole horde from a single
texture in one batch.

Each animation is cropped to the area its frames use and keeps an anchor at the unit's feet, so units stand on their
position whatever the canvas PixelLab drew them on.

Usage: python tools/art/build_atlas.py
Writes game/assets/atlas.png, game/assets/atlas.json and game/assets/grounds/germania.png.
"""
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "art_test" / "raw"
OUT = ROOT / "game" / "assets"
DIRS = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
UNITS = {"commander": "walking", "legionary": "walking", "archer": "walking",
         "barbarian_club": "running", "barbarian_spear": "running", "chieftain": "running",
         "berserker": "running", "war_band_leader": "running", "axe_thrower": "running", "wolf": "running", "war_dog": "running", "war_priest": "walking"}
PROPS = {"oak": "props2/oak.png", "fir": "props2/fir.png", "rock": "props2/rock.png", "log": "props2/log.png",
         "bush": "props/bush.png", "stones": "props/stones.png", "coin": "props/coin.png", "pilum": "props2/pilum.png",
         "stake": "props3/stake.png", "caltrops": "props3/caltrops.png", "fire_pot": "props3/fire_pot.png",
         "onager_stone": "props3/onager_stone.png", "chest": "props3/chest.png", "supply_cart": "props3/supply_cart.png"}
WIDTH = 2048


def crop_set(images, anchor):
    """Crops frames to the union of their drawn pixels and moves the anchor to match."""
    boxes = [im.getbbox() for im in images if im.getbbox()]
    x0, y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
    x1, y1 = max(b[2] for b in boxes), max(b[3] for b in boxes)
    return [im.crop((x0, y0, x1, y1)) for im in images], [anchor[0] - x0, anchor[1] - y0]


def feet(images):
    return max(int(np.nonzero(np.asarray(im)[..., 3].any(1))[0][-1]) for im in images)


def main():
    sets = []
    for unit, action in UNITS.items():
        for d in DIRS:
            folder = RAW / unit / f"t_{action}_{d}"
            frames = [Image.open(p).convert("RGBA") for p in sorted(folder.glob("frame_*.png"))]
            if not frames:
                raise SystemExit(f"missing {folder}")
            # The first frame is the standing pose itself, which the loop already passes through.
            loop = frames[1:] if len(frames) > 8 else frames
            images, anchor = crop_set(loop, (loop[0].width / 2, feet(loop)))
            sets.append((("units", unit, "move", d), images, anchor))
            still = Image.open(RAW / unit / f"{d}.png").convert("RGBA")
            images, anchor = crop_set([still], (still.width / 2, feet([still])))
            sets.append((("units", unit, "idle", d), images, anchor))
    for name, path in PROPS.items():
        im = Image.open(RAW / path).convert("RGBA")
        images, anchor = crop_set([im], (im.width / 2, feet([im])))
        sets.append((("props", name), images, anchor))

    # Shelf packing, tallest first, with a pixel of space so filtering never bleeds between sprites.
    flat = [(key, i, im) for key, images, _ in sets for i, im in enumerate(images)]
    flat.sort(key=lambda f: -f[2].height)
    x = y = shelf = 0
    places = {}
    for key, i, im in flat:
        if x + im.width + 1 > WIDTH:
            x, y, shelf = 0, y + shelf + 1, 0
        places[(key, i)] = (x, y)
        x += im.width + 1
        shelf = max(shelf, im.height)
    atlas = Image.new("RGBA", (WIDTH, y + shelf + 1), (0, 0, 0, 0))
    meta = {"units": {}, "props": {}}
    for key, images, anchor in sets:
        frames = []
        for i, im in enumerate(images):
            px, py = places[(key, i)]
            atlas.alpha_composite(im, (px, py))
            frames.append([px, py, im.width, im.height])
        entry = {"frames": frames, "anchor": anchor}
        if key[0] == "units":
            meta["units"].setdefault(key[1], {}).setdefault(key[2], {})[key[3]] = entry
        else:
            meta["props"][key[1]] = entry
    OUT.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT / "atlas.png")
    (OUT / "atlas.json").write_text(json.dumps(meta))
    (OUT / "grounds").mkdir(exist_ok=True)
    shutil.copy(RAW / "ground" / "grass_tile_b.png", OUT / "grounds" / "germania.png")
    print(f"atlas {atlas.size[0]}x{atlas.size[1]}, {len(flat)} sprites")


if __name__ == "__main__":
    main()
