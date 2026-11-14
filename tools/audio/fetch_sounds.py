"""Downloads the CC0 recordings the game's sounds are cut from into tools/audio/downloads/ and writes sources.json.

Run: python tools/audio/fetch_sounds.py
Each recording is the public preview mp3 of a Freesound page, saved as ID.mp3. Only audio files are fetched, and they are
only ever read as data. Every page is checked to say Creative Commons 0 before its preview is kept.
"""
import html
import json
import re
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
DOWNLOADS = HERE / "downloads"

# Freesound id: author, as in the page address freesound.org/people/AUTHOR/sounds/ID/
SOUNDS = {
    547042: "CogFireStudios", 442769: "qubodup", 426322: "MTJohnson", 334169: "loudernoises", 175949: "freefire66",
    370203: "nekoninja", 792354: "Diasyl", 138489: "JustInvoke",
    394179: "saturdaysoundguy", 263675: "PorkMuncher",
    420670: "SypherZent", 420668: "SypherZent", 394004: "DigPro120",
    163453: "LeMudCrab", 249810: "spookymodem",
    539956: "adharca", 482686: "jocmusic",
    651646: "Krizin", 267248: "BerlinGameScene",
    486140: "Anuj_Shrestha1", 486141: "Anuj_Shrestha1", 375287: "sgossner", 345635: "cabled_mess", 581467: "johnnydekk",
    547209: "MrFossy", 464486: "elynch0901",
    416839: "tonsil5", 416838: "tonsil5", 554443: "Blankened", 577032: "Blankened",
    347174: "Davidsraba", 350875: "cabled_mess",
    609335: "Kenneth_Cooney", 442943: "qubodup",
    253168: "suntemple", 467951: "benzix2", 546974: "finix473",
    # The VSCO 2 CE harp notes the calm music is played from, the same ones the other games use.
    373556: "sgossner", 373559: "sgossner", 373560: "sgossner", 373563: "sgossner", 373565: "sgossner",
    373566: "sgossner", 373568: "sgossner", 373570: "sgossner", 373571: "sgossner", 373573: "sgossner",
}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=60).read()


def main():
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    out = {}
    for sid, user in SOUNDS.items():
        page = f"https://freesound.org/people/{user}/sounds/{sid}/"
        text = get(page).decode("utf8", "replace")
        if "Creative Commons 0" not in text and "publicdomain/zero" not in text:
            print(f"{sid}: not CC0, skipped")
            continue
        title = html.unescape(re.search(r'data-title="([^"]*)"', text).group(1))
        mp3 = re.search(r'data-mp3="([^"]+)"', text).group(1).replace("-lq.mp3", "-hq.mp3")
        target = DOWNLOADS / f"{sid}.mp3"
        if not target.exists():
            target.write_bytes(get(mp3))
        out[str(sid)] = {"author": user, "title": title, "page": page}
        print(sid, title)
    (HERE / "sources.json").write_text(json.dumps(out, indent=1, ensure_ascii=False), encoding="utf8")


if __name__ == "__main__":
    main()
