"""Make the Steam achievement icons and the achievement table.

Each icon is a gold-framed parchment tile in the style of the game's achievement card, holding art the game already
has: a province's ground with its chieftain, commanders and recruits from the atlas, an arm's or form's icon on an
ember glow, or a crowd of barbarians or legionaries. It is composed on a 64 pixel grid with whole pixels, then
enlarged four times with no smoothing to Steam's 256 by 256. Steamworks takes JPG files, so the tiles have no
transparency. The locked icon is the same tile in grey.

Usage: python tools/steam/make_achievement_icons.py
Writes store/achievements/<id>.jpg (earned) and <id>_locked.jpg (before), store/achievements/sheet.png to look them
over, and store/achievements/achievements.md, the table of API name, name, description and hidden flag, read from
game/data/content.json.
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
OUT = ROOT / "store" / "achievements"
ATLAS = Image.open(GAME / "assets" / "atlas.png").convert("RGBA")
ATLAS_JSON = json.loads((GAME / "assets" / "atlas.json").read_text(encoding="utf-8"))
FONT = ImageFont.truetype(str(GAME / "assets" / "fonts" / "Silkscreen-Regular.ttf"), 8)
GRID = 64
SCALE = 4
INK = (41, 26, 20)
PARCH = (245, 230, 194)
PARCH_DARK = (209, 179, 133)
GOLD = (232, 176, 64)
GOLD_LIGHT = (255, 227, 150)
GOLD_DARK = (156, 106, 36)
RED = (184, 46, 36)
RED_DARK = (110, 28, 24)

# Each achievement's picture: a province with its chieftain, sprites, an icon, or a crowd.
ART = {
    "win_germania": ("province", "germania", "chieftain"),
    "win_britannia": ("province", "britannia", "warrior_queen"),
    "win_gaul": ("province", "gaul", "gaul_king"),
    "win_dacia": ("province", "dacia", "dacian_king"),
    "win_parthia": ("province", "parthia", "shah"),
    "win_hispania": ("province", "hispania", "viriathus"),
    "win_aegyptus": ("province", "aegyptus", "achillas"),
    "win_sarmatia": ("province", "sarmatia", "rasparaganus"),
    "win_as_archer_captain": ("duo", ["commander", "archer"], "laurel"),
    "win_as_engineer": ("duo_icon", "commander", "scorpio", "laurel"),
    "commander_cavalry_prefect": ("duo_icon", "commander", "cavalry", "red"),
    "commander_old_centurion": ("duo_icon", "commander", "centurion", "red"),
    "commander_legate": ("duo_icon", "commander", "standard_bearer", "red"),
    "forge_hooked_pila": ("forge", "hooked_pila"),
    "forge_greek_fire": ("forge", "greek_fire"),
    "forge_siege_train": ("forge", "siege_train"),
    "forge_hunting_horn": ("forge", "hunting_horn"),
    "forge_burning_eagle": ("forge", "burning_eagle"),
    "forge_fortified_camp": ("forge", "fortified_camp"),
    "kills_1000": ("crowd", ["barbarian_club"], "1K"),
    "kills_10000": ("crowd", ["barbarian_spear", "barbarian_club", "axe_thrower"], "10K"),
    "kills_100000": ("crowd", ["barbarian_spear", "barbarian_club", "axe_thrower", "wolf", "berserker", "barbarian_club"], "100K"),
    "legion_25": ("legion", 2, 3, "25"),
    "legion_50": ("legion", 3, 4, "50"),
    "legion_100": ("legion", 4, 5, "100"),
    "arms_8": ("icons", ["pilum", "scorpio", "onager", "fire_arrows", "caltrops", "eagle"], 3, "8", True),
    "forge_all": ("forge_set", ["hooked_pila", "greek_fire", "siege_train", "hunting_horn", "burning_eagle", "fortified_camp"], 3),
    "drills_all": ("icons", ["shield_wall", "gladius", "lorica", "testudo", "march", "discipline"], 3, "15", False),
}


def sprite(name):
    """The southward idle frame of a unit, cropped to the unit."""
    x, y, w, h = ATLAS_JSON["units"][name]["idle"]["south"]["frames"][0]
    return ATLAS.crop((x, y, x + w, y + h))


def icon(name):
    return Image.open(GAME / "assets" / "icons" / f"{name}.png").convert("RGBA")


def small(name, size):
    """An icon shrunk to a size, its edge kept hard so it stays pixel art."""
    img = icon(name).resize((size, size), Image.LANCZOS)
    img.putalpha(img.getchannel("A").point(lambda a: 255 if a >= 128 else 0))
    return img


def fit(img, height):
    """Enlarge or shrink a sprite to a height, keeping its shape."""
    if img.height == height:
        return img
    w = max(1, round(img.width * height / img.height))
    return img.resize((w, height), Image.NEAREST if height > img.height else Image.LANCZOS)


def tile(red=False):
    """The card's parchment with a darker edge, inside a gold frame inked on both sides."""
    img = Image.new("RGBA", (GRID, GRID), INK)
    d = ImageDraw.Draw(img)
    d.rectangle((1, 1, 62, 62), fill=GOLD_DARK)
    d.rectangle((1, 1, 61, 61), fill=GOLD)
    d.rectangle((2, 2, 61, 2), fill=GOLD_LIGHT)
    d.rectangle((2, 2, 2, 61), fill=GOLD_LIGHT)
    d.rectangle((3, 3, 60, 60), fill=INK)
    base, edge = ((RED, RED_DARK) if red else (PARCH, PARCH_DARK))
    for y in range(4, 60):
        for x in range(4, 60):
            r = max(abs(x - 31.5), abs(y - 31.5)) / 28.0
            img.putpixel((x, y), edge if r > 0.9 else base)
    return img


