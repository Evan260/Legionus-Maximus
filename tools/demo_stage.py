"""Makes the copy of game/ that the demo is exported from, holding only what the demo can show or play.

The demo plays one province (balance.json `demo.province`) and lists the first `demo.commanders` commanders. Its copy
keeps that province with its enemies and the enemies they bring, those commanders, and every recruit, arm, forged form,
drill, god and quartermaster upgrade, all of which the demo offers. The other provinces, their enemies and commanders,
the achievements about them and their translated words are left out of the data, and their pictures out of the atlas,
which build_atlas.py cuts from the atlas as it stands. The tablinum still shows the other enemies as dark shapes, so the atlas
keeps each one's south-facing outline filled with one colour (`glimpses` in content.json). The other provinces' grounds
are left out, and the canal water, the ice and the wheat tile, which the code loads whatever the province, are each
replaced by one clear pixel. data/demo_build.json marks the copy as the demo (Game.DEMO_MARK).

  python tools/demo_stage.py FOLDER     writes the copy to FOLDER/game and imports it, to look at
tools/export.py --demo exports from a copy made in a temporary folder.
"""
import csv
import json
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
sys.path.insert(0, str(ROOT / "tools" / "art"))
KINDS = ["recruits", "enemies", "arms", "forged", "drills", "provinces", "commanders", "quartermaster", "achievements", "gods"]
# Pictures the code loads for any province, which only other provinces draw from.
CLEARED = ["assets/ice.png", "assets/water.png", "assets/wheat_tile.png"]


def available_art(game):
    """The art keys that exist, as Content.available_art() finds them."""
    meta = json.loads((game / "assets" / "atlas.json").read_text(encoding="utf-8"))
    out = {"unit:" + n for n in meta["units"]} | {"prop:" + n for n in meta["props"]}
    out |= {"icon:" + p.stem for p in (game / "assets" / "icons").glob("*.png")}
    out |= {"ground:" + p.stem for p in (game / "assets" / "grounds").glob("*.png")}
    return out


def strings(value):
    if isinstance(value, dict):
        for v in value.values():
            yield from strings(v)
    elif isinstance(value, list):
        for v in value:
            yield from strings(v)
    elif isinstance(value, str):
        yield value


def province_blocks(value, province, provinces):
    """The values that the province-keyed tables in balance.json hold for `province`."""
    if isinstance(value, dict):
        for key, v in value.items():
            if key == province:
                yield v
            elif key not in provinces:
                yield from province_blocks(v, province, provinces)
    elif isinstance(value, list):
        for v in value:
            yield from province_blocks(v, province, provinces)


def default_cover():
    """The props terrain.gd scatters on any ground that has no block of its own in balance.json."""
    text = (GAME / "scripts" / "terrain.gd").read_text(encoding="utf-8")
    return set(re.findall(r'"(\w+)"', re.search(r"const SCATTER := \[(.*?)\]", text).group(1)))


def province_props(content, balance, province, props):
    """The props a province names: its own in content.json, those its blocks in balance.json name, the fort pieces on its
    ground, and the props made from them (hedge_end_left from hedge)."""
    info = content["provinces"][province]
    names = set(info.get("props", [])) | {k[5:] for k in info.get("art", []) if k.startswith("prop:")}
    for block in province_blocks(balance, province, content["provinces"]):
        names |= set(strings(block))
    ground = info.get("fort_ground", "grass")
    if ground != "grass":
        names |= {p for p in props if p.endswith("_" + ground) and p[:-len(ground) - 1] in props}
    names &= set(props)
    return names | {p for p in props for n in names if p.startswith(n + "_")}


def plan(content, balance, art, atlas):
    """What the demo keeps: its content.json, and the units, props and silhouettes of its atlas."""
    demo = balance["demo"]
    province = demo["province"]
    info = content["provinces"][province]
    enemies = set()
    todo = list(info["ordinary"]) + list(info["elites"]) + [info["chieftain"]]
    for block in province_blocks(balance, province, content["provinces"]):
        todo += [s for s in strings(block) if s in content["enemies"]]
    while todo:
        foe = todo.pop()
        if foe in content["enemies"] and foe not in enemies:
            enemies.add(foe)
            todo += [s for s in strings(content["enemies"][foe]) if s in content["enemies"]]
    ready = lambda entry: all(key in art for key in entry.get("art", []))
    # The commanders the full game's demo lists, by the rule of Game.commanders().
    commanders = [c for c, entry in content["commanders"].items() if ready(entry)
                  and ready(content["provinces"].get(entry.get("unlock", {}).get("province", province), {"art": ["?"]}))]
    commanders = commanders[:int(demo["commanders"])]
    for c in commanders:
        if content["commanders"][c].get("unlock", {}).get("province", province) != province:
            sys.exit(f"the demo lists {c}, who is unlocked in a province the demo leaves out")
    kept = dict(content)
    kept["provinces"] = {province: info}
    kept["enemies"] = {id: e for id, e in content["enemies"].items() if id in enemies}
    kept["commanders"] = {id: content["commanders"][id] for id in commanders}
    kept["achievements"] = {id: a for id, a in content["achievements"].items() if achievable(a, kept)}
    kept["glimpses"] = {"enemies": [id for id, e in content["enemies"].items() if id not in enemies and ready(e)]}

    used = {k[5:] for kind in KINDS for e in kept[kind].values() for k in e.get("art", []) if k.startswith("unit:")}
    named = {k[5:] for kind in KINDS for e in content[kind].values() for k in e.get("art", []) if k.startswith("unit:")}
    units = [u for u in atlas["units"] if u in used or u not in named]
    silhouettes = [k[5:] for id in kept["glimpses"]["enemies"] for k in content["enemies"][id]["art"]
                   if k.startswith("unit:") and k[5:] not in units]
    others = set().union(*(province_props(content, balance, p, atlas["props"]) for p in content["provinces"] if p != province))
    left_out = others - province_props(content, balance, province, atlas["props"]) - default_cover()
    props = [p for p in atlas["props"] if p not in left_out]
    return kept, {"units": units, "props": props, "silhouettes": silhouettes}


