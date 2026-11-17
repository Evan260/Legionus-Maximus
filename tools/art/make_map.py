"""Renders game/assets/map.png, the campaign map, as pixel art from the Natural Earth data in tools/art/geo; --preview PATH also saves it at 2x."""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
GEO = ROOT / "tools" / "art" / "geo"
OUT = ROOT / "game" / "assets" / "map.png"

W, H = 640, 360
# The projection is equirectangular with longitude scaled by cos 42°, the same as in game/scripts/screens/map.gd.
WEST, NORTH = -11.5, 58.9
PX_PER_DEG = 13.8
COS = math.cos(math.radians(42.0))
SS = 4

C = {
    "deep": (4, 81, 154), "deep2": (6, 74, 144), "wave": (25, 130, 208), "shelf": (9, 105, 187), "shallow": (25, 130, 208),
    "lake": (25, 130, 208), "river": (16, 118, 198), "coast": (40, 26, 20),
    "grass1": (118, 152, 58), "grass2": (96, 134, 50), "grass3": (74, 114, 46),
    "meadow1": (152, 160, 62), "meadow2": (128, 140, 50),
    "dry1": (196, 168, 86), "dry2": (172, 142, 68),
    "steppe1": (212, 172, 96), "steppe2": (200, 158, 82),
    "sand1": (236, 190, 110), "sand2": (228, 178, 98), "dune_hi": (246, 212, 140), "dune_lo": (202, 146, 72),
    "forest": (36, 74, 44), "forest_hi": (60, 106, 54), "forest_lo": (22, 48, 34),
    "snow": (238, 242, 246), "snow_lo": (190, 202, 220), "rock_hi": (162, 144, 122), "rock_lo": (112, 94, 80), "peak_line": (52, 36, 28),
    "drock_hi": (204, 156, 92), "drock_lo": (150, 100, 58),
}
EMPIRE_TINT = np.array([255, 170, 90], float)
EMPIRE_MIX = 0.3

RIVERS = {"Rhine", "Rhein", "Rhin", "Nederrijn", "Waal", "Lek", "Danube", "Donau", "Borcea", "Bratul Chillia", "Bratul Sfintu Gheorghe",
          "Bratul Sulina", "Nile", "Rosetta Branch", "Damietta Branch", "Rhône", "Po", "Euphrates", "Al Furat", "Firat", "Tigris", "Dicle",
          "Shatt al Arab", "Seine", "Loire", "Garonne", "Ebro", "Tajo", "Tejo", "Duero", "Elbe", "Oder", "Vistula", "Dniester", "Dnepre",
          "Dnipro", "Don", "Volga", "Thames", "Jordan", "Tisza", "Tisa", "Drava", "Ural"}
# Modern reservoirs did not exist in the Roman world.
SKIP_LAKES = {"Rybinsk Reservoir", "Kremenchuk Reservoir", "Kakhovka Reservoir", "Samara Reservoir", "Lake Nasser", "Lake Tharthar",
              "Razzaza Lake", "Lake Habbaniyah"}
