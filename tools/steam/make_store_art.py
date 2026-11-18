"""Make the Steam store page's pictures: the capsules, the library art, the page background, the icons and the
screenshots, all from the game's own renders.

Each capsule and the library hero is a run nine minutes in that the game renders at one window pixel to the game
pixel, with no interface, no damage numbers and no shake (tools/steam/store_scene.gd), then enlarged a whole number
of times with no smoothing and cropped to Steam's exact size, so its pixel art stays crisp. The logo is laid over it
at the same pixel size as the scene, on a soft shadow so the name reads over the crowd (the hero has none, since
Steam lays the library logo over it). The page background is the legion at the lip of a ravine, darkened. The
screenshots are the game as it draws at 1920x1080: 640x360 game pixels enlarged three times, interface included.

The game seeds each run from the clock, so every render shows a different field, and some put the legion under the
trees. Look at the capsules after a run. With --renders=DIR the renders are kept in DIR, and any already there are
used again instead of being made afresh, so a field that looked right can be kept while the others are redone.

Usage: python tools/steam/make_store_art.py [screenshots] [capsules] [SCREENSHOT_NAME ...] [--renders=DIR]
Naming screenshots (such as 02_jupiters_storm) takes only those again.
Everything it renders, crops or combines goes into a temporary folder that is removed afterwards (or DIR); only the
finished files are written, to store/steam_page/ (see README.txt there for which file goes in which Steamworks slot).
"""
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "store" / "steam_page"
GODOT = (Path.home() / "AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
         / "Godot_v4.7.2-stable_win64_console.exe")
SCENE = Path(__file__).with_name("store_scene.gd")
sys.path.insert(0, str(ROOT / "tools" / "art"))
import make_icon  # noqa: E402
import make_logo  # noqa: E402

# Drills that keep the autoplay legion alive long enough to show a late run; every one is in the game.
HARDY = "lorica:9,rations:9,veterans:9,reserves:9,shield_wall:9"
# The newer recruits beside the legionaries and archers, so every screenshot shows a mixed legion.
MEN = "slinger:3,cavalry:2,ballista:2,centurion:1,standard_bearer:1,medicus:1"
LATE = ["--autoplay", "--skip=780", f"--give={HARDY},{MEN},pilum:3,fire_arrows:3"]
# Nine minutes in, the legion of about seventy is still in clean ranks, with war bands and elites closing in.
MID = ["--autoplay", "--skip=540", f"--give={HARDY},pilum:3"]
# Eighty seconds into a province, a legion of about twenty with an elite or the chieftain brought beside it, before the
# legion of 25 or the thousandth kill earns a card that would cover the corner.
EARLY = ["--autoplay", "--skip=80", f"--give={HARDY},{MEN}"]
# name: the game's flags. Upload them in this order; the first four show in the sidebar and in search. Each waits until
# the achievement cards a skipped run earns have slid away, or starts early enough to earn none. Each run is laid out
# from its --seed, so a screenshot that came out crowded with labels or empty is taken again with another seed.
SCREENSHOTS = {
    "01_a_hundred_men": [*LATE, "--seed=7", "--at=30"],
    "02_the_war_elephant": [*EARLY, "--province=parthia", "--seed=7", "--boss=war_elephant", "--boss-act=trample", "--at=1.2"],
    "03_boudicas_chariot": [*EARLY, "--province=britannia", "--seed=7", "--boss=warrior_queen", "--boss-act=drive", "--at=1.5"],
    "04_a_bridge_over_the_ravine": ["--autoplay", "--skip=80", f"--give={HARDY},{MEN}", "--seed=7", "--go-to=bridge", "--at=3"],
    "05_the_falx_band_charges": [*EARLY, "--province=dacia", "--seed=3", "--boss=falx_band", "--boss-act=onrush", "--at=0.8"],
    "06_the_gaulish_king": [*EARLY, "--province=gaul", "--seed=7", "--boss=gaul_king", "--boss-act=siege", "--at=2.2"],
    "07_jupiters_storm": ["--autoplay", "--skip=480", f"--give={HARDY},{MEN}", "--seed=7", "--god=jupiter", "--god-at=25",
                          "--at=25.35"],
    "08_holding_the_fort": [*EARLY, "--province=parthia", "--seed=7", "--go-to=fort", "--at=1.5"],
    "09_a_level_up": ["--autoplay", "--skip=360", f"--give={HARDY},{MEN}", "--seed=7", "--hold-choice", "--at=3"],
    "10_the_campaign_map": ["--screen=map", "--at=2"],
}

