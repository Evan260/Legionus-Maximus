"""Generate a PixelLab Wang tileset of two terrains and save each tile with its corner pattern.

Usage: python tools/art/make_tileset.py "lower terrain" "upper terrain" --size 32 --out-dir art_test/raw/tiles
"""
import argparse
import json
import time
from pathlib import Path

import urllib.error
import urllib.request

import pixellab as pl


def fetch(tid):
    """Waits for the tileset, since the server answers 423 until it is drawn."""
    for _ in range(90):
        req = urllib.request.Request(f"{pl.API}/tilesets/{tid}", headers={"Authorization": f"Bearer {pl.token()}"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code != 423:
                raise
        time.sleep(10)
    raise SystemExit("tileset timed out")

p = argparse.ArgumentParser()
p.add_argument("lower")
p.add_argument("upper")
p.add_argument("--transition", default="")
p.add_argument("--size", type=int, default=32)
p.add_argument("--out-dir", required=True)
p.add_argument("--existing", help="fetch a tileset already made instead of making a new one")
a = p.parse_args()

before = pl.balance()
r = {"tileset_id": a.existing} if a.existing else pl.call("POST", "/create-tileset", {
    "lower_description": a.lower, "upper_description": a.upper, "transition_description": a.transition,
    "tile_size": {"width": a.size, "height": a.size}, "transition_size": 0.0,
    "lower_walkable": True, "upper_walkable": True})
tid = r.get("tileset_id") or r.get("id")
out = pl.ROOT / a.out_dir
out.mkdir(parents=True, exist_ok=True)
t = fetch(tid)
tiles = t.get("tiles") or t["tileset"]["tiles"]
meta = []
for i, tile in enumerate(tiles):
    img = tile.get("image", {})
    pl.save_b64(img.get("base64") if isinstance(img, dict) else img, out / f"tile_{i:02d}.png")
    meta.append({"file": f"tile_{i:02d}.png", "corners": tile.get("corners"), "name": tile.get("name")})
(out / "tiles.json").write_text(json.dumps({"tileset_id": tid, "tiles": meta}, indent=2))
pl.record("tileset", a.out_dir, before, pl.balance())