# Rivers whose banks stay green through the desert.
GREEN_BANKS = {"Nile", "Rosetta Branch", "Damietta Branch", "Euphrates", "Al Furat", "Firat", "Tigris", "Dicle", "Shatt al Arab"}
# Only the Pyrenees and the Caucasus are snowy throughout; the Alps carry snow on their high core alone.
SNOWY = {"CAUCASUS MTS.", "PYRENEES"}
HALF_SNOW = {"ALPS"}
DESERT_ROCK = {"HEJAZ MTS.", "AHAGGAR MTS.", "TIBESTI MTS.", "KUH RUD MOUNTAINS", "Anti Atlas", "ATLAS SAHARIEN"}
DESERTS = {"ARABIAN PENINSULA"}
# Ranges Natural Earth leaves out of its region polygons, as (lon, lat) outlines.
EXTRA_RANGES = {
    "TAURUS": [(29.6, 37.3), (31.5, 37.6), (33.0, 37.6), (34.5, 37.6), (36.0, 38.0), (37.8, 38.4), (38.0, 37.9), (36.2, 37.5),
               (34.6, 37.1), (33.0, 36.9), (31.4, 37.0), (29.8, 36.9)],
    "LEBANON": [(35.9, 34.6), (36.4, 34.4), (35.9, 33.3), (35.5, 33.4)],
    "ARMENIA": [(38.5, 40.0), (41.5, 40.6), (44.5, 39.9), (44.0, 38.4), (41.0, 38.5), (38.6, 38.8)],
}
# Ranges too thin or too short in Natural Earth, as (lon, lat) crest lines with a half width in degrees and a kind.
RIDGES = {
    "Apennines": ([(8.2, 44.3), (9.3, 44.55), (10.3, 44.3), (11.3, 44.0), (12.2, 43.6), (12.9, 43.0), (13.5, 42.4), (14.2, 41.85),
                   (14.9, 41.3), (15.5, 40.7), (15.9, 40.1), (16.2, 39.5), (16.3, 39.0), (16.1, 38.5), (15.9, 38.1)], 0.3, "rock"),
    "Dinaric Alps": ([(14.2, 45.8), (15.1, 45.1), (16.1, 44.3), (17.2, 43.6), (18.4, 42.9), (19.4, 42.4), (20.2, 41.9)], 0.4, "rock"),
    "Haemus": ([(22.4, 43.7), (23.2, 43.2), (24.0, 42.85), (25.0, 42.75), (26.0, 42.75), (27.0, 42.75), (27.7, 42.7)], 0.22, "rock"),
    "Pindus": ([(20.5, 40.7), (20.9, 40.1), (21.2, 39.5), (21.5, 39.0), (21.9, 38.7), (22.4, 38.6)], 0.28, "rock"),
    "Peloponnese": ([(21.9, 38.0), (22.3, 37.6), (22.4, 37.1), (22.3, 36.6)], 0.22, "light"),
    "Pyrenees": ([(-1.9, 43.05), (-1.0, 42.95), (0.0, 42.75), (1.0, 42.6), (2.0, 42.45), (2.9, 42.4)], 0.32, "snow"),
    "Cantabrian": ([(-7.0, 42.85), (-6.0, 43.0), (-5.0, 43.05), (-4.2, 43.05), (-3.4, 43.1), (-2.6, 43.05)], 0.22, "rock"),
    "Sistema Central": ([(-7.6, 40.3), (-6.6, 40.25), (-5.6, 40.25), (-4.8, 40.4), (-4.0, 40.8), (-3.4, 41.1)], 0.22, "rock"),
    "Sistema Iberico": ([(-3.2, 42.0), (-2.4, 41.7), (-1.7, 41.1), (-1.2, 40.5), (-0.9, 40.1)], 0.25, "light"),
    "Baetic": ([(-5.4, 36.6), (-4.6, 36.85), (-3.6, 37.05), (-2.8, 37.25), (-2.0, 37.7), (-1.2, 38.2), (-0.4, 38.6)], 0.3, "rock"),
    "Highlands": ([(-5.0, 58.3), (-4.8, 57.7), (-4.6, 57.2), (-4.2, 56.85), (-3.5, 56.9), (-2.8, 57.0)], 0.42, "rock"),
    "Massif Central": ([(2.7, 45.8), (2.9, 45.2), (3.3, 44.7), (3.7, 44.3)], 0.42, "light"),
    "Rhodope": ([(23.4, 41.95), (24.2, 41.65), (25.0, 41.5), (25.6, 41.45)], 0.22, "light"),
    "Carpathians": ([(17.6, 48.6), (18.8, 49.1), (20.0, 49.2), (21.4, 49.3), (22.7, 49.0), (23.9, 48.3), (24.9, 47.7), (25.6, 47.0),
                     (25.95, 46.2), (26.1, 45.6), (25.4, 45.4), (24.4, 45.45), (23.3, 45.35), (22.5, 45.2), (22.1, 44.8)], 0.33, "rock"),
    "Apuseni": ([(22.2, 47.0), (22.7, 46.6), (23.1, 46.3)], 0.25, "light"),
    "Corsica": ([(9.1, 42.6), (9.15, 42.1), (9.2, 41.7)], 0.15, "rock"),
    "Sardinia": ([(9.0, 40.4), (9.3, 40.0), (9.4, 39.6)], 0.18, "light"),
    "Sicily": ([(13.3, 37.85), (14.2, 37.9), (14.95, 37.75)], 0.18, "light"),
}
# Natural Earth's Carpathian polygon covers the Transylvanian basin inside the arc, so the arc is drawn by hand instead.
SKIP_RANGES = {"CARPATHIAN MOUNTAINS"}

