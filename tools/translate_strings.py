"""Fill in the game's translations with Azure AI Translator, the same service the other Slow Sunday games use.

Reads game/translations/strings.csv (one row per string, its key first and the English second, then one column per language), sends only the empty
cells to Azure, and writes the answers back, saving after each language so an interrupted run loses nothing.
Placeholders such as %s, %d, %.1f and {name} are shielded so they come back exactly as they went in.

After translating, the hand-checked cells in tools/translation_fixes.json are written over the machine's, and its
glossary keeps names such as the gods' in the form each language uses for them.

Usage:
    python tools/translate_strings.py                    every language below
    python tools/translate_strings.py --languages fr,ja  just those
    python tools/translate_strings.py --dry-run          count what is missing and what it would cost, send nothing
    python tools/translate_strings.py --redo fr          clear one language's cells first, then translate it afresh
    add --yes to skip the cost confirmation

The key comes from AZURE_TRANSLATOR_KEY and AZURE_TRANSLATOR_REGION (default "canadacentral"), set in the shell or in
the git-ignored .env at the repository root. Azure's free tier covers 2 million characters a month; one full run of
every language is far under that. Run tools/extract_strings.py first so new strings are in the sheet, then reimport
the project in Godot so each column becomes a translation file.
"""
import csv
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "game" / "translations" / "strings.csv"
FIXES_PATH = ROOT / "tools" / "translation_fixes.json"
ENDPOINT = "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=en&to={to}&textType=html"
# Godot's locale code for each column, and the code Azure knows the language by.
LANGUAGES = {
    "fr": "fr", "de": "de", "es": "es", "it": "it", "pt_BR": "pt", "pl": "pl", "tr": "tr", "ru": "ru", "uk": "uk",
    "ja": "ja", "ko": "ko", "zh_CN": "zh-Hans", "zh_TW": "zh-Hant",
}
# Azure takes at most 100 texts and 10,000 characters a request; staying under both leaves room for the shielding.
MAX_TEXTS, MAX_CHARS = 50, 9000
USD_PER_MILLION = 10.0
# Godot's own format codes, so a percent sign in a sentence such as "95% or more" is translated as words.
# Runs of spaces (the gaps between key hints) and the Latin terms the game keeps in every language.
PLACEHOLDER = re.compile(r"%[a-z]+%|%[-0-9.]*[sdifxXcv%]|\{[A-Za-z0-9_]*\}| {2,}|[Tt]estudo|Decimatio|Tablinum|Steam|Space|Esc|WASD|A / D|R / Y|B / X")
# Godot's % operator fills these in order, so a translation must keep them in the English order.
PERCENT = re.compile(r"%[-0-9.]*[sdifxXcv]")
# Named fields, which format() fills by name, so a translation may move them but must keep every one.
FIELDS = re.compile(r"\{[A-Za-z0-9_]*\}")
# The English a short word is sent as, where on its own the translator picks the wrong sense (Arms as body parts).
HINTS = {
    "Arms": "Weapons", "Forged": "Forged weapon", "Drill": "Military training", "Banked": "Total saved in the bank",
    "Title": "Main menu", "Hold!": "Hold the line!", "Recruit": "Soldier recruit", "Max": "Maximum rank",
    "Camp": "Army camp", "Legion": "Roman legion", "New": "New upgrade", "Free": "Free (nothing to unlock)",
    "Pause": "Pause button", "Back": "Back (previous screen)", "Start": "Start button", "Confirm": "Confirm button",
    "March": "Set off (start the run)",
    "March up": "Move the legion up", "March down": "Move the legion down", "March left": "Move the legion left",
    "March right": "Move the legion right", "Resume": "Resume the game", "Settings": "Settings (game options)",
    "Paused": "Game paused", "Easy": "Easy difficulty", "Medium": "Medium difficulty", "Hard": "Hard difficulty mode", "Endless": "Endless mode", "Endless %s": "Endless mode %s",
    "Endless  +%d:%02d": "Endless mode  +%d:%02d", "Hard won": "Hard mode won", "Hard not won": "Hard mode not won",
    "Won": "Won (victory)", "Not won": "Not won (no victory)", "On": "Switched on", "Off": "Switched off",
    "Chosen": "Selected", "Master volume": "Overall sound volume", "Effects volume": "Sound effects volume",
    "Large": "Large text", "Normal": "Normal text", "Press...": "Press a key...", "Kills": "Enemies killed",
    "Kills %d": "Kills: %d", "Legion %d": "Legion: %d", "Time": "Elapsed time", "Level": "Experience level",
    "Largest %d": "Largest: %d", "Give up the run": "Give up this run", "The camp": "The army camp",
    "Automatic": "Automatic language", "Demo": "Demo version", "Marching here": "Currently marching here",
    "Defeat %d barbarians in total": "Defeat a total of %d barbarians", "Win in %s": "Win a victory in %s",
    "Win in every province": "Win a victory in every province", "Win here to open Endless and Decimatio": "Win in this province to unlock Endless and Decimatio",
    "Dpad up": "D-pad up button", "Dpad down": "D-pad down button", "Dpad left": "D-pad left button", "Dpad right": "D-pad right button",
    "Reroll": "Reroll the choices", "Banish": "Banish a choice",
}


