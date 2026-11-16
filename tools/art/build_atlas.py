"""Packs every unit animation, prop and pickup into one atlas, so the game draws the whole horde from a single
texture in one batch.

Each animation is cropped to the area its frames use and keeps an anchor at the unit's feet, so units stand on their
position whatever the canvas PixelLab drew them on. A unit whose attack_<direction> folders exist also gets an "attack"
action, anchored on the standing pose its first frame repeats. A prop in SHEETS is several frames drawn side by side,
such as the flame, and is packed as one prop with a frame per drawing.

Usage: python tools/art/build_atlas.py
Writes game/assets/atlas.png, game/assets/atlas.json and the province grounds in game/assets/grounds/.
"""
import json
import shutil
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "tools" / "art" / "raw"
OUT = ROOT / "game" / "assets"
DIRS = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
UNITS = {"commander": "walking", "legionary": "walking", "archer": "walking",
         "barbarian_club": "running", "barbarian_spear": "running", "chieftain": "running",
         "berserker": "running", "war_band_leader": "running", "axe_thrower": "running", "wolf": "running", "war_dog": "running", "war_priest": "walking",
         "gaul_swordsman": "running", "gaul_horseman": "running", "gaul_archer": "running", "boar": "running",
         "champion": "running", "horn_blower": "running", "gaul_king": "running"}
PROPS = {"oak": "props2/oak.png", "fir": "props2/fir.png", "rock": "props2/rock.png", "log": "props2/log.png",
         "stones": "props/stones.png", "coin": "props/coin.png", "pilum": "props2/pilum.png",
         "stake": "props3/stake.png", "caltrops": "props3/caltrops.png", "fire_pot": "props3/fire_pot.png",
         "onager_stone": "props3/onager_stone.png", "chest": "props3/chest.png", "supply_cart": "props3/supply_cart.png",
         "fort_gate": "props3/fort_gate.png", "hut": "props3/hut.png", "eagle_standard": "props3/eagle_standard.png",
         "altar": "props3/altar.png", "stump": "props3/stump.png", "timber": "props3/timber.png",
         "wheat": "props3/wheat.png", "hedge": "props3/hedge.png", "village": "props3/village.png", "roundhouse": "roundhouse/house_a.png",
         "wheat_field": "wheat_field/field_tile.png"}
# Props drawn as several frames side by side on one sheet, played in turn.
SHEETS = {"flame": "props3/flame_sheet_b.png"}
# Props toned down after drawing, as (how much the light parts darken, how much colour is taken out), so the
# scattered stones and felled stumps do not shine like coins on the grass.
TONE = {"stones": (0.4, 0.5), "stump": (0.4, 0.2)}
# The bosses are drawn from their larger remakes; the small originals stay on disk.
FOLDERS = {"berserker": "berserker_big", "war_band_leader": "war_band_leader_big", "war_priest": "war_priest_big",
           "chieftain": "chieftain_big", "champion": "champion_big", "horn_blower": "horn_blower_big", "gaul_king": "gaul_king_big"}
WIDTH = 4096
# GL Compatibility on older GPUs guarantees 4096 px textures, so the atlas never grows past it.
MAX_SIDE = 4096


def crop_set(images, anchor):
    """Crops frames to the union of their drawn pixels and moves the anchor to match."""
    boxes = [im.getbbox() for im in images if im.getbbox()]
    x0, y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
    x1, y1 = max(b[2] for b in boxes), max(b[3] for b in boxes)
    return [im.crop((x0, y0, x1, y1)) for im in images], [anchor[0] - x0, anchor[1] - y0]


def feet(images):
    return max(int(np.nonzero(np.asarray(im)[..., 3].any(1))[0][-1]) for im in images)


