"""Collect every player-facing string into game/translations/strings.csv for translators.

The scripts wrap their words in tr("...") or TranslationServer.translate("..."); the names the screens look up in their
own tables (the camp's boards, the map's modes, the settings' toggles, the controls' actions) are read from those tables.
The names, texts and histories in game/data/content.json get a key built from the entry, such as
"content.recruits.legionary.name", so a translation does not depend on the English wording.
Existing translations are kept, new strings are added with the English filled in, and rows for text the game no longer
has are dropped.
Usage: python tools/extract_strings.py
"""
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "game"
OUT = ROOT / "translations" / "strings.csv"
WORDS = ["name", "text", "history", "more"]
KINDS = ["recruits", "enemies", "arms", "forged", "drills", "provinces", "commanders", "quartermaster", "achievements"]
# Tables of words that screens look up with tr(entry), as (script, constant name).
TABLES = [("screens/camp.gd", "BOARDS"), ("screens/map.gd", "MODES"), ("screens/settings.gd", "VOLUME_NAMES"),
          ("screens/settings.gd", "TOGGLES"), ("screens/tablinum.gd", "KINDS"), ("controls.gd", "ACTIONS"),
          ("controls.gd", "PAD_NAMES"), ("content.gd", "GROUPS")]
# Words built from ids in code: the mode names, which the camp and the summary capitalise.
EXTRA = ["Hard", "Endless", "Decimatio", "Language", "Automatic"]

CALL = re.compile(r'\b(?:tr|TranslationServer\.translate)\(\s*"((?:[^"\\]|\\.)*)"')
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def unescape(s):
    return s.encode("latin-1", "backslashreplace").decode("unicode_escape")


def from_calls():
    found = []
    for f in sorted((ROOT / "scripts").rglob("*.gd")):
        for m in CALL.finditer(f.read_text(encoding="utf-8")):
            found.append(unescape(m.group(1)))
    return found


def from_tables():
    found = []
    for script, name in TABLES:
        text = (ROOT / "scripts" / script).read_text(encoding="utf-8")
        start = text.index(f"const {name} :=")
        depth, i, seen = 0, text.index("=", start), False
        for j in range(i, len(text)):
            ch = text[j]
            if ch in "[{":
                depth += 1
                seen = True
            elif ch in "]}":
                depth -= 1
            if seen and depth == 0:
                block = text[i:j + 1]
                break
        for m in LITERAL.finditer(block):
            s = unescape(m.group(1))
            # Only the capitalised words are names: the lower-case ones are ids.
            if re.match(r"[A-Z]", s) and re.search(r"[a-z]{2,}", s):
                found.append(s)
    return found


def from_content():
    """The content.json words as {key: English}."""
    data = json.loads((ROOT / "data" / "content.json").read_text(encoding="utf-8"))
    out = {"content.base_commander.name": data["base_commander"]["name"]}
    for kind in KINDS:
        for id_, entry in data[kind].items():
            for field in WORDS:
                if isinstance(entry, dict) and isinstance(entry.get(field), str):
                    out[f"content.{kind}.{id_}.{field}"] = entry[field]
    return out


def from_presence():
    """The English tokens of tools/steam/rich_presence.vdf as {"presence.Status_Camp": English}; write_presence.py writes the other languages back."""
    text = (ROOT.parent / "tools" / "steam" / "rich_presence.vdf").read_text(encoding="utf-8")
    english = text.split('"english"')[1].split("}")[0]
    return {"presence." + k: v for k, v in re.findall(r'"#([A-Za-z_]+)"\s+"([^"]*)"', english)}


def main():
    rows = {}
    languages = ["en"]
    if OUT.exists():
        with OUT.open(encoding="utf-8", newline="") as f:
            reader = csv.reader(f)
            header = next(reader)
            languages = header[1:]
            for r in reader:
                rows[r[0]] = r[1:]
    wanted = {s: s for s in from_calls() + from_tables() + EXTRA}
    wanted.update(from_content())
    wanted.update(from_presence())
    old = rows
    rows = {}
    for key, english in wanted.items():
        row = old.get(key, [""] * len(languages))
        # A changed English text starts that row's translations again.
        if row[0] != english:
            row = [english] + [""] * (len(languages) - 1)
        rows[key] = row
    OUT.parent.mkdir(exist_ok=True)
    with OUT.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["keys"] + languages)
        for key in sorted(rows):
            w.writerow([key] + rows[key])
    print(f"{len(rows)} strings in {OUT.relative_to(ROOT.parent)} for {', '.join(languages)}")


if __name__ == "__main__":
    main()