# How dry the land is, 0 for wet green to 1 for sand, at known places; the field between them is interpolated.
DRYNESS = [
    (-4, 54, 0.0), (-8, 53, 0.0), (2, 47, 0.05), (0, 44, 0.12), (5, 44, 0.25), (10, 51, 0.0), (20, 52, 0.02), (30, 55, 0.05),
    (12, 45, 0.1), (13, 42, 0.3), (16, 40, 0.4), (14, 37.5, 0.5), (9, 40, 0.45), (-4, 40, 0.5), (-6, 42.5, 0.2), (-5, 37.5, 0.5),
    (-1, 38.5, 0.6), (19, 45.5, 0.15), (22, 44, 0.2), (22, 39, 0.45), (26, 42, 0.3), (33, 39, 0.55), (36, 41, 0.25), (30, 38.5, 0.45),
    (36, 34.5, 0.5), (35.5, 32, 0.6), (40, 34, 0.85), (44, 33, 0.75), (46, 31, 0.85), (44, 36.5, 0.55), (42, 38.5, 0.45),
    (46, 38.5, 0.5), (52, 33, 0.85), (58, 38, 0.9), (60, 43, 0.92), (50, 44, 0.75), (55, 50, 0.6), (45, 48, 0.55), (36, 47, 0.38),
    (42, 52, 0.12), (40, 43, 0.15), (48, 41, 0.4), (64, 34, 0.75), (54, 28, 0.9),
    (-6, 34, 0.45), (-8, 31, 0.7), (3, 36.3, 0.45), (10, 36, 0.55), (13, 32.5, 0.8), (21, 32.5, 0.6), (30, 31, 0.95), (25, 29, 1.0),
    (10, 30, 1.0), (0, 30, 1.0), (40, 28, 1.0), (31, 26, 1.0),
]
# How thickly wooded the land is at known places.
FOREST = [
    (9, 52, 1.0), (12, 50.5, 0.95), (7, 49.5, 0.65), (14, 53, 0.95), (19, 51, 0.9), (24, 53, 0.75), (30, 56, 0.6), (24, 47, 0.8),
    (26, 46, 0.75), (2, 48, 0.4), (-2, 53, 0.4), (-4, 57, 0.3), (0, 45, 0.35), (16, 45, 0.55), (20, 43.5, 0.5), (8, 46.5, 0.5),
    (12, 43, 0.25), (-6, 42.8, 0.4), (-4, 40, 0.15), (24, 39.5, 0.15), (34, 41, 0.4), (38, 52, 0.35), (45, 55, 0.45), (40, 44, 0.45),
    (51, 37, 0.5), (32, 47, 0.1), (45, 47, 0.0), (33, 38, 0.05), (36, 34, 0.1), (-8, 53, 0.2), (8, 56, 0.4),
]

# The empire in AD 9 as lon/lat outlines; their edges at sea do not matter because the shape is cut to the land.
EMPIRE_WEST_SEA = [(29.8, 44.8), (29.8, 34.5), (26.5, 34.5), (22.0, 35.2), (14.5, 35.5), (12.6, 37.25), (11.0, 37.6), (8.0, 38.0),
                   (3.0, 37.4), (0.0, 36.3), (-2.0, 36.4), (-4.5, 36.15), (-5.4, 36.0), (-6.2, 36.15), (-13.0, 36.4), (-13.0, 47.0),
                   (-5.0, 49.3), (1.5, 50.95), (2.5, 51.35), (3.98, 51.85)]
EMPIRE_EAST = [(29.0, 42.5), (36.3, 41.9), (36.3, 41.2), (35.5, 40.0), (34.3, 39.0), (34.0, 37.5), (35.2, 37.2), (36.2, 37.3),
               (37.5, 37.0), (38.1, 36.6), (38.3, 34.6), (37.0, 33.0), (36.0, 32.6), (35.6, 32.7), (35.55, 31.8), (35.5, 31.2),
               (35.0, 31.0), (34.3, 31.2), (32.5, 33.0), (29.8, 34.5), (29.0, 36.0)]
EMPIRE_EGYPT = [(25.0, 32.5), (25.0, 22.0), (36.0, 22.0), (35.5, 24.0), (34.0, 26.5), (33.0, 28.0), (32.55, 29.9), (32.5, 30.5),
                (32.4, 31.3), (32.5, 32.5)]
