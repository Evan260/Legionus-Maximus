"""Make the phone app stores' pictures: the Google Play icon, feature graphic and phone and tablet screenshots, and the
App Store icon and iPhone and iPad screenshots, all from the game's own renders.

Each screenshot is the game run in a window of the store's size with the phone's interface and touch controls
(--phone, through tools/phone/phone_scene.gd), so it lays out its buttons, text and insets as that screen gets them.
The game draws 640x360 game pixels widened or deepened to the window's shape, and the picture is that view enlarged a
whole number of times with no smoothing. A 16:9 store size is exactly 3 or 4 times the view. Apple's iPhone and iPad
sizes are not a whole number of times theirs, so the view is enlarged by the next whole number, 4 on the iPhone and 5
on the iPad, and trimmed evenly to the size, with the interface held in from the trimmed edges (--phone-insets) as far
as the game keeps it from a phone's rounded corners. The feature graphic is a battle rendered with no interface
(tools/steam/store_scene.gd) enlarged twice, with the logo at the same pixel size. The icons are the game's own icon,
game/icon.png, with its rounded corners filled, enlarged twice and four times, since both stores round the corners
themselves.

The game lays out a fresh field for every run unless it is given a seed, and barbarians walk about, so look at every
picture afterwards. With --renders=DIR the game's renders are kept in DIR, and any already there are used again instead
of being made afresh, so a scene that came out well can be kept while the others are redone.

Usage: python tools/phone/make_store_art.py [icons] [feature] [screenshots] [SCENE ...] [--renders=DIR]
Naming scenes (such as raise_the_testudo) takes only those again, in every folder that lists them.
Everything rendered goes into a temporary folder that is removed afterwards (or DIR); only the finished pictures are
written, to store/google_play/ and store/app_store/ (see README.txt in each for which file goes where).
"""
import ctypes
import hashlib
import math
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
PLAY = ROOT / "store" / "google_play"
APPLE = ROOT / "store" / "app_store"
GODOT = (Path.home() / "AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
         / "Godot_v4.7.2-stable_win64_console.exe")
PHONE_SCENE = Path(__file__).with_name("phone_scene.gd")
STORE_SCENE = ROOT / "tools" / "steam" / "store_scene.gd"
ICON = ROOT / "game" / "icon.png"
LOGO = ROOT / "game" / "assets" / "logo.png"
sys.path.insert(0, str(ROOT / "tools" / "art"))
import make_icon  # noqa: E402

# Drills that keep the autoplay legion alive long enough to show a late run; every one is in the game.
HARDY = "lorica:9,rations:9,veterans:9,reserves:9,shield_wall:9"
# The newer recruits beside the legionaries and archers, so every screenshot shows a mixed legion.
MEN = "archer:3,cavalry:2,ballista:2,centurion:1,standard_bearer:1,medicus:1"
# Thirteen minutes into a run, a legion of a hundred in gold behind its stakes, with the horde all round it.
LATE = ["--autoplay", "--skip=780", f"--give={HARDY},{MEN},pilum:3,fire_arrows:3"]
# Eighty seconds into a province, a legion of about twenty with an elite or the chieftain brought beside it.
EARLY = ["--autoplay", "--skip=80", f"--give={HARDY},{MEN}"]
# The objectives taken already, as a player who has been about the field has them, so their badges keep off the battle.
TAKEN = "--objectives-done"
# name: the game's flags. --thumb holds a thumb on the stick, as a player steering the legion would; it is shown in a
# few pictures only, so the others keep the whole field clear. Each run is laid out from its --seed, so a picture that came out crowded or empty is
# taken again with another seed or second.
SCENES = {
    "a_hundred_men": [*LATE, "--province=gaul", "--seed=7", TAKEN, "--thumb", "--at=30"],
    # The autoplay raises the testudo five seconds into every twenty, so the berserker is brought just before second 85
    # and the picture taken with the shields up while his red ring is still down.
    "raise_the_testudo": ["--autoplay", "--skip=84.4", f"--give={HARDY},{MEN}", "--men=30", "--seed=7", TAKEN,
                          "--boss=berserker", "--boss-act=whirl", "--at=0.8"],
    "boudicas_chariot": [*EARLY, "--province=britannia", "--seed=7", TAKEN, "--boss=warrior_queen", "--boss-act=drive",
                         "--at=1.0"],
    # The elephant is brought on the left, clear of the buttons, and low enough that his name stays below the top bar.
    "the_war_elephant": [*EARLY, "--province=parthia", "--seed=7", TAKEN, "--boss=war_elephant", "--boss-act=trample",
                         "--boss-shift=-400,70", "--at=0.4"],
    "the_falx_band_charges": [*EARLY, "--province=dacia", "--seed=3", "--men=20", TAKEN, "--boss=falx_band",
                              "--boss-act=onrush", "--at=0.5"],
    "a_bridge_over_the_ravine": [*EARLY, "--province=hispania", "--seed=7", TAKEN, "--go-to=bridge", "--thumb", "--at=3"],
    # The king's warning would run under the right-hand buttons, so the fire is taken once it has gone.
    "the_steppe_on_fire": ["--autoplay", "--skip=80", f"--give={HARDY},archer:3,cavalry:10,ballista:1,centurion:1,"
                           "standard_bearer:1", "--province=sarmatia", "--seed=9", "--commander=cavalry_prefect", TAKEN,
                           "--boss=rasparaganus", "--boss-act=fire", "--at=4.5"],
    "a_level_up": ["--autoplay", "--skip=360", f"--give={HARDY},{MEN}", "--province=aegyptus", "--seed=7", TAKEN,
                   "--hold-choice", "--at=3"],
    "the_campaign_map": ["--screen=map", "--at=2"],
}
# The phone stores' first three screenshots show first on the listing, so they lead with the legion of a hundred, the war
# elephant and Boudica's chariot.
PHONE = ["a_hundred_men", "the_war_elephant", "boudicas_chariot", "the_steppe_on_fire", "raise_the_testudo",
         "a_bridge_over_the_ravine", "the_falx_band_charges"]
