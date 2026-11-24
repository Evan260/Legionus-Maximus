"""Fails when a demo build holds another province's pictures or data, which would let a player who edits the build's
feature tags play the full game.

  python tools/check_demo.py "builds/windows-demo/Legionus Maximus Demo.exe"

Takes the demo's .exe, .x86_64, .pck or macOS .zip. What belongs to another province comes from the full game's
content.json: its ground, its ordinary enemies, elites and chieftain (only their one-colour outline may be in the atlas,
for the tablinum), the props it names and the fort pieces on its ground. tools/export.py runs this after every demo export.
"""
import io
import json
import re
import struct
import sys
import zipfile
from pathlib import Path

import numpy as np

import demo_stage

GAME = Path(__file__).resolve().parents[1] / "game"


def pck_of(path):
    """The bytes of the Godot pack in a build, embedded in its executable or on its own."""
    path = Path(path)
    if path.suffix == ".zip":
        with zipfile.ZipFile(path) as z:
            for name in z.namelist():
                if name.endswith(".pck") or "/Contents/MacOS/" in name and not name.endswith("/"):
                    data = z.read(name)
                    if data[:4] == b"GDPC" or data[-4:] == b"GDPC":
                        return pck_of_bytes(data)
        sys.exit(f"{path}: no Godot pack inside")
    return pck_of_bytes(path.read_bytes())


def pck_of_bytes(data):
    if data[:4] == b"GDPC":
        return data
    if data[-4:] != b"GDPC":
        sys.exit("no Godot pack in the build")
    start = len(data) - 12 - struct.unpack("<Q", data[-12:-4])[0]
    while data[start:start + 4] != b"GDPC":
        start -= 1
    return data[start:]


def files_of(pck):
    """Each file in the pack by its res:// path, as a function returning its bytes."""
    version, _, _, _, _, base, directory = struct.unpack("<IIIIIQQ", pck[4:40])
    if version < 3:
        sys.exit(f"pack format {version} is older than this check reads")
    count = struct.unpack("<I", pck[directory:directory + 4])[0]
    q = directory + 4
    out = {}
    for _ in range(count):
        n = struct.unpack("<I", pck[q:q + 4])[0]
        name = pck[q + 4:q + 4 + n].rstrip(b"\0").decode("utf-8")
        offset, size = struct.unpack("<QQ", pck[q + 4 + n:q + 20 + n])
        q += 4 + n + 16 + 16 + 4
        out[name.removeprefix("res://")] = lambda at=base + offset, size=size: pck[at:at + size]
    return out


def picture_in(ctex):
    """The image inside an imported texture, stored as a PNG or a lossless WebP."""
    from PIL import Image

    for magic in (b"\x89PNG", b"RIFF"):
        at = ctex.find(magic)
        if at >= 0:
            return Image.open(io.BytesIO(ctex[at:])).convert("RGBA")
    return None


def problems(files):
    content = json.loads((GAME / "data" / "content.json").read_text(encoding="utf-8"))
    balance = json.loads((GAME / "data" / "balance.json").read_text(encoding="utf-8"))
    demo = balance["demo"]["province"]
    others = [p for p in content["provinces"] if p != demo]
    out = [f"{name} is missing" for name in ("data/content.json", "assets/atlas.json", "data/demo_build.json") if name not in files]
    if "data/content.json" not in files or "assets/atlas.json" not in files:
        return out
    built = json.loads(files["data/content.json"]())
    atlas = json.loads(files["assets/atlas.json"]())
    for name in files:
        for p in others:
            if re.search(rf"(^|/){p}\.png", name):
                out.append(f"{p}'s ground is in the build: {name}")
    for p in others:
        if p in built["provinces"]:
            out.append(f"{p} is in content.json")
    own = lambda p: {p["chieftain"], *p["ordinary"], *p["elites"]}
    mine = own(content["provinces"][demo])
    for e in mine.copy():
        mine |= {s for s in demo_stage.strings(content["enemies"].get(e, {})) if s in content["enemies"]}
    foes = set().union(*(own(content["provinces"][p]) for p in others)) - mine
    for e in sorted(foes):
        if e in built["enemies"]:
            out.append(f"{e} is in content.json")
        unit = atlas["units"].get(e)
        if unit and (list(unit) != ["idle"] or list(unit["idle"]) != ["south"] or len(unit["idle"]["south"]["frames"]) != 1):
            out.append(f"{e} has more than its outline in the atlas")
    def signature(p):
        info = content["provinces"][p]
        return set(info.get("props", [])) | {k[5:] for k in info.get("art", []) if k.startswith("prop:")}

    props = set().union(*(signature(p) for p in others)) - signature(demo) - demo_stage.default_cover()
    ground = lambda p: content["provinces"][p].get("fort_ground", "grass")
    grounds = {ground(p) for p in others} - {ground(demo)}
    for prop in sorted(atlas["props"]):
        if prop in props or any(prop.endswith("_" + g) for g in grounds):
            out.append(f"another province's {prop} is in the atlas")
    out += outlines_problems(files, atlas, foes)
    return out


def outlines_problems(files, atlas, foes):
    """Every other province's enemy left in the atlas must be a shape of one colour, with nothing of its picture inside."""
    imported = re.search(r'path="res://([^"]+)"', files["assets/atlas.png.import"]().decode("utf-8")).group(1)
    image = picture_in(files[imported]())
    if image is None:
        return ["the atlas's picture could not be read from the build"]
    out = []
    for e in sorted(foes & set(atlas["units"])):
        x, y, w, h = atlas["units"][e]["idle"]["south"]["frames"][0]
        cell = np.asarray(image.crop((x, y, x + w, y + h)))
        if len(np.unique(cell[cell[..., 3] > 0][:, :3], axis=0)) > 1:
            out.append(f"{e}'s outline in the atlas shows more than one colour")
    return out


def check(path):
    """Exits with every problem found in the demo build at path."""
    found = problems(files_of(pck_of(path)))
    if found:
        sys.exit(f"{path} holds more than the demo:\n  " + "\n  ".join(found))
    print(f"checked {path}: only the demo's pictures and data")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    check(sys.argv[1])