def read_env():
    env = ROOT / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def load_fixes():
    return json.loads(FIXES_PATH.read_text(encoding="utf-8")) if FIXES_PATH.exists() else {"glossary": {}, "fixes": {}}


def glossary_pattern(glossary, lang):
    terms = sorted((t for t, forms in glossary.items() if lang in forms), key=len, reverse=True)
    return re.compile(r"\b(" + "|".join(re.escape(t) for t in terms) + r")\b") if terms else None


def shield(text, lang="", glossary=None):
    """The text as HTML, with each placeholder wrapped so the translator leaves it alone and each glossary name already in the language's own form."""
    glossary = glossary or {}
    names = glossary_pattern(glossary, lang)
    parts, last = [], 0
    for m in PLACEHOLDER.finditer(text):
        parts.append(shield_names(text[last:m.start()], lang, glossary, names))
        parts.append(f'<span class="notranslate">{html.escape(m.group(0), quote=False)}</span>')
        last = m.end()
    parts.append(shield_names(text[last:], lang, glossary, names))
    return "".join(parts)


def shield_names(text, lang, glossary, names):
    if names is None:
        return html.escape(text, quote=False)
    parts, last = [], 0
    for m in names.finditer(text):
        parts.append(html.escape(text[last:m.start()], quote=False))
        parts.append(f'<span class="notranslate">{html.escape(glossary[m.group(0)][lang], quote=False)}</span>')
        last = m.end()
    parts.append(html.escape(text[last:], quote=False))
    return "".join(parts)


def apply_fixes(header, rows, fixes):
    """Writes the hand-checked cells over the sheet. A fix whose English no longer matches the sheet, or a cell that would break a
    format call, is reported and skipped, keeping the machine's translation."""
    by_key = {r[0]: r for r in rows}
    for key, cells in fixes.items():
        row = by_key.get(key)
        if row is None:
            print(f"  fix for {key!r} has no row in the sheet")
            continue
        if cells.get("en", row[1]) != row[1]:
            print(f"  fix for {key!r} was written for other English; check it")
            continue
        for lang, text in cells.items():
            if lang != "en" and lang in header:
                if PERCENT.findall(text) != PERCENT.findall(row[1]):
                    print(f"  fix for {key!r} in {lang} has its % codes out of the English order; skipped, check it")
                    continue
                if sorted(FIELDS.findall(text)) != sorted(FIELDS.findall(row[1])):
                    print(f"  fix for {key!r} in {lang} has other {{fields}} than the English; skipped, check it")
                    continue
                row[header.index(lang)] = text


def unshield(text):
    text = re.sub(r'<span class="notranslate">(.*?)</span>', r"\1", text)
    return html.unescape(text)


def batches(texts):
    batch, size = [], 0
    for t in texts:
        if batch and (len(batch) >= MAX_TEXTS or size + len(t) > MAX_CHARS):
            yield batch
            batch, size = [], 0
        batch.append(t)
        size += len(t)
    if batch:
        yield batch