# name: (window size, the game's flags, seconds into the look). The window sets the game's view: its shorter side is
# 360 or 640 game pixels and the other grows to match.
RENDERS = {
    "battle": ((1200, 1200), MID, 4),
    "wide": ((1920, 620), MID, 4),
    "ravine": ((1440, 810), ["--autoplay", "--skip=120", f"--give={HARDY}", "--go-to=ravine"], 2),
}
# name: (Steam's size, the render, screen pixels to the game pixel, the crop's centre in the render, the logo, the
# logo's top in game pixels).
CAPSULES = {
    "header_capsule_920x430.png": ((920, 430), "battle", 2, (350, 262), "full", 4),
    "small_capsule_462x174.png": ((462, 174), "battle", 2, (330, 300), "compact", 6),
    "main_capsule_1232x706.png": ((1232, 706), "battle", 2, (330, 280), "full", 10),
    "vertical_capsule_748x896.png": ((748, 896), "battle", 2, (350, 300), "full", 12),
    "library_capsule_600x900.png": ((600, 900), "battle", 2, (350, 300), "plain", 14),
}


def godot(window, flags, extra):
    return subprocess.run([str(GODOT), "--path", str(ROOT / "game"), "--fixed-fps", "60", "--resolution",
                           f"{window[0]}x{window[1]}", *extra, "--", *flags], capture_output=True, timeout=600)


def render(tmp, name):
    """The scene with no interface, at one window pixel to the game pixel."""
    window, flags, at = RENDERS[name]
    path = tmp / f"{name}.png"
    if path.exists():
        print("kept", name)
        return Image.open(path).convert("RGBA")
    godot(window, [*flags, f"--store-shot={path}", f"--store-at={at}"], ["--script", str(SCENE)])
    if not path.exists():
        sys.exit(f"the game did not render {name}")
    print("rendered", name)
    return Image.open(path).convert("RGBA")


