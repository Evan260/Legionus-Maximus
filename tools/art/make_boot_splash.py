"""Make the picture Godot shows while the game starts: the logo enlarged three times with whole pixels so it stays crisp.
Godot draws it at its own size in the middle of the window, on the background colour set in project.godot, which is the
average colour of the ground the title opens on.

Usage: python tools/art/make_boot_splash.py
Writes game/assets/boot_splash.png and prints the colour for boot_splash/bg_color.
"""
from pathlib import Path

import numpy as np
from PIL import Image

GAME = Path(__file__).resolve().parents[2] / "game"
SCALE = 3


def main():
    logo = Image.open(GAME / "assets" / "logo.png").convert("RGBA")
    out = GAME / "assets" / "boot_splash.png"
    logo.resize((logo.width * SCALE, logo.height * SCALE), Image.NEAREST).save(out)
    ground = np.asarray(Image.open(GAME / "assets" / "ground.png").convert("RGB"), dtype=float) / 255
    r, g, b = ground.reshape(-1, 3).mean(0)
    print(f"wrote {out}\nboot_splash/bg_color=Color({r:.4f}, {g:.4f}, {b:.4f}, 1)")


if __name__ == "__main__":
    main()
