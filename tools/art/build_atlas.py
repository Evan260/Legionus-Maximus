"""Packs every unit animation, prop and pickup into one atlas, so the game draws the whole horde from a single
texture in one batch.

Each animation is cropped to the area its frames use and keeps an anchor at the unit's feet, so units stand on their
position whatever the canvas PixelLab drew them on. A unit whose attack_<direction> folders exist also gets an "attack"
action, anchored on the standing pose its first frame repeats. A prop in SHEETS is several frames drawn side by side,
such as the flame, and is packed as one prop with a frame per drawing.

Soldiers' armour and red cloth are marked in the alpha channel (LIVERY) so the game can recolour them as the legion is
upgraded; `--livery-only` marks the existing atlas without rebuilding it.

Usage: python tools/art/build_atlas.py [--livery-only]
Writes game/assets/atlas.png, game/assets/atlas.json, the wheat tile and the province grounds in game/assets/grounds/.
"""
import json
import shutil
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

import fort_ground

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "tools" / "art" / "raw"
OUT = ROOT / "game" / "assets"
DIRS = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
UNITS = {"commander": "walking", "legionary": "walking", "archer": "walking",
         "cavalry": "running", "standard_bearer": "running", "medicus": "running",
         "ballista": "running", "centurion": "running",
         "barbarian_club": "running", "barbarian_spear": "running", "chieftain": "running",
         "berserker": "running", "war_band_leader": "running", "axe_thrower": "running", "wolf": "running", "war_dog": "running", "war_priest": "walking",
         "gaul_swordsman": "running", "gaul_horseman": "running", "gaul_archer": "running", "boar": "running",
         "champion": "running", "horn_blower": "running", "gaul_king": "running",
         "falx_warrior": "running", "dacian_archer": "running", "wolf_standard_bearer": "running", "mountain_bear": "running",
         "falx_band": "running", "priest": "running", "dacian_king": "running",
         "horse_archer": "running", "cataphract": "running", "camel_rider": "running", "parthian_slinger": "running",
         "cataphract_charge": "running", "war_elephant": "running", "shah": "running",
         "painted_warrior": "running", "briton_slinger": "running", "druid_acolyte": "running", "chariot": "running",
         "chariot_charge": "running", "druid": "running", "warrior_queen": "running",
         "celtiberian_warrior": "running", "balearic_slinger": "running", "caetratus": "running", "war_hound": "running",
         "celtiberian_chief": "running", "lusitanian_raider": "running", "viriathus": "running",
         "egyptian_spearman": "running", "nubian_archer": "running", "khopesh_raider": "running", "crocodile": "running",
         "sobek_priest": "running", "camel_captain": "running", "achillas": "running",
         "sarmatian_lancer": "running", "steppe_archer": "running", "lasso_rider": "running", "steppe_wolf": "running",
         "draco_rider": "running", "war_wagon": "running", "rasparaganus": "running"}
PROPS = {"oak": "props2/oak.png", "fir": "props2/fir.png", "rock": "props2/rock.png", "log": "props2/log.png",
         "stones": "props/stones.png", "coin": "props/coin.png", "pilum": "props2/pilum.png",
         "stake": "props3/stake.png", "caltrops": "props3/caltrops.png", "fire_pot": "props3/fire_pot.png",
         "onager_stone": "props3/onager_stone.png", "chest": "props3/chest.png", "supply_cart": "props3/supply_cart.png",
         "fort_gate": "props3/fort_gate.png", "hut": "props3/hut.png", "hut_charred": "props3/hut_charred.png", "hut_ruin": "props3/hut_ruin.png",
         "eagle_standard": "props3/eagle_standard.png",
         "altar": "props3/altar.png", "stump": "props3/stump.png", "timber": "props3/timber.png",
         "wheat": "props3/wheat.png", "hedge": "props3/hedge.png", "hedge_end_left": "props6/hedge_end_left.png",
         "hedge_end_right": "props6/hedge_end_right.png", "roundhouse": "roundhouse/house_a.png",
         "wheat_field": "wheat_field/field_tile.png", "pine": "props3/pine.png", "frozen_stream": "frozen_stream/ice_tile.png",
         "dune": "props4/dune.png", "palm": "props4/palm.png", "ruined_wall": "props4/ruined_wall.png", "well": "props4/well.png",
         "fort_wall": "castra/wall_tile.png", "fort_side": "castra/side_tile.png", "watchtower": "castra/tower.png", "tent": "castra/tent.png",
         "command_tent": "castra/command_tent.png",
         "heather": "props5/heather.png", "bog": "props5/bog.png", "stone_circle": "props5/stone_circle.png",
         "olive": "props7/olive.png", "stone_wall": "props7/stone_wall.png", "dry_grass": "props7/dry_grass.png",
         "date_palm": "props8/date_palm.png", "papyrus": "props8/papyrus.png", "fallen_column": "props8/fallen_column.png",
         "obelisk": "props8/obelisk.png",
         "feather_grass": "props9/feather_grass.png", "kurgan": "props9/kurgan_b.png", "wagon": "props9/wagon.png", "birch": "props9/birch.png"}