TABLET = ["a_hundred_men", "the_war_elephant", "the_steppe_on_fire", "the_campaign_map"]
# folder: (the store's size, the scenes in upload order, flags per scene laid over its own). Apple's sizes trim the
# view's edges, which would cut the map's names at the top on the iPhone, and both the map's panel and the level-up's
# list of arms at the sides on the iPad, so neither is taken there; the iPhone takes the level-up, whose cards keep
# inside the trimmed edges at its large text.
SETS = {
    PLAY / "phone_screenshots": ((1920, 1080), [*PHONE, "the_campaign_map"], {}),
    PLAY / "tablet_7_inch_screenshots": ((1920, 1080), TABLET, {}),
    PLAY / "tablet_10_inch_screenshots": ((2560, 1440), TABLET, {}),
    APPLE / "iphone_6.9_inch_screenshots": ((2868, 1320), [*PHONE, "a_level_up"], {}),
    # The iPad's trimmed sides would cut the elephant in half, so he is brought a little nearer the legion.
    APPLE / "ipad_13_inch_screenshots": ((2752, 2064), PHONE, {"the_war_elephant": ["--boss-shift=-340,80"]}),
}
# The feature graphic: a window whose view is 640x360, the flags of the trailer's opening shot (a legion in gold and
# purple ringed by the horde), the second it is taken at, and the crop's centre in game pixels, which sets the legion
# below the logo.
FEATURE = ((1280, 720), ["--autoplay", "--seed=7", "--trailer-shot=hook", f"--give={HARDY},{MEN}", "--men=80",
                         "--livery=2,2", "--march=0.5,0.15"], 5.5, (320, 150))
# How far the logo's top sits below the feature graphic's top edge, in game pixels.
LOGO_TOP = 8


def view_of(window):
    """The view the game draws in a window: 640x360 widened or deepened to its shape (Display.base_size())."""
    aspect = window[0] / window[1]
    if abs(aspect - 640 / 360) < 1e-6:
        return 640, 360
    if aspect > 640 / 360:
        return math.floor(360 * aspect), 360
    return 640, math.floor(640 / aspect)