def achievable(a, kept):
    """Whether an achievement names only what the demo keeps."""
    target = str(a.get("target", ""))
    match a.get("kind"):
        case "province":
            return target in kept["provinces"]
        case "commander" | "commander_win":
            return target in kept["commanders"]
        case "forged":
            return target in kept["forged"]
        case "maxed":
            return a.get("group") in kept
    return True


def trim_balance(value, others):
    """balance.json without the other provinces' entries in its province-keyed tables and lists."""
    if isinstance(value, dict):
        return {k: trim_balance(v, others) for k, v in value.items() if k not in others}
    if isinstance(value, list):
        if value and all(isinstance(v, str) for v in value) and set(value) & others:
            return [v for v in value if v not in others]
        return [trim_balance(v, others) for v in value]
    return value


def trim_strings(path, kept):
    """Drops the translated words of every content entry the demo leaves out."""
    with path.open(encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    keep = [rows[0]]
    for row in rows[1:]:
        parts = row[0].split(".")
        if len(parts) == 4 and parts[0] == "content" and parts[1] in KINDS and parts[2] not in kept[parts[1]]:
            continue
        keep.append(row)
    with path.open("w", encoding="utf-8", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(keep)


def write_json(path, data):
    path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")


def stage(folder, godot):
    """Writes the demo's copy of game/ into folder/game, imports it with `godot` and returns its path."""
    import build_atlas

    project = Path(folder) / "game"
    # The editor's state, whose long file names can pass Windows' path limit, and the phone's Android build template stay behind.
    shutil.copytree(GAME, project, ignore=lambda folder, names: ["editor"] if Path(folder).name == ".godot" else ["android"] if Path(folder) == GAME else [])
    content = json.loads((GAME / "data" / "content.json").read_text(encoding="utf-8"))
    balance = json.loads((GAME / "data" / "balance.json").read_text(encoding="utf-8"))
    atlas = json.loads((GAME / "assets" / "atlas.json").read_text(encoding="utf-8"))
    kept, keep = plan(content, balance, available_art(GAME), atlas)
    others = set(content["provinces"]) - set(kept["provinces"])
    write_json(project / "data" / "content.json", kept)
    write_json(project / "data" / "balance.json", trim_balance(balance, others))
    write_json(project / "data" / "demo_build.json", {"province": balance["demo"]["province"]})
    build_atlas.cut(keep, project / "assets")
    for ground in (project / "assets" / "grounds").glob("*.png"):
        if ground.stem not in kept["provinces"]:
            ground.unlink()
            ground.with_suffix(".png.import").unlink()
    for path in CLEARED:
        build_atlas.Image.new("RGBA", (1, 1)).save(project / path)
    trim_strings(project / "translations" / "strings.csv", kept)
    presets = project / "export_presets.cfg"
    # The copy lies outside the repo, so paths beside game/ (the Windows template) are given in full.
    text = re.sub(r'="(\.\./[^"]*)"', lambda m: '="%s"' % (GAME / m.group(1)).resolve().as_posix(), presets.read_text(encoding="utf-8"))
    presets.write_text(text, encoding="utf-8", newline="\n")
    for args, what in ((["--import"], "importing the demo's copy"),
                       (["--script", "res://tools/demo_props.gd"], "checking the demo's copy has the pictures it needs")):
        result = subprocess.run([godot, "--headless", "--path", str(project), *args], capture_output=True, text=True,
                                encoding="utf-8", errors="replace")
        if result.returncode != 0 or "ERROR:" in result.stdout + result.stderr:
            sys.exit(f"{what} failed:\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
    return project


@contextmanager
def staged(godot):
    """The demo's copy of game/ in a temporary folder, removed afterwards."""
    folder = tempfile.mkdtemp(prefix="lm-demo-")
    try:
        yield stage(folder, godot)
    finally:
        shutil.rmtree(folder, ignore_errors=True)


if __name__ == "__main__":
    import export

    if len(sys.argv) != 2 or Path(sys.argv[1]).joinpath("game").exists():
        sys.exit("usage: python tools/demo_stage.py FOLDER (FOLDER/game must not exist yet)")
    print(stage(sys.argv[1], export.GODOT))