# Props drawn as several frames side by side on one sheet, played in turn.
SHEETS = {"flame": "props3/flame_sheet_b.png"}
# Smaller copies of a sheet's frames, smoothed down from the drawing, as name: (sheet prop, scale), so a fire grows and dies
# down by whole pictures instead of being stretched.
SMALLER = {"flame_half": ("flame", 0.5), "flame_three_quarters": ("flame", 0.75)}
# Pictures of several standing stones on one patch of grass, split as name: picture into the grass, drawn flat, and each
# stone, sorted at its own foot, so a man can stand between the stones.
SPLIT = {"stone_circle_parts": "stone_circle"}
# Props toned down after drawing, as (how much the light parts darken, how much colour is taken out), so the
# scattered stones and felled stumps do not shine like coins on the grass.
TONE = {"stones": (0.4, 0.5), "stump": (0.4, 0.2)}
# Props whose black outline is redrawn in a darker shade of the colour just inside it, so the rock sits in the ground.
SOFT_EDGE = {"rock"}
# Props whose leaves are brought to another prop's greens, as prop: (the prop whose greens set the change, the prop to match),
# so the Gaulish hedges wear the oaks' green and the fort's gate, towers and command tent the grass of its wall bank.
MATCH_GREEN = {"hedge": ("hedge", "oak"), "hedge_end_left": ("hedge", "oak"), "hedge_end_right": ("hedge", "oak"),
               "fort_gate": ("fort_gate", "fort_wall"), "watchtower": ("watchtower", "fort_wall"), "command_tent": ("command_tent", "fort_wall")}
# The bosses and the chariot are drawn from their larger remakes; the small originals stay on disk.
FOLDERS = {"berserker": "berserker_big", "war_band_leader": "war_band_leader_big", "war_priest": "war_priest_big",
           "chieftain": "chieftain_big", "champion": "champion_big", "horn_blower": "horn_blower_big", "gaul_king": "gaul_king_big",
           "falx_band": "falx_band_big", "priest": "priest_big", "dacian_king": "dacian_king_big",
           "cataphract_charge": "cataphract_charge_big", "war_elephant": "war_elephant_136", "shah": "shah_big",
           "druid": "druid_big", "chariot_charge": "chariot_charge_96", "chariot": "chariot_72", "warrior_queen": "warrior_queen_big",
           "celtiberian_chief": "celtiberian_chief_big", "lusitanian_raider": "lusitanian_raider_big", "viriathus": "viriathus_big",
           "crocodile": "crocodile_64", "sobek_priest": "sobek_priest_big", "camel_captain": "camel_captain_big", "achillas": "achillas_big",
           "draco_rider": "draco_rider_big", "war_wagon": "war_wagon_big", "rasparaganus": "rasparaganus_big"}