def glow(img, centre, radius):
    """An ember glow, in rings of colour out from the middle."""
    d = ImageDraw.Draw(img)
    for r, col in ((radius, RED_DARK), (radius * 0.8, RED), (radius * 0.55, (226, 120, 40)), (radius * 0.3, GOLD_LIGHT)):
        d.ellipse((centre[0] - r, centre[1] - r, centre[0] + r, centre[1] + r), fill=col)


def laurel(img, c):
    """The card's laurel: two arcs of gold leaves round a red dot."""
    d = ImageDraw.Draw(img)
    for side in (-1, 1):
        for i in range(6):
            a = math.radians(120 + 20 * i)
            x, y = round(c[0] + math.cos(a) * side * 9), round(c[1] - math.sin(a) * 9)
            d.rectangle((x - 1, y + 2, x + 1, y + 2), fill=INK)
            d.rectangle((x - 1, y - 1, x + 1, y + 1), fill=GOLD if i % 2 == 0 else GOLD_LIGHT)
    d.rectangle((c[0] - 2, c[1] - 2, c[0] + 1, c[1] + 1), fill=RED)


def stand(img, spr, x, foot):
    """Set a sprite with its feet at a row and its middle at a column."""
    img.alpha_composite(spr, (round(x - spr.width / 2), foot - spr.height))


def number(img, text, at):
    """A count on a small gold plate, in the game's pixel font with no smoothing."""
    d = ImageDraw.Draw(img)
    d.fontmode = "1"
    w = round(d.textlength(text, font=FONT))
    x0, y0 = at[0] - w // 2 - 3, at[1]
    d.rectangle((x0, y0, x0 + w + 6, y0 + 10), fill=INK)
    d.rectangle((x0 + 1, y0 + 1, x0 + w + 5, y0 + 9), fill=GOLD)
    d.text((x0 + 3, y0), text, font=FONT, fill=INK)


def province(img, ground, boss):
    g = Image.open(GAME / "assets" / "grounds" / f"{ground}.png").convert("RGBA")
    img.paste(g.crop((100, 100, 156, 156)), (4, 4))
    spr = sprite(boss)
    spr = fit(spr, 50) if spr.height > 50 else spr
    stand(img, spr, 28, 58)
    laurel(img, (49, 49))


def duo(img, names, mark):
    sprs = [sprite(n) for n in names]
    sprs = [fit(s, 44) if s.height > 44 else s for s in sprs]
    stand(img, sprs[0], 21, 56)
    stand(img, sprs[1], 42, 56)
    if mark == "laurel":
        laurel(img, (32, 14))
    else:
        d = ImageDraw.Draw(img)
        for i, col in enumerate((GOLD_LIGHT, GOLD)):
            d.polygon([(32 - 6 + i, 6), (32 + 6 - i, 6), (32, 14 - i * 2)], fill=col)


def duo_icon(img, name, icon_name, mark):
    glow(img, (40, 32), 20)
    img.alpha_composite(icon(icon_name).resize((48, 48), Image.NEAREST), (16, 8))
    stand(img, sprite(name), 20, 58)
    if mark == "laurel":
        laurel(img, (32, 12))
    else:
        d = ImageDraw.Draw(img)
        for i, col in enumerate((GOLD_LIGHT, GOLD)):
            d.polygon([(32 - 6 + i, 6), (32 + 6 - i, 6), (32, 14 - i * 2)], fill=col)


def forge(img, name):
    glow(img, (32, 32), 26)
    big = icon(name).resize((48, 48), Image.NEAREST)
    img.alpha_composite(big, (8, 8))
    d = ImageDraw.Draw(img)
    for x, y in ((9, 12), (52, 10), (12, 50), (51, 52), (5, 30), (57, 31)):
        d.rectangle((x, y, x + 1, y + 1), fill=GOLD_LIGHT)


def icons(img, names, cols, text, embers):
    """Icons in rows under a count, on small ember glows or on the bare parchment."""
    size, gap = 16, 2
    rows = (len(names) + cols - 1) // cols
    left = 32 - (cols * size + (cols - 1) * gap) // 2
    top = 37 - (rows * size + (rows - 1) * gap) // 2
    for n, name in enumerate(names):
        r, c = divmod(n, cols)
        x, y = left + c * (size + gap), top + r * (size + gap)
        if embers:
            glow(img, (x + size / 2 - 0.5, y + size / 2 - 0.5), size * 0.56)
        img.alpha_composite(small(name, size), (x, y))
    number(img, text, (32, 6))


