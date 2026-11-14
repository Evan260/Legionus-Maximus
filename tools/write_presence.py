"""Write tools/steam/rich_presence.vdf from the "presence.*" rows of game/translations/strings.csv, one block per Steam language.

Run tools/extract_strings.py and tools/translate_strings.py first so the rows exist and are translated.
Usage: python tools/write_presence.py
"""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "game" / "translations" / "strings.csv"
VDF = ROOT / "tools" / "steam" / "rich_presence.vdf"
# The game's language code and the name Steam knows the language by.
STEAM = {"en": "english", "fr": "french", "de": "german", "es": "spanish", "it": "italian", "pt_BR": "brazilian",
         "pl": "polish", "tr": "turkish", "ru": "russian", "uk": "ukrainian", "ja": "japanese", "ko": "koreana",
         "zh_CN": "schinese", "zh_TW": "tchinese"}


def main():
    with CSV_PATH.open(encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    header = rows[0]
    tokens = [r for r in rows[1:] if r[0].startswith("presence.")]
    out = ['"lang"', "{"]
    for code, name in STEAM.items():
        col = header.index(code)
        out += [f'\t"{name}"', "\t{", '\t\t"tokens"', "\t\t{"]
        for r in tokens:
            out.append(f'\t\t\t"#{r[0].removeprefix("presence.")}"\t"{r[col].replace(chr(34), chr(39))}"')
        out += ["\t\t}", "\t}"]
    out.append("}")
    VDF.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"{len(tokens)} tokens in {len(STEAM)} languages in {VDF.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