# Animations drawn from their mirror image, as unit: {folder: the folder it mirrors}, where PixelLab drew a unit so far off centre that the canvas edge cuts it.
MIRROR = {"mountain_bear": {"t_running_east": "t_running_west", "t_running_south-east": "t_running_south-west",
                            "attack_east": "attack_west", "attack_south-east": "attack_south-west"},
          "war_hound": {"t_running_east": "t_running_west", "attack_east": "attack_west"},
          "steppe_wolf": {"t_running_east": "t_running_west", "attack_east": "attack_west"},
          "caetratus": {"attack_east": "attack_west", "attack_north-east": "attack_north-west"},
          "balearic_slinger": {"attack_south-east": "attack_south-west"},
          "nubian_archer": {"attack_east": "attack_west", "attack_south-west": "attack_south-east", "attack_north-west": "attack_north-east"}}
# The atlas stays one page so the horde draws in one batch, and grows wide before tall.
WIDTH = 8192
MAX_SIDE = 8192


# Soldiers whose armour and cloth game/scripts/livery.gd recolours, with the parts each one has.
LIVERY = {"legionary": "armour cloth", "archer": "armour cloth", "cavalry": "armour cloth", "standard_bearer": "armour cloth",
          "medicus": "cloth", "ballista": "armour cloth", "centurion": "armour cloth"}
# Red-brown wood of the ballista's frame that falls inside the cloth colours.
NOT_CLOTH = {"ballista": [(108, 38, 30), (95, 29, 34)]}
# Alpha values that mark a pixel as armour or cloth; livery.gd reads the same values and draws them opaque.
ARMOUR_ALPHA = 254
CLOTH_ALPHA = 253


def livery_parts(rgb):
    """Which pixels of an RGB array are armour metal (bluish grey) and which are red cloth."""
    c = rgb.astype(np.float32) / 255.0
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    hi, lo = c.max(-1), c.min(-1)
    sat = np.where(hi > 0, (hi - lo) / np.maximum(hi, 1e-6), 0)
    armour = (sat < 0.5) & (b >= r + 0.02) & (b >= g - 0.03) & (hi > 0.24)
    hue = 60.0 * (g - b) / np.maximum(hi - lo, 1e-6)
    cloth = (r == hi) & (r > 0.33) & (sat > 0.6) & (hue > -40) & (hue < 12)
    return armour, cloth


def tag_livery(atlas, meta):
    """Marks the armour and cloth pixels of every LIVERY soldier's frames in the atlas's alpha channel."""
    px = np.array(atlas)
    for unit, parts in LIVERY.items():
        for action in meta["units"][unit].values():
            for anim in action.values():
                for x, y, w, h in anim["frames"]:
                    cell = px[y:y + h, x:x + w]
                    alpha = cell[..., 3]
                    alpha[(alpha >= CLOTH_ALPHA) & (alpha < 255)] = 255
                    armour, cloth = livery_parts(cell[..., :3])
                    for colour in NOT_CLOTH.get(unit, []):
                        cloth &= ~np.all(cell[..., :3] == colour, -1)
                    solid = alpha == 255
                    if "armour" in parts:
                        alpha[solid & armour] = ARMOUR_ALPHA
                    if "cloth" in parts:
                        alpha[solid & cloth & ~armour] = CLOTH_ALPHA
    return Image.fromarray(px, "RGBA")


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


def soft_edge(im, shade=0.6):
    a = np.asarray(im).astype(float)
    solid = a[..., 3] > 0
    rim = solid & ~cv2.erode(solid.astype(np.uint8), np.ones((5, 5), np.uint8), borderValue=0).astype(bool)
    dark = rim & (a[..., :3].sum(-1) < 140)
    h, w = solid.shape
    # Each pass shades the dark pixels touching ones already coloured, so a thick outline fills from the inside out.
    edge = dark.copy()
    while dark.any():
        out, done = a.copy(), dark.copy()
        for y, x in zip(*np.nonzero(dark)):
            near = [a[y + dy, x + dx, :3] for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                    if 0 <= y + dy < h and 0 <= x + dx < w and solid[y + dy, x + dx] and not dark[y + dy, x + dx]]
            if near:
                out[y, x, :3] = np.mean(near, 0)
                done[y, x] = False
        if (done == dark).all():
            break
        a, dark = out, done
    a[edge & ~dark, :3] *= shade
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def _greens(im):
    """The leaf pixels of a drawing, as a mask, and its colours in HSV with hue from 0 to 180."""
    a = np.asarray(im.convert("RGBA"))
    hsv = cv2.cvtColor(np.ascontiguousarray(a[..., :3]), cv2.COLOR_RGB2HSV).astype(float)
    mask = (a[..., 3] > 0) & (hsv[..., 0] > 20) & (hsv[..., 0] < 90) & (hsv[..., 1] > 40)
    return mask, hsv