def translate(batch, to, key, region):
    body = json.dumps([{"Text": t} for t in batch]).encode("utf-8")
    for attempt in range(6):
        req = urllib.request.Request(ENDPOINT.format(to=to), data=body, method="POST", headers={
            "Ocp-Apim-Subscription-Key": key, "Ocp-Apim-Subscription-Region": region,
            "Content-Type": "application/json; charset=UTF-8"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return [item["translations"][0]["text"] for item in json.load(r)]
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise SystemExit(f"Azure answered {e.code}: {e.read().decode('utf-8', 'replace')[:300]}")
            wait = float(e.headers.get("Retry-After") or min(120, 5 * 2 ** attempt))
            print(f"  busy, waiting {wait:.0f} s")
            time.sleep(wait)
    raise SystemExit("Azure stayed busy; try again later")


def load():
    with CSV_PATH.open(encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    return rows[0], rows[1:]


def save(header, rows):
    with CSV_PATH.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    args = sys.argv[1:]
    wanted = list(LANGUAGES)
    if "--languages" in args:
        wanted = args[args.index("--languages") + 1].split(",")
        unknown = [w for w in wanted if w not in LANGUAGES]
        if unknown:
            raise SystemExit(f"Unknown language {unknown}; choose from {', '.join(LANGUAGES)}")
    header, rows = load()
    for lang in wanted:
        if lang not in header:
            header.append(lang)
            for r in rows:
                r.append("")
    for r in rows:
        r.extend([""] * (len(header) - len(r)))
    if "--redo" in args:
        redo = args[args.index("--redo") + 1]
        col = header.index(redo)
        for r in rows:
            r[col] = ""
    fixes = load_fixes()
    todo = {lang: [r for r in rows if not r[header.index(lang)].strip()] for lang in wanted}
    chars = sum(len(r[1]) for missing in todo.values() for r in missing)
    for lang, missing in todo.items():
        print(f"{lang:6} {len(missing):4} strings to translate")
    print(f"{chars:,} characters, about ${chars / 1e6 * USD_PER_MILLION:.2f} at Azure's paid rate (free within 2M a month)")
    if "--dry-run" in args:
        return
    if chars == 0:
        apply_fixes(header, rows, fixes["fixes"])
        save(header, rows)
        return
    read_env()
    key = os.environ.get("AZURE_TRANSLATOR_KEY")
    if not key:
        raise SystemExit("Set AZURE_TRANSLATOR_KEY (and AZURE_TRANSLATOR_REGION) in the shell or in .env first")
    region = os.environ.get("AZURE_TRANSLATOR_REGION", "canadacentral")
    if "--yes" not in args and input("Translate now? [y/N] ").strip().lower() != "y":
        return
    for lang, missing in todo.items():
        if not missing:
            continue
        col = header.index(lang)
        done = 0
        for batch in batches(missing):
            answers = translate([shield(HINTS.get(r[0], r[1]), lang, fixes["glossary"]) for r in batch], LANGUAGES[lang], key, region)
            for r, a in zip(batch, answers):
                r[col] = unshield(a)
            done += len(batch)
            print(f"  {lang}: {done}/{len(missing)}")
        save(header, rows)
        # A placeholder that did not survive would show raw or crash a format call, so it is cleared to be redone.
        for r in missing:
            if sorted(PLACEHOLDER.findall(r[1])) != sorted(PLACEHOLDER.findall(r[col])):
                print(f"  {lang}: placeholders changed in {r[1]!r} -> {r[col]!r}; left empty")
                r[col] = ""
            elif PERCENT.findall(r[1]) != PERCENT.findall(r[col]):
                print(f"  {lang}: % codes reordered in {r[1]!r} -> {r[col]!r}; left empty (use named {{fields}} where the order must change)")
                r[col] = ""
        save(header, rows)
    apply_fixes(header, rows, fixes["fixes"])
    save(header, rows)
    print("Done. Reimport the project in Godot so every language column becomes a translation file.")


if __name__ == "__main__":
    main()
