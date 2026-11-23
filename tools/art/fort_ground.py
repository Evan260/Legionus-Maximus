"""Repaints the fort's grass and bare earth in the ground of the province named by each other `fort_ground` in
game/data/content.json ("grass" keeps the pictures as drawn), keeping each pixel's lightness against Germania's ground,
which the green pictures were drawn for."""
import json
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
GROUNDS = ROOT / "game" / "assets" / "grounds"
LUMA = np.array([0.3, 0.59, 0.11])
# The fort pictures that have ground of their own to repaint; the small tents stand on nothing.
PIECES = ("fort_wall", "fort_side", "fort_gate", "watchtower", "command_tent")
# Where each picture's grass begins, in rows from its top, so no moss on the wood above it is repainted.
GROUND_FROM = {"fort_gate": 55, "watchtower": 60, "command_tent": 50}
# Boxes (left, top, right, bottom) holding each picture's bare earth, which is the same orange as the lit wood beside it.
EARTH = {"fort_gate": [(41, 55, 52, 64), (36, 64, 52, 71), (52, 64, 60, 72), (2, 65, 8, 72), (20, 71, 80, 80), (78, 69, 82, 74),
                       (82, 71, 90, 74)],
         "watchtower": [(8, 64, 20, 77), (19, 67, 21, 70), (27, 67, 34, 71), (41, 64, 48, 71), (27, 71, 48, 80), (25, 76, 28, 80)],
         "command_tent": [(17, 50, 31, 60)]}
# The least spread of lightness a repainted bank keeps between its 5th and 95th percentiles, so on even ground like sand it still reads as a ridge.
MIN_SPREAD = 40.0
# How far past the ground's lightest colour a repainted pixel may go, so the bare path through the gate does not shine.
LIGHTEST = 8.0
HIGHLIGHT = 0.5
EARTH_DARKEST = 60


def variants():
    """Each fort ground other than grass, with the province whose ground tile it is painted from."""
    provinces = json.loads((ROOT / "game" / "data" / "content.json").read_text(encoding="utf-8"))["provinces"]
    out = {}
    for pid, p in provinces.items():
        ground = p.get("fort_ground", "grass")
        if ground != "grass":
            out.setdefault(ground, pid)
    return out


def _tile(province):
    a = np.asarray(cv2.cvtColor(cv2.imread(str(GROUNDS / f"{province}.png")), cv2.COLOR_BGR2RGB)).reshape(-1, 3)
    return a.astype(float), a.astype(float) @ LUMA


def palette(province, bins=16):
    """The ground's colours from dark to light, as the mean colour and lightness of each sixteenth of its pixels by lightness."""
    rgb, light = _tile(province)
    # Only pixels near the ground's own colour count, so the grass tufts on the Nile mud do not tint a bank of mud green.
    shade = rgb / np.maximum(rgb.sum(1, keepdims=True), 1.0)
    keep = np.abs(shade - np.median(shade, 0)).max(1) < 0.04
    rgb, light = rgb[keep], light[keep]
    order = np.argsort(light)
    chunks = np.array_split(order, bins)
    colours = np.array([rgb[c].mean(0) for c in chunks])
    lights = np.array([light[c].mean() for c in chunks])
    p5, p50, p95 = np.percentile(light, (5, 50, 95))
    middle = np.array([np.interp(p50, lights, colours[:, c]) for c in range(3)])
    return {"colours": colours, "lights": lights, "mid": p50, "spread": p95 - p5, "middle": middle}


GREEN = palette("germania")


def _colour(pal, light):
    """The ground colour at each lightness, darkened in proportion past the ground's darkest and lightened a little past its lightest."""
    lights, colours = pal["lights"], pal["colours"]
    out = np.stack([np.interp(light, lights, colours[:, c]) for c in range(3)], -1)
    dark = light < lights[0]
    out[dark] = colours[0] * (light[dark] / lights[0])[:, None]
    bright = light > lights[-1]
    out[bright] = colours[-1] + np.minimum(light[bright] - lights[-1], LIGHTEST)[:, None]
    return out.clip(0, 255)


def repaint(pixels, pal, mask=None):
    """The pixels under `mask` (every opaque one by default) in the colours of `pal`'s ground, each keeping its lightness
    against Germania's ground."""
    out = pixels.copy()
    m = out[..., 3] > 0 if mask is None else mask & (out[..., 3] > 0)
    if not m.any():
        return out
    light = out[..., :3][m].astype(float) @ LUMA
    scale = max(pal["spread"], MIN_SPREAD) / GREEN["spread"]
    lift = (light - GREEN["mid"]) * scale
    # Grass lit brighter than the ground round it turns only a little lighter, so a bank of sand or snow does not shine.
    lift = np.where(lift > 0, lift * HIGHLIGHT, lift)
    out[..., :3][m] = _colour(pal, pal["mid"] + lift).round().astype(np.uint8)
    return out


def ground_mask(pixels, name):
    """The grass and bare earth at the foot of a fort picture: its green pixels below GROUND_FROM, and its earth-coloured
    pixels inside the picture's EARTH boxes."""
    hsv = cv2.cvtColor(np.ascontiguousarray(pixels[..., :3]), cv2.COLOR_RGB2HSV).astype(int)
    seen = pixels[..., 3] > 0
    mask = seen & (hsv[..., 0] > 20) & (hsv[..., 0] < 90) & (hsv[..., 1] > 40)
    mask[:GROUND_FROM.get(name, 0)] = False
    earth = seen & (hsv[..., 0] >= 5) & (hsv[..., 0] <= 22) & (hsv[..., 1] > 30) & (hsv[..., 2] > EARTH_DARKEST)
    for x0, y0, x1, y1 in EARTH.get(name, ()):
        mask[y0:y1, x0:x1] |= earth[y0:y1, x0:x1]
    return mask