def green_match(source, target):
    """How to move the leaves of `source` onto those of `target`: a hue shift, a saturation scale, and the 10th and 90th
    brightness percentiles of each, so the light and shade spread the same way."""
    sm, sh = _greens(source)
    tm, th = _greens(target)
    return {"hue": float(th[..., 0][tm].mean() - sh[..., 0][sm].mean()),
            "sat": float(th[..., 1][tm].mean() / sh[..., 1][sm].mean()),
            "from": [float(np.percentile(sh[..., 2][sm], p)) for p in (10, 90)],
            "to": [float(np.percentile(th[..., 2][tm], p)) for p in (10, 90)]}


def recolour(im, m):
    """A drawing with its leaves moved by a green_match, its outline and anything not green left as drawn."""
    a = np.asarray(im.convert("RGBA")).copy()
    mask, hsv = _greens(im)
    f1 = m["from"][1]
    t1 = m["to"][1]
    hsv[..., 0] = np.where(mask, np.clip(hsv[..., 0] + m["hue"], 0, 179), hsv[..., 0])
    hsv[..., 1] = np.where(mask, np.clip(hsv[..., 1] * m["sat"], 0, 255), hsv[..., 1])
    # Only the light end is matched; the deep shade between the leaves stays as dark as drawn.
    hsv[..., 2] = np.where(mask, np.clip(hsv[..., 2] * t1 / max(1.0, f1), 0, 255), hsv[..., 2])
    rgb = cv2.cvtColor(hsv.round().astype(np.uint8), cv2.COLOR_HSV2RGB)
    a[..., :3] = np.where(mask[..., None], rgb, a[..., :3])
    return Image.fromarray(a)


def prop_image(name):
    im = Image.open(RAW / PROPS[name]).convert("RGBA")
    if name in TONE:
        im = tone(im, *TONE[name])
    if name in SOFT_EDGE:
        im = soft_edge(im)
    if name in MATCH_GREEN:
        source, target = MATCH_GREEN[name]
        im = recolour(im, green_match(Image.open(RAW / PROPS[source]).convert("RGBA"), Image.open(RAW / PROPS[target]).convert("RGBA")))
    return im


def fort_pictures(ground, province):
    """The fort's pictures that stand on ground, named as props with the ground after them (fort_gate_sand), their grass
    and bare earth in the province's ground; the wall strips come ready painted from make_castra_walls.py."""
    pal = fort_ground.palette(province)
    out = {}
    for name in fort_ground.PIECES:
        if name in ("fort_wall", "fort_side"):
            im = Image.open(RAW / PROPS[name].replace(".png", f"_{ground}.png")).convert("RGBA")
        else:
            a = np.asarray(prop_image(name)).copy()
            im = Image.fromarray(fort_ground.repaint(a, pal, fort_ground.ground_mask(a, name)))
        out[f"{name}_{ground}"] = im
    return out


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


def smaller(frames, k):
    """Frames scaled by k with their colours averaged, on canvases of one size so they stay rooted where they stand."""
    size = (max(1, round(frames[0].width * k)), max(1, round(frames[0].height * k)))
    return [im.convert("RGBa").resize(size, Image.Resampling.BOX).convert("RGBA") for im in frames]