def forge_set(img, names, cols):
    """Forged icons in rows on one big ember glow, with the forge's sparks."""
    glow(img, (32, 32), 27)
    size, gap = 17, 1
    rows = (len(names) + cols - 1) // cols
    left = 32 - (cols * size + (cols - 1) * gap) // 2
    top = 32 - (rows * size + (rows - 1) * gap) // 2
    for n, name in enumerate(names):
        r, c = divmod(n, cols)
        img.alpha_composite(small(name, size), (left + c * (size + gap), top + r * (size + gap)))
    d = ImageDraw.Draw(img)
    for x, y in ((9, 12), (52, 10), (12, 50), (51, 52), (5, 30), (57, 31)):
        d.rectangle((x, y, x + 1, y + 1), fill=GOLD_LIGHT)


def crowd(img, names, text):
    n = len(names)
    rows = [names] if n <= 3 else [names[:3], names[3:]]
    height = 40 if n == 1 else (24 if n <= 3 else 19)
    foot0 = 54 if len(rows) == 1 else 40
    for r, row in enumerate(rows):
        spacing = 20 if len(rows) == 1 else 15
        for i, name in enumerate(row):
            x = 32 + (i - (len(row) - 1) / 2) * spacing + (6 if r else 0)
            stand(img, fit(sprite(name), height), x, foot0 + r * 14)
    number(img, text, (32, 6))


def legion(img, rows, cols, text):
    spr = fit(sprite("legionary"), 20)
    for r in range(rows):
        for c in range(cols):
            x = 32 + (c - (cols - 1) / 2) * 10.0
            stand(img, spr, x, 58 - 8 * (rows - 1 - r))
    number(img, text, (32, 6))


def build(ach_id):
    spec = ART[ach_id]
    red = spec[-1] == "red"
    img = tile(red)
    kind = spec[0]
    if kind == "province":
        province(img, spec[1], spec[2])
    elif kind == "duo":
        duo(img, spec[1], spec[2])
    elif kind == "duo_icon":
        duo_icon(img, spec[1], spec[2], spec[3])
    elif kind == "forge":
        forge(img, spec[1])
    elif kind == "crowd":
        crowd(img, spec[1], spec[2])
    elif kind == "icons":
        icons(img, spec[1], spec[2], spec[3], spec[4])
    elif kind == "forge_set":
        forge_set(img, spec[1], spec[2])
    else:
        legion(img, spec[1], spec[2], spec[3])
    # Whatever reaches past the stripe is cut off, so the frame stays whole.
    framed = tile(red)
    framed.paste(img.crop((4, 4, 60, 60)), (4, 4))
    img = framed
    return img.resize((GRID * SCALE, GRID * SCALE), Image.NEAREST).convert("RGB")


def locked(img):
    grey = ImageEnhance.Color(img).enhance(0.0)
    return ImageEnhance.Brightness(ImageEnhance.Contrast(grey).enhance(0.8)).enhance(0.55)


def table(achievements):
    lines = ["| API name | Name | Description | Hidden |", "|---|---|---|---|"]
    for ach_id, a in achievements.items():
        lines.append(f"| `{ach_id}` | {a['name']} | {a['text']} | {'yes' if a.get('hidden') else 'no'} |")
    return "\n".join(lines) + "\n"


def main():
    content = json.loads((GAME / "data" / "content.json").read_text(encoding="utf-8"))
    achievements = content["achievements"]
    missing = [i for i in achievements if i not in ART]
    if missing:
        sys.exit(f"no picture chosen for {missing}; add them to ART")
    OUT.mkdir(parents=True, exist_ok=True)
    cell = 64 * 3 + 8
    cols = 4
    sheet = Image.new("RGB", (cols * cell, ((len(achievements) + cols - 1) // cols) * 136 + 8), (40, 30, 26))
    for n, ach_id in enumerate(achievements):
        img = build(ach_id)
        dim = locked(img)
        img.save(OUT / f"{ach_id}.jpg", quality=95, subsampling=0)
        dim.save(OUT / f"{ach_id}_locked.jpg", quality=95, subsampling=0)
        x, y = (n % cols) * cell + 4, (n // cols) * 136 + 4
        sheet.paste(img.resize((128, 128), Image.NEAREST), (x, y))
        sheet.paste(img.resize((64, 64), Image.LANCZOS), (x + 132, y))
        sheet.paste(dim.resize((64, 64), Image.LANCZOS), (x + 132, y + 64))
    sheet.save(OUT / "sheet.png")
    (OUT / "achievements.md").write_text(table(achievements), encoding="utf-8")
    print(f"wrote {len(achievements) * 2} icons and the table to {OUT}")


if __name__ == "__main__":
    main()