EMPIRE_CYRENE = [(18.8, 30.2), (25.0, 30.6), (25.0, 34.0), (18.8, 34.0)]
EMPIRE_AFRICA = [(6.3, 38.0), (6.3, 35.6), (8.0, 34.6), (9.6, 33.6), (11.5, 32.3), (13.5, 31.9), (15.0, 31.3), (16.5, 30.8),
                 (18.8, 30.2), (18.8, 34.0), (12.0, 38.0)]
# Straits that must stay open, as (lon, lat) lines from sea to sea.
STRAITS = [[(29.2, 41.35), (29.06, 41.12), (28.95, 40.95)]]
# Thrace was a client kingdom until AD 46.
THRACE = [(24.6, 40.8), (24.0, 41.6), (23.6, 42.5), (24.5, 42.8), (26.5, 42.8), (28.0, 42.9), (29.0, 43.0), (29.08, 41.25),
          (29.0, 41.0), (28.5, 40.85), (26.6, 40.3), (26.2, 40.0), (25.8, 40.3)]


def to_px(lon, lat):
    return (np.asarray(lon) - WEST) * COS * PX_PER_DEG, (NORTH - np.asarray(lat)) * PX_PER_DEG


def load(name):
    with open(GEO / f"{name}.geojson", encoding="utf-8") as f:
        return json.load(f)["features"]


def rings_of(geom):
    if geom["type"] == "Polygon":
        return [np.array(r, float) for r in geom["coordinates"]]
    if geom["type"] == "MultiPolygon":
        return [np.array(r, float) for poly in geom["coordinates"] for r in poly]
    return []


def lines_of(geom):
    if geom["type"] == "LineString":
        return [np.array(geom["coordinates"], float)]
    if geom["type"] == "MultiLineString":
        return [np.array(l, float) for l in geom["coordinates"]]
    return []


def in_view(ring, margin=2.0):
    lon, lat = ring[:, 0], ring[:, 1]
    east = WEST + W / (COS * PX_PER_DEG)
    south = NORTH - H / PX_PER_DEG
    return lon.max() > WEST - margin and lon.min() < east + margin and lat.max() > south - margin and lat.min() < NORTH + margin


def fill(rings, s=SS):
    """Even-odd scanline fill of lon/lat rings into a mask s times the picture's size."""
    xs, ys, xe, ye = [], [], [], []
    for r in rings:
        x, y = to_px(r[:, 0], r[:, 1])
        x, y = x * s, y * s
        xs.append(x[:-1]); ys.append(y[:-1]); xe.append(x[1:]); ye.append(y[1:])
    w, h = W * s, H * s
    if not xs:
        return np.zeros((h, w), bool)
    x0, y0, x1, y1 = (np.concatenate(a) for a in (xs, ys, xe, ye))
    lo, hi = np.minimum(y0, y1), np.maximum(y0, y1)
    r0 = np.clip(np.ceil(lo - 0.5), 0, h).astype(int)
    r1 = np.clip(np.ceil(hi - 0.5), 0, h).astype(int)
    n = r1 - r0
    keep = n > 0
    x0, y0, x1, y1, r0, n = x0[keep], y0[keep], x1[keep], y1[keep], r0[keep], n[keep]
    idx = np.repeat(np.arange(len(n)), n)
    rows = r0[idx] + (np.arange(n.sum()) - np.repeat(np.cumsum(n) - n, n))
    yc = rows + 0.5
    t = (yc - y0[idx]) / (y1[idx] - y0[idx])
    xc = x0[idx] + t * (x1[idx] - x0[idx])
    order = np.lexsort((xc, rows))
    rows, xc = rows[order], xc[order]
    cols = np.clip(np.ceil(xc - 0.5), 0, w).astype(int)
    diff = np.zeros((h, w + 1), np.int32)
    sign = np.where(np.arange(len(rows)) % 2 == 0, 1, -1)
    np.add.at(diff, (rows, cols), sign)
    return np.cumsum(diff, axis=1)[:, :w] > 0


def coverage(mask, s=SS):
    return mask.reshape(H, s, W, s).mean(axis=(1, 3))


def area_mask(rings, threshold=0.5, keep_small=False):
    m = coverage(fill(rings)) >= threshold
    if keep_small:
        for r in rings:
            x, y = to_px(r[:, 0], r[:, 1])
            area = 0.5 * abs(np.dot(x[:-1], y[1:]) - np.dot(x[1:], y[:-1]))
            cx, cy = int(x.mean()), int(y.mean())
            if area >= 0.3 and 0 <= cx < W and 0 <= cy < H and not m[max(cy - 1, 0):cy + 2, max(cx - 1, 0):cx + 2].any():
                m[cy, cx] = True
    return m