def rimmed_coin(coin):
    """The coin as the game draws it: gold, inside a dark rim a pixel wide made of its own shape."""
    a = np.asarray(coin).astype(float)
    rim = (a * [0.18, 0.1, 0.04, 0.85]).clip(0, 255).astype(np.uint8)
    gold = (a * [1.35, 1.12, 0.5, 1.0]).clip(0, 255).astype(np.uint8)
    out = Image.new("RGBA", (coin.width + 2, coin.height + 2), (0, 0, 0, 0))
    for dx, dy in ((0, 1), (2, 1), (1, 0), (1, 2)):
        out.alpha_composite(Image.fromarray(rim), (dx, dy))
    out.alpha_composite(Image.fromarray(gold), (1, 1))
    return out


def split_stones(im):
    """A picture of standing stones on grass as [the grass, each stone], all on its canvas, and each part's lowest row.
    Each stone grows from its light middle, which its dark outline keeps apart from the next, over every pixel that is
    not grass and lies within a few pixels of that middle."""
    a = np.asarray(im)
    drawn = a[..., 3] > 0
    hsv = cv2.cvtColor(np.ascontiguousarray(a[..., :3]), cv2.COLOR_RGB2HSV).astype(int)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    grass = drawn & (v >= 50) & (((h >= 22) & (h <= 50) & (s >= 105)) | ((h >= 30) & (h <= 50) & (s >= 40)))
    stony = drawn & ~grass
    middle = cv2.erode((drawn & (s < 95) & (v >= 45)).astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_CROSS, (3, 3)))
    n, labels, stats, _ = cv2.connectedComponentsWithStats(middle, 4)
    seeds = [i for i in range(1, n) if stats[i][4] >= 15]
    reach = np.zeros(drawn.shape, int)
    owner = np.zeros(drawn.shape, int)
    for k, i in enumerate(seeds):
        hull = np.zeros(drawn.shape, np.uint8)
        cv2.fillConvexPoly(hull, cv2.convexHull(np.argwhere(labels == i)[:, ::-1].astype(np.int32)), 1)
        reach[cv2.dilate(hull, np.ones((15, 15), np.uint8)).astype(bool)] |= 1 << k
        owner[hull.astype(bool) & stony] = k + 1
    while True:
        grown = owner.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            near = np.roll(owner, (dy, dx), (0, 1))
            within = (near > 0) & ((reach >> np.maximum(near - 1, 0)) & 1 == 1)
            take = stony & (grown == 0) & within
            grown[take] = near[take]
        if (grown == owner).all():
            break
        owner = grown
    parts = [np.where((owner == 0)[..., None], a, 0)]
    rows = [int(np.nonzero(drawn.any(1))[0][-1])]
    for k in range(len(seeds)):
        mask = owner == k + 1
        parts.append(np.where(mask[..., None], a, 0))
        rows.append(int(np.nonzero(mask.any(1))[0][-1]))
    return [Image.fromarray(part.astype(np.uint8)) for part in parts], rows


def drawn_span(im, foot):
    """The leftmost and rightmost columns drawn in the picture's bottom three rows down to `foot`, where a trunk meets the ground."""
    rows = np.asarray(im)[max(0, foot - 2):foot + 1, :, 3] > 127
    cols = np.nonzero(rows.any(0))[0]
    return [int(cols[0]), int(cols[-1])] if len(cols) else [1 << 20, -1]


def frames_of(unit, src, folder):
    """The frames of one animation folder in name order, flipped from their mirror folder where MIRROR says so."""
    mirrored = MIRROR.get(unit, {}).get(folder)
    paths = sorted((src / (mirrored or folder)).glob("frame_*.png"))
    frames = [Image.open(p).convert("RGBA") for p in paths]
    if mirrored:
        frames = [im.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for im in frames]
    return frames, [p.name for p in paths]


