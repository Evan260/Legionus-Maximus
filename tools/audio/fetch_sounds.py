"""Downloads the CC0 recordings the game's sounds are cut from into tools/audio/downloads/ and writes sources.json.

Run: python tools/audio/fetch_sounds.py
Each recording is the public preview mp3 of a Freesound page, saved as ID.mp3. Only audio files are fetched, and they are
only ever read as data. Every page must say Creative Commons 0, or the run stops.
"""
import html
import json
import re
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
DOWNLOADS = HERE / "downloads"

# Freesound id: author, as in the page address freesound.org/people/AUTHOR/sounds/ID/
SOUNDS = {
    547042: "CogFireStudios", 442769: "qubodup", 426322: "MTJohnson", 334169: "loudernoises", 175949: "freefire66",
    370203: "nekoninja", 792354: "Diasyl", 138489: "JustInvoke",
    394179: "saturdaysoundguy", 263675: "PorkMuncher",
    420670: "SypherZent", 420668: "SypherZent",
    163453: "LeMudCrab", 249810: "spookymodem",
    539956: "adharca", 482686: "jocmusic",
    651646: "Krizin", 267248: "BerlinGameScene",
    486140: "Anuj_Shrestha1", 486141: "Anuj_Shrestha1", 375287: "sgossner", 581467: "johnnydekk",
    547209: "MrFossy", 464486: "elynch0901",
    416839: "tonsil5", 416838: "tonsil5", 554443: "Blankened", 577032: "Blankened",
    347174: "Davidsraba", 350875: "cabled_mess",
    609335: "Kenneth_Cooney", 442943: "qubodup",
    253168: "suntemple", 467951: "benzix2", 546974: "finix473",
    # Boss abilities, felling, building, fire and the gods.
    593875: "igroglaz", 494071: "Kinoton", 342542: "sgrowe", 173941: "JohnsonBrandEditing", 202231: "deraj",
    478238: "Fission9", 803551: "agaisgsbs", 244926: "hnhnh", 260555: "LookIMadeAThing",
    521639: "Fupicat", 877983: "Qvantor", 
    521831: "joelcarrsound", 521832: "joelcarrsound", 346373: "denao270", 399080: "Kinoton", 623130: "Brsjak",
    876169: "Assetsmith", 420677: "SypherZent", 512217: "Mateusz_Chenc", 714257: "qubodup",
    513694: "kasparsj", 350978: "cabled_mess", 621352: "WelvynZPorterSamples", 274121: "bone666138",
    361772: "kingsrow", 840628: "loganzsound", 431851: "nofeedbak",
    431174: "Blankened", 186932: "ReadeOnly", 505063: "olver", 204912: "Noxdl",
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
            sys.exit(f"{sid} is not CC0, remove it from SOUNDS")
        title = html.unescape(re.search(r'data-title="([^"]*)"', text).group(1))
        mp3 = re.search(r'data-mp3="([^"]+)"', text).group(1).replace("-lq.mp3", "-hq.mp3")
        target = DOWNLOADS / f"{sid}.mp3"
        if not target.exists():
            target.write_bytes(get(mp3))
        out[str(sid)] = {"license": "CC0", "author": user, "title": title, "page": page}
        print(sid, title)
    (HERE / "sources.json").write_text(json.dumps(out, indent=1, ensure_ascii=False), encoding="utf8")


if __name__ == "__main__":
    main()