def poly_mask(points):
    return area_mask([np.array(points + [points[0]], float)])


def value_noise(cell, seed, octaves=3):
    rng = np.random.default_rng(seed)
    out = np.zeros((H, W))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = max(cell / 2 ** o, 1.5)
        gh, gw = int(H / c) + 3, int(W / c) + 3
        grid = rng.random((gh, gw))
        z = ndimage.zoom(grid, c, order=3)[:H, :W]
        out += z * amp
        total += amp
        amp *= 0.5
    out /= total
    return (out - out.min()) / (out.max() - out.min())


def idw(points, power=2.0):
    """Inverse-distance-weighted field over the picture from (lon, lat, value) points."""
    step = 4
    gy, gx = np.mgrid[0:H:step, 0:W:step].astype(float)
    px = np.array([to_px(p[0], p[1]) for p in points])
    vals = np.array([p[2] for p in points])
    d2 = (gx[..., None] - px[:, 0]) ** 2 + (gy[..., None] - px[:, 1]) ** 2 + 40.0
    wgt = 1.0 / d2 ** (power / 2)
    f = (wgt * vals).sum(-1) / wgt.sum(-1)
    return ndimage.zoom(f, step, order=1)[:H, :W]


BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 + 1 / 32.0


def bayer():
    return np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W]


def line_px(a, b):
    """The pixels of a Bresenham line, so rivers stay one hard pixel wide."""
    x0, y0 = int(round(a[0])), int(round(a[1]))
    x1, y1 = int(round(b[0])), int(round(b[1]))
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    out = []
    while True:
        out.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return out
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def chain(lines):
    """Joins river pieces end to end into one line, turning pieces round as needed."""
    out = [tuple(p) for p in lines[0]]
    rest = [[tuple(p) for p in l] for l in lines[1:]]
    while rest:
        best = None
        for i, l in enumerate(rest):
            for flip in (False, True):
                seq = l[::-1] if flip else l
                d = math.dist(out[-1], seq[0])
                if best is None or d < best[0]:
                    best = (d, i, seq)
        out.extend(best[2])
        rest.pop(best[1])
    return out


def river_line(features, names):
    parts = []
    for name in names:
        for f in features:
            if f["properties"]["name"] == name:
                parts.extend(lines_of(f["geometry"]))
    return parts


def frontier(rivers):
    """The empire's northern edge in Europe: down the Rhine from its mouth to Lake Constance, then down the Danube from Raetia."""
    rhine = chain(sorted(river_line(rivers, ["Waal", "Rhine", "Rhin"]), key=lambda l: l[:, 0].min()))
    if rhine[0][0] > rhine[-1][0]:
        rhine = rhine[::-1]
    danube_parts = river_line(rivers, ["Donau", "Danube"])
    danube = chain(sorted(danube_parts, key=lambda l: l[:, 0].min()))
    if danube[0][0] > danube[-1][0]:
        danube = danube[::-1]
    danube = [p for p in danube if p[0] >= 9.6]
    return rhine + [(9.55, 47.5)] + danube


def empire_mask(rivers):
    m = poly_mask(frontier(rivers) + EMPIRE_WEST_SEA)
    for shape in (EMPIRE_EAST, EMPIRE_EGYPT, EMPIRE_CYRENE, EMPIRE_AFRICA):
        m |= poly_mask(shape)
    return m & ~poly_mask(THRACE)


def carve(land, points):
    """Opens a strait narrower than a pixel as a 4-connected line of water, so the seas either side still meet."""
    x, y = to_px([p[0] for p in points], [p[1] for p in points])
    pts = list(zip(x, y))
    for a, c in zip(pts, pts[1:]):
        last = None
        for px, py in line_px(a, c):
            if last and px != last[0] and py != last[1]:
                land[last[1], px] = False
            land[py, px] = False
            last = (px, py)


def ridge_mask(spine, half_width):
    """The land within half_width degrees of a crest line."""
    line = np.zeros((H, W), bool)
    x, y = to_px([p[0] for p in spine], [p[1] for p in spine])
    pts = list(zip(x, y))
    for a, c in zip(pts, pts[1:]):
        for px, py in line_px(a, c):
            if 0 <= px < W and 0 <= py < H:
                line[py, px] = True
    return ndimage.distance_transform_edt(~line) <= half_width * PX_PER_DEG