def layout(size):
    """The view for a store size, the whole number it is enlarged by, and the game pixels trimmed from each side."""
    view = view_of(size)
    scale = max(-(-size[0] // view[0]), -(-size[1] // view[1]))
    return view, scale, ((view[0] * scale - size[0]) / 2 / scale, (view[1] * scale - size[1]) / 2 / scale)


def insets_flag(size):
    """--phone-insets that keep the interface inside the trimmed picture, as far in from its edges as the game keeps it
    from a phone's rounded corners (Touch.insets_for)."""
    view, scale, trim = layout(size)
    if trim == (0, 0):
        return []
    window_scale = size[1] / view[1]
    corner = math.ceil(math.ceil(min(size) * 0.035) / window_scale)
    x, y = (math.floor((math.ceil(t) + corner) * window_scale) for t in trim)
    return [f"--phone-insets={x},{y},{x},{y}"]


def godot(window, flags, script):
    return subprocess.run([str(GODOT), "--path", str(ROOT / "game"), "--fixed-fps", "60", "--audio-driver", "Dummy",
                           "--resolution", f"{window[0]}x{window[1]}", "--script", str(script), "--", *flags],
                          capture_output=True, timeout=600)


def flags_for(name, size, extra):
    """The game's flags for a scene at a store size: the phone, the insets, the scene's own and the set's laid over them."""
    keys = {f.split("=")[0] for f in extra}
    return ["--no-save", "--phone", *insets_flag(size), *[f for f in SCENES[name] if f.split("=")[0] not in keys], *extra]


def render(tmp, name, size, flags):
    """The game's own view of a scene, as a phone of the store's size shows it. A kept render is used again only when it
    was taken with the same flags."""
    view, _, _ = layout(size)
    stamp = hashlib.sha1(" ".join(flags).encode()).hexdigest()[:8]
    path = tmp / f"{name}_{view[0]}x{view[1]}_{stamp}.png"
    if path.exists():
        print("kept", path.name)
        return path
    godot(size, [*flags, f"--shot={path}"], PHONE_SCENE)
    if not path.exists():
        sys.exit(f"the game did not render {name}")
    print("rendered", path.name)
    return path


def enlarge(img, scale):
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def picture(render_path, size):
    """The view enlarged a whole number of times and trimmed evenly to the store's size, with no alpha. The trim starts on
    a game pixel's edge, so where the size is not a whole number of game pixels only the right and bottom edges cut one."""
    view, scale, trim = layout(size)
    shot = Image.open(render_path).convert("RGB")
    if shot.size != view:
        sys.exit(f"{render_path.name} is {shot.size}, not the {view} a {size} screen draws")
    left, top = (math.floor(t) * scale for t in trim)
    return enlarge(shot, scale).crop((left, top, left + size[0], top + size[1]))


def screenshots(tmp, only):
    jobs = {}
    for folder, (size, names, extra) in SETS.items():
        for name in names:
            if not only or name in only:
                view, _, _ = layout(size)
                flags = flags_for(name, size, extra.get(name, []))
                # Sizes that draw the same view with the same flags share one render.
                jobs.setdefault((name, view, tuple(flags)), (name, size, flags))
    with ThreadPoolExecutor(3) as pool:
        paths = dict(zip(jobs, pool.map(lambda job: render(tmp, *job), jobs.values())))
    for folder, (size, names, extra) in SETS.items():
        folder.mkdir(parents=True, exist_ok=True)
        if not only:
            for old in folder.glob("*.png"):
                old.unlink()
        for k, name in enumerate(names, 1):
            if only and name not in only:
                continue
            view, _, _ = layout(size)
            path = paths[(name, view, tuple(flags_for(name, size, extra.get(name, []))))]
            picture(path, size).save(folder / f"{k:02d}_{name}.png")
        print("laid out", folder.relative_to(ROOT))


def logo():
    pic = Image.open(LOGO).convert("RGBA")
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


def feature_graphic(tmp):
    """A legion in gold ringed by a horde, 1024x500 at two screen pixels to the game pixel, with the logo over it."""
    window, flags, at, centre = FEATURE
    path = tmp / f"feature_scene_{hashlib.sha1(' '.join(flags).encode()).hexdigest()[:8]}.png"
    if not path.exists():
        godot(window, [*flags, f"--store-shot={path}", f"--store-at={at}"], STORE_SCENE)
        if not path.exists():
            sys.exit("the game did not render the feature graphic's scene")
        print("rendered", path.name)
    scene = Image.open(path).convert("RGBA")
    w, h = 512, 250
    left = min(max(0, centre[0] - w // 2), scene.width - w)
    top = min(max(0, centre[1] - h // 2), scene.height - h)
    base = scene.crop((left, top, left + w, top + h))
    mark = logo()
    at = ((w - mark.width) // 2, LOGO_TOP)
    base = shadow_under(base, mark, at)
    base.alpha_composite(mark, at)
    enlarge(base, 2).convert("RGB").save(PLAY / "feature_graphic_1024x500.png")
    print("made feature_graphic_1024x500.png")


def icons():
    # The stores take a square and round its corners themselves, so the icon's own rounded corners are filled.
    icon = Image.new("RGBA", (256, 256), make_icon.DARK)
    icon.alpha_composite(Image.open(ICON).convert("RGBA"))
    # Google asks for a 32-bit PNG and Apple refuses any alpha channel, even a fully opaque one.
    enlarge(icon, 2).save(PLAY / "icon_512.png")
    enlarge(icon.convert("RGB"), 4).save(APPLE / "icon_1024.png")
    print("made icon_512.png and icon_1024.png")


def main():
    which = [a for a in sys.argv[1:] if not a.startswith("--")]
    kept = [a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--renders=")]
    only = [a for a in which if a in SCENES]
    unknown = [a for a in which if a not in SCENES and a not in ("icons", "feature", "screenshots")]
    if unknown:
        sys.exit(f"no such part or scene: {', '.join(unknown)}")
    parts = [a for a in which if a in ("icons", "feature", "screenshots")] or (["screenshots"] if only else
                                                                               ["icons", "feature", "screenshots"])
    if sys.platform == "win32":
        # A pointer resting over a game window would light up a button, so it waits in the desktop's top corner.
        user32 = ctypes.windll.user32
        user32.SetCursorPos(user32.GetSystemMetrics(76), user32.GetSystemMetrics(77))
    PLAY.mkdir(parents=True, exist_ok=True)
    APPLE.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(kept[0]) if kept else Path(folder)
        tmp.mkdir(parents=True, exist_ok=True)
        if "icons" in parts:
            icons()
        if "feature" in parts:
            feature_graphic(tmp)
        if "screenshots" in parts or only:
            screenshots(tmp, only)
    print("laid out", PLAY.relative_to(ROOT), "and", APPLE.relative_to(ROOT))


if __name__ == "__main__":
    main()