def tone(im, darken, grey):
    a = np.asarray(im).astype(float)
    rgb = a[..., :3] * (1 - darken * (a[..., :3] @ [0.299, 0.587, 0.114]) / 255)[..., None]
    rgb = rgb * (1 - grey) + (rgb @ [0.299, 0.587, 0.114])[..., None] * grey
    a[..., :3] = rgb
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def sheet_frames(sheet):
    """Splits a sheet into its separate drawings, left to right, on canvases of one size with the middle of each
    drawing's base at the same point, so a flickering flame stays rooted where it stands."""
    a = np.asarray(sheet)
    n, labels, stats, _ = cv2.connectedComponentsWithStats((a[..., 3] > 0).astype(np.uint8), 8)
    parts = sorted((stats[i] for i in range(1, n) if stats[i][4] >= 40), key=lambda st: st[0])
    bases = []
    for x, y, w, h, _ in parts:
        rows = np.nonzero(a[y + h - 3:y + h, x:x + w, 3] > 0)[1]
        bases.append(x + int(round(rows.mean())))
    half = max(max(b - x, x + w - b) for (x, _, w, _, _), b in zip(parts, bases)) + 1
    frames = []
    for (x, y, w, h, _), b in zip(parts, bases):
        im = Image.new("RGBA", (2 * half, sheet.height), (0, 0, 0, 0))
        im.alpha_composite(sheet.crop((b - half, 0, b + half, sheet.height)))
        frames.append(im)
    return frames


def torso_x(images, anchor, height):
    """Mean x of the body from the hips to the head, against the anchor, over the frames."""
    xs = []
    for im in images:
        drawn = np.asarray(im)[..., 3] > 0
        top = max(0, int(anchor[1] - 0.97 * height))
        bottom = max(top + 1, int(anchor[1] - 0.45 * height))
        cols = np.nonzero(drawn[top:bottom])[1]
        if len(cols):
            xs.append(cols.mean() - anchor[0])
    return float(np.mean(xs)) if xs else 0.0


def main():
    sets = []
    for unit, action in UNITS.items():
        src = RAW / FOLDERS.get(unit, unit)
        attacks = all((src / f"attack_{d}").is_dir() for d in DIRS)
        for d in DIRS:
            folder = src / f"t_{action}_{d}"
            frames = [Image.open(p).convert("RGBA") for p in sorted(folder.glob("frame_*.png"))]
            if not frames:
                raise SystemExit(f"missing {folder}")
            # The first frame is the standing pose itself, which the loop already passes through.
            loop = frames[1:] if len(frames) > 8 else frames
            still = Image.open(src / f"{d}.png").convert("RGBA")
            idle, idle_anchor = crop_set([still], (still.width / 2, feet([still])))
            images, anchor = crop_set(loop, (loop[0].width / 2, feet(loop)))
            # The run leans the body ahead of the feet; taking half the lean back keeps a unit from hopping as it starts and stops.
            lean = torso_x(images, anchor, idle_anchor[1]) - torso_x(idle, idle_anchor, idle_anchor[1])
            if abs(lean) >= 3:
                anchor[0] += round(lean / 2)
            sets.append((("units", unit, "move", d), images, anchor))
            sets.append((("units", unit, "idle", d), idle, idle_anchor))
            if attacks:
                names = sorted(p.name for p in (src / f"attack_{d}").iterdir())
                if names != [f"frame_{i:02d}.png" for i in range(9)]:
                    raise SystemExit(f"{src / f'attack_{d}'} must hold exactly frame_00 to frame_08")
                frames = [Image.open(src / f"attack_{d}" / n).convert("RGBA") for n in names]
                # The strike starts from the standing pose, so the anchor comes from it and the pose itself is left out.
                images, anchor = crop_set(frames[1:], (frames[0].width / 2, feet(frames[:1])))
                sets.append((("units", unit, "attack", d), images, anchor))
    for name, path in PROPS.items():
        im = Image.open(RAW / path).convert("RGBA")
        if name in TONE:
            im = tone(im, *TONE[name])
        images, anchor = crop_set([im], (im.width / 2, feet([im])))
        sets.append((("props", name), images, anchor))
    for name, path in SHEETS.items():
        frames = sheet_frames(Image.open(RAW / path).convert("RGBA"))
        images, anchor = crop_set(frames, (frames[0].width / 2, feet(frames)))
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
    if y + shelf + 1 > MAX_SIDE:
        raise SystemExit(f"atlas would be {WIDTH}x{y + shelf + 1}, over {MAX_SIDE}")
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
    shutil.copy(RAW / "ground" / "gaul_tile.png", OUT / "grounds" / "gaul.png")
    print(f"atlas {atlas.size[0]}x{atlas.size[1]}, {len(flat)} sprites")


if __name__ == "__main__":
    main()