def peak_sprite(size, snow):
    """A mountain peak as rows of pixel keys: o outline, L lit side, D shaded side, S snow, s shaded snow."""
    h = size
    w = 2 * size - 1
    rows = []
    for y in range(h):
        half = y
        row = []
        for x in range(w):
            dx = x - (size - 1)
            if abs(dx) > half:
                row.append(".")
            elif abs(dx) == half or y == h - 1:
                row.append("o")
            else:
                snowy = snow and y <= h // 2 + (1 if dx < 0 and y % 2 else 0)
                if dx < 0 or (dx == 0 and y % 2 == 0):
                    row.append("S" if snowy else "L")
                else:
                    row.append("s" if snowy else "D")
        rows.append("".join(row))
    return rows


def draw_peaks(img, land, shore, ranges, rng):
    peaks = []
    for name, mask, kind, spine in ranges:
        ys, xs = np.nonzero(mask)
        if len(xs) == 0:
            continue
        dist = ndimage.distance_transform_edt(mask)
        if spine is not None:
            # A hand ridge sets its peaks along its crest, so a range on a narrow peninsula still shows.
            x, y = to_px([p[0] for p in spine], [p[1] for p in spine])
            step, carry, k = (10.0 if kind == "light" else 7.0), 0.0, 0
            for a, c in zip(zip(x, y), zip(x[1:], y[1:])):
                length = math.dist(a, c)
                nx, ny = -(c[1] - a[1]) / length, (c[0] - a[0]) / length
                d = carry
                while d < length:
                    # Peaks step either side of the crest so the range reads as massed mountains, not a line.
                    side = (2.0 if k % 2 else -2.0) if kind != "light" else 0.0
                    px = int(round(a[0] + (c[0] - a[0]) * d / length + nx * side))
                    py = int(round(a[1] + (c[1] - a[1]) * d / length + ny * side))
                    if not (0 <= px < W and 0 <= py < H and land[py, px]):
                        px, py = int(round(a[0] + (c[0] - a[0]) * d / length)), int(round(a[1] + (c[1] - a[1]) * d / length))
                    if 0 <= px < W and 0 <= py < H and shore[py, px]:
                        size = 4 if kind == "light" else 5 + (1 if dist[py, px] > 3 and rng.random() < 0.5 else 0)
                        peaks.append((py, px, size, kind == "snow", False, True))
                    d += step
                    k += 1
                carry = d - length
            continue
        spacing = 8
        for gy in range(ys.min() - spacing, ys.max() + spacing, spacing - 2):
            for gx in range(xs.min() - spacing, xs.max() + spacing, spacing + 2):
                x = gx + (spacing // 2 if (gy // spacing) % 2 else 0) + int(rng.integers(-1, 2))
                y = gy + int(rng.integers(-1, 2))
                if not (0 <= x < W and 0 <= y < H) or not mask[y, x] or not land[y, x]:
                    continue
                core = dist[y, x]
                if rng.random() < (0.55 if kind == "light" else 0.25):
                    continue
                size = 4 if kind == "light" else 4 + (1 if core > 2 and rng.random() < 0.7 else 0) + (1 if core > 4 and rng.random() < 0.6 else 0)
                snow = kind == "snow" or (kind == "half" and core > 3)
                peaks.append((y, x, size, snow, kind == "desert", False))
    for y, x, size, snow, desert, narrow in sorted(peaks):
        sprite = peak_sprite(size, snow)
        top = y - size + 1
        left = x - (size - 1)
        hi, lo = (C["drock_hi"], C["drock_lo"]) if desert else (C["rock_hi"], C["rock_lo"])
        for sy, row in enumerate(sprite):
            for sx, ch in enumerate(row):
                px, py = left + sx, top + sy
                if ch == "." or not (0 <= px < W and 0 <= py < H) or not (shore if narrow else land)[py, px]:
                    continue
                img[py, px] = {"o": C["peak_line"], "L": hi, "D": lo, "S": C["snow"], "s": C["snow_lo"]}[ch]


def main():
    rng = np.random.default_rng(9)
    land_f = load("ne_50m_land")
    land_rings = [r for f in land_f for r in rings_of(f["geometry"]) if in_view(r, 30)]
    land = area_mask(land_rings, 0.5, keep_small=True)
    for strait in STRAITS:
        carve(land, strait)

    lake_rings = [r for f in load("ne_50m_lakes") if f["properties"].get("name") not in SKIP_LAKES
                  for r in rings_of(f["geometry"]) if in_view(r)]
    lakes = area_mask(lake_rings, 0.45, keep_small=True) & land

    regions = load("ne_50m_geography_regions_polys")
    by_name = {}
    for f in regions:
        rings = [r for r in rings_of(f["geometry"]) if in_view(r)]
        if rings:
            by_name.setdefault(f["properties"]["NAME"], (f["properties"]["FEATURECLA"], []))[1].extend(rings)

    sea = ~land
    dist_sea = ndimage.distance_transform_edt(sea)
    inland = ndimage.distance_transform_edt(land)
    b = bayer()
    n1 = value_noise(26, 1)
    n2 = value_noise(9, 2, 2)
    n3 = value_noise(48, 3, 2)

    img = np.zeros((H, W, 3), np.uint8)
    deep = np.where((n3 + (b - 0.5) * 0.12 > 0.62)[..., None], C["deep2"], C["deep"])
    img[:] = deep
    shelf = dist_sea + (n2 - 0.5) * 2.0
    img[sea & (shelf <= 3.6 + b * 1.8)] = C["shelf"]
    img[sea & (dist_sea <= 1.5 + b)] = C["shallow"]

    dry = idw(DRYNESS)
    desert_mask = np.zeros((H, W), bool)
    for name, (cla, rings) in by_name.items():
        if cla == "Desert" or name in DESERTS:
            desert_mask |= area_mask(rings, 0.5)
    desert_mask = ndimage.binary_opening(desert_mask, iterations=1)
    dry = np.where(desert_mask, np.maximum(dry, 0.9), dry)
    dry = ndimage.gaussian_filter(dry, 2.0) + (n1 - 0.5) * 0.12 + (n2 - 0.5) * 0.08
    bands = [(0.2, ("grass1", "grass2", "grass3")), (0.36, ("meadow1", "meadow2")), (0.56, ("dry1", "dry2")),
             (0.76, ("steppe1", "steppe2")), (9.0, ("sand1", "sand2"))]
    grain = rng.random((H, W))
    shade = np.clip(value_noise(10, 4, 2) * 0.7 + n2 * 0.3 + (grain - 0.5) * 0.12, 0, 0.999)
    lower = -9.0
    for i, (upper, cols) in enumerate(bands):
        # A ragged ordered-dither seam between bands keeps the edge hand-painted rather than a contour line.
        lo_edge = lower + (b - 0.5) * 0.06 if i else lower
        hi_edge = upper + (b - 0.5) * 0.06
        sel = land & (dry >= lo_edge) & (dry < hi_edge)
        k = np.clip((shade * len(cols) + (b - 0.5) * 0.5).astype(int), 0, len(cols) - 1)
        for j, name in enumerate(cols):
            img[sel & (k == j)] = C[name]
        lower = upper

    sandy = land & (dry >= 0.76)
    yy, xx = np.mgrid[0:H, 0:W]
    ripple = np.sin(xx * 0.55 + yy * 1.25 + n1 * 14.0)
    img[sandy & (ripple > 0.93)] = C["dune_hi"]
    img[sandy & (ripple < -0.95) & (n2 > 0.45)] = C["dune_lo"]

    rivers = load("ne_50m_rivers_lake_centerlines")
    banks = np.zeros((H, W), bool)
    for f in rivers:
        if f["properties"]["name"] in GREEN_BANKS:
            for line in lines_of(f["geometry"]):
                x, y = to_px(line[:, 0], line[:, 1])
                for a, c in zip(list(zip(x, y)), list(zip(x[1:], y[1:]))):
                    for px, py in line_px(a, c):
                        if 0 <= px < W and 0 <= py < H:
                            banks[py, px] = True
    delta = area_mask(by_name["Nile Delta"][1], 0.3)
    green = land & ((ndimage.distance_transform_edt(~banks) <= 1.6 + b) | ndimage.binary_dilation(delta))
    img[green & (shade < 0.5)] = C["meadow1"]
    img[green & (shade >= 0.5)] = C["grass2"]

    forest = idw(FOREST, 3.0) + (value_noise(7, 5, 2) - 0.5) * 0.7 + (n1 - 0.5) * 0.3
    wooded = land & (forest > 0.62) & (dry < 0.45) & (inland > 1.5)
    wooded = ndimage.binary_opening(wooded)
    img[wooded] = C["forest_lo"]
    for y in range(1, H - 1, 3):
        for x in range((y // 3) % 2 * 2, W - 1, 4):
            tx, ty = x + int(rng.integers(0, 2)), y
            if not wooded[ty, tx]:
                continue
            img[ty, tx] = C["forest"]
            if wooded[ty - 1, tx]:
                img[ty - 1, tx] = C["forest_hi"]
            if wooded[ty, tx - 1]:
                img[ty, tx - 1] = C["forest_hi"]
            if wooded[ty, tx + 1]:
                img[ty, tx + 1] = C["forest"]
            if wooded[ty + 1, tx]:
                img[ty + 1, tx] = C["forest"]

    ranges = []
    for name, (cla, rings) in by_name.items():
        if cla != "Range/mtn":
            continue
        kind = "snow" if name in SNOWY else "half" if name in HALF_SNOW else "desert" if name in DESERT_ROCK else "rock"
        if name not in SKIP_RANGES:
            ranges.append((name, area_mask(rings, 0.3), kind, None))
    for name, pts in EXTRA_RANGES.items():
        ranges.append((name, poly_mask(pts), "rock", None))
    for name, (spine, half_width, kind) in RIDGES.items():
        ranges.append((name, ridge_mask(spine, half_width), kind, spine))
    for name, mask, kind, _ in ranges:
        hi, lo = (C["drock_hi"], C["drock_lo"]) if kind == "desert" else (C["rock_hi"], C["rock_lo"])
        core = ndimage.distance_transform_edt(mask)
        density = np.clip(core / 4.0, 0, 1) * (0.25 if kind == "light" else 0.5)
        rough = land & mask & (b < density)
        img[rough & (n2 < 0.5)] = hi
        img[rough & (n2 >= 0.5)] = lo
        if kind == "snow":
            img[land & mask & (core > 3.0) & (b < np.clip((core - 3.0) / 3.0, 0, 0.6))] = C["snow_lo"]

    emp = empire_mask(load("ne_50m_rivers_lake_centerlines")) & land
    lum = img.astype(float).mean(axis=2, keepdims=True)
    mix = EMPIRE_MIX * np.clip(lum / 150.0, 0.35, 1.0)
    tinted = img.astype(float) * (1 - mix) + EMPIRE_TINT * mix
    img[emp] = tinted[emp].round().astype(np.uint8)

    img[lakes] = C["lake"]
    for f in rivers:
        if f["properties"]["name"] not in RIVERS:
            continue
        for line in lines_of(f["geometry"]):
            x, y = to_px(line[:, 0], line[:, 1])
            pts = list(zip(x, y))
            for a, c in zip(pts, pts[1:]):
                for px, py in line_px(a, c):
                    if 0 <= px < W and 0 <= py < H and land[py, px]:
                        img[py, px] = C["river"]

    water = sea | lakes
    near_water = np.zeros_like(water)
    near_water[1:, :] |= water[:-1, :]
    near_water[:-1, :] |= water[1:, :]
    near_water[:, 1:] |= water[:, :-1]
    near_water[:, :-1] |= water[:, 1:]
    coast = land & ~lakes & near_water
    img[coast] = C["coast"]


    # A hand ridge on a peninsula a few pixels wide may draw its peaks over the coastline.
    draw_peaks(img, land & ~lakes & ~coast, land & ~lakes, ranges, rng)

    open_sea = sea & (dist_sea > 9)
    for y in range(2, H, 7):
        for x in range((y * 5) % 11, W - 3, 11):
            jx, jy = x + int(rng.integers(0, 4)), y + int(rng.integers(0, 3))
            if jy < H - 1 and jx < W - 3 and open_sea[jy, jx:jx + 3].all() and n2[jy, jx] < 0.6:
                img[jy, jx + 1] = C["wave"]
                img[jy + 1, jx] = C["wave"]
                img[jy + 1, jx + 2] = C["wave"]

    Image.fromarray(img, "RGB").save(OUT)
    if "--preview" in sys.argv:
        path = sys.argv[sys.argv.index("--preview") + 1]
        Image.fromarray(img, "RGB").resize((W * 2, H * 2), Image.NEAREST).save(path)
    print(f"wrote {OUT} ({len(np.unique(img.reshape(-1, 3), axis=0))} colours)")


if __name__ == "__main__":
    main()