def enlarge(img, scale):
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def name_lines(cap, gap):
    """The name in two lines with no laurel, its capitals `cap` game pixels tall."""
    make_logo.CAP = cap
    lines = [make_logo.shade(make_logo.glyph_line(t)) for t in make_logo.LINES]
    width = max(line.width for line in lines)
    pic = Image.new("RGBA", (width, sum(line.height for line in lines) + gap), (0, 0, 0, 0))
    y = 0
    for line in lines:
        pic.alpha_composite(line, ((width - line.width) // 2, y))
        y += line.height + gap
    return pic


def logo(kind):
    """The logo trimmed to its drawn pixels, at one pixel to the game pixel."""
    if kind == "full":
        pic = Image.open(ROOT / "game" / "assets" / "logo.png").convert("RGBA")
    else:
        pic = name_lines(27 if kind == "plain" else 19, 7 if kind == "plain" else 4)
    return pic.crop(pic.getbbox())


def shadow_under(base, mark, at):
    """Darkens the scene in a soft patch under the logo, so the gold letters stand clear of the crowd."""
    mask = Image.new("L", base.size, 0)
    pad = 6
    ImageDraw.Draw(mask).rounded_rectangle((at[0] - pad, at[1] - pad, at[0] + mark.width + pad, at[1] + mark.height + pad),
                                           radius=18, fill=150)
    mask = mask.filter(ImageFilter.GaussianBlur(9))
    dark = Image.new("RGBA", base.size, (16, 10, 6, 255))
    return Image.composite(dark, base, mask)


def make_capsules(renders):
    for name, (size, scene, scale, centre, kind, logo_top) in CAPSULES.items():
        w, h = -(-size[0] // scale), -(-size[1] // scale)
        src = renders[scene]
        left = min(max(0, centre[0] - w // 2), src.width - w)
        top = min(max(0, centre[1] - h // 2), src.height - h)
        base = src.crop((left, top, left + w, top + h))
        mark = logo(kind)
        at = ((w - mark.width) // 2, logo_top)
        base = shadow_under(base, mark, at)
        base.alpha_composite(mark, at)
        big = enlarge(base, scale)
        left, up = (big.width - size[0]) // 2, (big.height - size[1]) // 2
        big.crop((left, up, left + size[0], up + size[1])).convert("RGB").save(OUT / name)
        print("made", name)
    # Steam's library header is the same picture as the store's header capsule.
    Image.open(OUT / "header_capsule_920x430.png").save(OUT / "library_header_920x430.png")
    # The hero is the same run four times its pixel size, with room left for the library logo.
    wide = renders["wide"]
    left, top = (wide.width - 960) // 2, (wide.height - 310) // 2
    enlarge(wide.crop((left, top, left + 960, top + 310)), 4).convert("RGB").save(OUT / "library_hero_3840x1240.png")
    # The page background is the legion at the lip of a ravine, behind the store page's text, three times its pixel
    # size and darkened.
    ravine = renders["ravine"]
    left, top = (ravine.width - 480) // 2, (ravine.height - 270) // 2
    page = enlarge(ravine.crop((left, top, left + 480, top + 270)).convert("RGB"), 3)
    page.crop((1, 0, 1439, 810)).point(lambda v: int(v * 0.45)).save(OUT / "page_background_1438x810.png")


def make_logo_and_icons():
    mark = enlarge(logo("full"), 4)
    canvas = Image.new("RGBA", (1280, mark.height), (0, 0, 0, 0))
    canvas.alpha_composite(mark, ((1280 - mark.width) // 2, 0))
    canvas.save(OUT / "library_logo_1280_transparent.png")
    # The community icon is square, so the helmet sits on a square red field with a gold rim and no rounded corners.
    side = 184
    tile = Image.new("RGBA", (side, side), make_icon.DARK)
    d = ImageDraw.Draw(tile)
    d.rectangle((6, 6, side - 7, side - 7), fill=make_icon.GOLD)
    d.rectangle((12, 12, side - 13, side - 13), fill=make_icon.RED)
    d.line((13, 13, side - 14, 13), fill=make_icon.GOLD_LIGHT, width=2)
    head = make_icon.helmet()
    scale = (side - 36) // head.width
    art = enlarge(head, scale)
    shade = Image.new("RGBA", art.size, (0, 0, 0, 0))
    shade.paste((20, 6, 4, 200), mask=art.split()[3])
    x, y = (side - art.width) // 2, (side - art.height) // 2 + 4
    tile.alpha_composite(shade, (x + 4, y + 4))
    tile.alpha_composite(art, (x, y))
    tile.convert("RGB").save(OUT / "community_icon_184x184.jpg", quality=95)
    (OUT / "app_icon.ico").write_bytes((ROOT / "game" / "icon.ico").read_bytes())


def take_screenshot(tmp, name):
    path = tmp / f"{name}.png"
    godot((1920, 1080), [*SCREENSHOTS[name], f"--shot={path}"], [])
    if not path.exists():
        return f"{name}: the game did not save it"
    # The game draws 640x360 game pixels; three times that is exactly 1920x1080.
    shot = Image.open(path).convert("RGB")
    enlarge(shot, 1920 // shot.width).save(OUT / "screenshots" / f"{name}.png")
    return f"{name}: {' '.join(SCREENSHOTS[name])}"


def make_screenshots(tmp, only):
    folder = OUT / "screenshots"
    folder.mkdir(parents=True, exist_ok=True)
    # A screenshot no longer in the list is taken off the page.
    for old in folder.glob("*.png"):
        if old.stem not in SCREENSHOTS:
            old.unlink()
    with ThreadPoolExecutor(3) as pool:
        for line in pool.map(lambda n: take_screenshot(tmp, n), [n for n in SCREENSHOTS if not only or n in only]):
            print(line)


def main():
    which = [a for a in sys.argv[1:] if not a.startswith("--")] or ["capsules", "screenshots"]
    kept = [a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--renders=")]
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(kept[0]) if kept else Path(folder)
        tmp.mkdir(parents=True, exist_ok=True)
        if "capsules" in which:
            with ThreadPoolExecutor(3) as pool:
                renders = dict(zip(RENDERS, pool.map(lambda n: render(tmp, n), RENDERS)))
            make_capsules(renders)
            make_logo_and_icons()
        if "screenshots" in which:
            make_screenshots(tmp, [a for a in which if a in SCREENSHOTS])
        elif any(a in SCREENSHOTS for a in which):
            make_screenshots(tmp, [a for a in which if a in SCREENSHOTS])
    print("laid out", OUT)


if __name__ == "__main__":
    main()