def main():
    if "--livery-only" in sys.argv:
        atlas = Image.open(OUT / "atlas.png").convert("RGBA")
        tag_livery(atlas, json.loads((OUT / "atlas.json").read_text())).save(OUT / "atlas.png")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    sets = []
    for unit, action in UNITS.items():
        src = RAW / FOLDERS.get(unit, unit)
        attacks = all((src / f"attack_{d}").is_dir() for d in DIRS)
        for d in DIRS:
            folder = src / f"t_{action}_{d}"
            frames, _ = frames_of(unit, src, folder.name)
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
                frames, names = frames_of(unit, src, f"attack_{d}")
                if names != [f"frame_{i:02d}.png" for i in range(9)]:
                    raise SystemExit(f"{src / f'attack_{d}'} must hold exactly frame_00 to frame_08")
                # The strike starts from the standing pose, so the anchor comes from it and the pose itself is left out.
                images, anchor = crop_set(frames[1:], (frames[0].width / 2, feet(frames[:1])))
                sets.append((("units", unit, "attack", d), images, anchor))
    extra = {}
    for name in PROPS:
        im = prop_image(name)
        images, anchor = crop_set([im], (im.width / 2, feet([im])))
        sets.append((("props", name), images, anchor))
        extra[name] = {"foot": drawn_span(images[0], int(anchor[1]))}
        if name == "wheat_field":
            # The wheat repeats across a whole field, so it also has a texture of its own.
            images[0].save(OUT / "wheat_tile.png")
    coin = rimmed_coin(prop_image("coin"))
    images, anchor = crop_set([coin], (coin.width / 2, feet([coin])))
    sets.append((("props", "coin_rimmed"), images, anchor))
    for name, source in SPLIT.items():
        im = prop_image(source)
        parts, rows = split_stones(im)
        images, anchor = crop_set(parts, (im.width / 2, feet([im])))
        sets.append((("props", name), images, anchor))
        top = int(anchor[1]) - feet([im])
        extra[name] = {"feet": [row + top for row in rows]}
    for ground, province in fort_ground.variants().items():
        for name, im in fort_pictures(ground, province).items():
            images, anchor = crop_set([im], (im.width / 2, feet([im])))
            sets.append((("props", name), images, anchor))
    for name, path in SHEETS.items():
        frames = sheet_frames(Image.open(RAW / path).convert("RGBA"))
        images, anchor = crop_set(frames, (frames[0].width / 2, feet(frames)))
        sets.append((("props", name), images, anchor))
        for small, (sheet, k) in SMALLER.items():
            if sheet == name:
                scaled = smaller(frames, k)
                images, anchor = crop_set(scaled, (scaled[0].width / 2, feet(scaled)))
                sets.append((("props", small), images, anchor))

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
        if key[0] == "props":
            entry.update(extra.get(key[1], {}))
        if key[0] == "units":
            meta["units"].setdefault(key[1], {}).setdefault(key[2], {})[key[3]] = entry
        else:
            meta["props"][key[1]] = entry
    atlas = tag_livery(atlas, meta)
    atlas.save(OUT / "atlas.png")
    (OUT / "atlas.json").write_text(json.dumps(meta))
    (OUT / "grounds").mkdir(exist_ok=True)
    shutil.copy(RAW / "ground" / "grass_tile_b.png", OUT / "grounds" / "germania.png")
    shutil.copy(RAW / "ground" / "gaul_tile.png", OUT / "grounds" / "gaul.png")
    shutil.copy(RAW / "ground" / "dacia_tile_b.png", OUT / "grounds" / "dacia.png")
    shutil.copy(RAW / "ground" / "parthia_tile.png", OUT / "grounds" / "parthia.png")
    shutil.copy(RAW / "ground" / "britannia_tile_b.png", OUT / "grounds" / "britannia.png")
    shutil.copy(RAW / "ground" / "hispania_tile.png", OUT / "grounds" / "hispania.png")
    shutil.copy(RAW / "ground" / "aegyptus_tile.png", OUT / "grounds" / "aegyptus.png")
    shutil.copy(RAW / "ground" / "sarmatia_tile.png", OUT / "grounds" / "sarmatia.png")
    shutil.copy(RAW / "frozen_stream" / "ice_tile.png", OUT / "ice.png")
    print(f"atlas {atlas.size[0]}x{atlas.size[1]}, {len(flat)} sprites")


if __name__ == "__main__":
    main()
