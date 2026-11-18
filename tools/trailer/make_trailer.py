"""Make the Steam trailer: record each staged shot in movie mode, then cut them together with the captions, the end card
and the game's own music, all in Godot, and keep an .mp4 copy beside the .avi.

Usage:
  python tools/trailer/make_trailer.py              records any shot not yet recorded, then renders the trailer
  python tools/trailer/make_trailer.py shots horde  records just those shots again
  python tools/trailer/make_trailer.py render       renders from the shots already recorded
  python tools/trailer/make_trailer.py render 40    renders a preview from 40 seconds in, into recordings/content/
  python tools/trailer/make_trailer.py stills DIR   records any missing shot, then saves into DIR a contact sheet of
                                                    one frame per segment of the edit and the end card at 1920x1080

The finished trailer goes to marketing/recordings/videos/steam_trailer/, beside its title, description and thumbnail;
the shot frames it is cut from, at the game's own 640 by 360, are kept in marketing/recordings/content/trailer_shots/, so a change to the edit renders
again in a minute or two. Both are kept out of git. Every shot is the game playing itself with its own look flags,
staged further by game/tools/trailer/shots.gd; the edit, with its captions and music, is game/tools/trailer/edit.gd.
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VIDEOS = ROOT / "marketing" / "recordings" / "videos"
WORK = ROOT / "marketing" / "recordings" / "content"
FPS = 30
SIZE = (1920, 1080)
GODOT = (Path.home() / "AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
         / "Godot_v4.7.2-stable_win64_console.exe")
FFMPEG = (Path.home() / "AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe"
          / "ffmpeg-9.0.2-full_build/bin/ffmpeg.exe")
LOOK = ["--autoplay", "--no-save", "--seed=7"]
# The legion's newer recruits, given beside --men's legionaries and archers so the later shots show a mixed legion.
MIXED = "slinger:2,cavalry:2,ballista:1,centurion:1"
LARGE = "slinger:4,cavalry:4,ballista:2,centurion:2,standard_bearer:1,medicus:1"
# name: (seconds to record, the second a quick screenshot of it is taken at, its look flags). The edit takes its part of each from
# edit.gd; a shot runs a moment before the part that is used, so the field has settled.
SHOTS = {
    "skirmish": (8, 3.0, [*LOOK, "--trailer-shot=skirmish", "--men=8"]),
    "levelup": (7, 2.5, [*LOOK, "--trailer-shot=levelup", "--men=8"]),
    "archers": (8, 3.0, [*LOOK, "--trailer-shot=archers", "--men=4:legionary", "--give=archer:3,slinger:4,ballista:2"]),
    "fell": (9, 5.0, [*LOOK, "--trailer-shot=fell", "--men=14", f"--give={MIXED}"]),
    "bridge": (8, 3.0, [*LOOK, "--trailer-shot=bridge", "--men=14", f"--give={MIXED}", "--go-to=bridge"]),
    "whirl": (8, 1.0, [*LOOK, "--trailer-shot=whirl", "--men=10", f"--give={MIXED}", "--boss=berserker", "--boss-act=whirl"]),
    "onrush": (9, 1.5, [*LOOK, "--trailer-shot=onrush", "--province=dacia", "--men=20", f"--give={MIXED}", "--boss=falx_band",
                        "--boss-act=onrush"]),
    "ravine": (8, 1.5, [*LOOK, "--trailer-shot=ravine", "--men=24", f"--give={MIXED}", "--go-to=ravine", "--boss=berserker",
                        "--boss-act=fall"]),
    "hold": (8, 3.0, [*LOOK, "--trailer-shot=hold", "--province=parthia", "--men=30", f"--give={LARGE},onager:2",
                      "--boss=war_elephant", "--boss-act=trample"]),
    "field": (8, 3.0, [*LOOK, "--trailer-shot=field", "--province=gaul", "--men=40", f"--give={LARGE}", "--go-to=field"]),
    "gods": (7, 2.5, [*LOOK, "--trailer-shot=gods", "--province=dacia", "--men=30", f"--give={LARGE}", "--god=choose", "--god-at=1"]),
    "reveal": (8, 2.6, [*LOOK, "--trailer-shot=reveal", f"--give={LARGE}", "--go-to=crowd", "--god=jupiter", "--god-at=2"]),
    "fort": (11, 3.0, [*LOOK, "--trailer-shot=fort", "--province=britannia", "--men=50", f"--give={LARGE}", "--go-to=fort"]),
    "map": (6, 2.0, ["--no-save", "--trailer-shot=map", "--screen=map"]),
    "endcard": (9, 3.0, [*LOOK, "--trailer-shot=endcard", "--province=gaul", "--men=85", f"--give={LARGE}", "--go-to=field"]),
}
SHOTS_DIR = WORK / "trailer_shots"
OUT = VIDEOS / "steam_trailer" / "steam_trailer.avi"


def godot(args, size=SIZE, full=False):
    """Runs Godot in a window of the given size. Movie mode records the game's own 640 by 360 view, which the edit
    scales up by whole pixels; with `full` the view is the whole window, so the edit itself is recorded at full size."""
    override = ROOT / "game" / "override.cfg"
    if override.exists():
        sys.exit(f"{override} already exists; move it aside first")
    view = (f"window/size/viewport_width={size[0]}\nwindow/size/viewport_height={size[1]}\nwindow/stretch/mode=\"disabled\"\n"
            if full else "")
    override.write_text(f"[display]\n\nwindow/size/window_width_override={size[0]}\nwindow/size/window_height_override={size[1]}\n{view}\n"
                        "[editor]\n\nmovie_writer/mjpeg_quality=0.95\n")
    try:
        subprocess.run([str(GODOT), "--path", str(ROOT / "game"), *args], check=True)
    finally:
        override.unlink()


def record(name):
    folder = SHOTS_DIR / name
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    seconds, _, flags = SHOTS[name]
    # A .png movie is written as numbered frames with the sound beside them in a .wav of the same name.
    godot(["--write-movie", str(folder / "f.png"), "--fixed-fps", str(FPS), "--quit-after", str(seconds * FPS), "--", *flags])


def render(start=0.0):
    """Renders the trailer, or with a start time a preview from that moment on into the work folder."""
    out = WORK / "preview.avi" if start else OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    # The edit quits when it ends; the frame limit only stops a run whose script failed to load from going on forever.
    godot(["--write-movie", str(out), "--fixed-fps", str(FPS), "--quit-after", str(200 * FPS), "res://tools/trailer/edit.tscn",
           "--", "--no-save", f"--shots={SHOTS_DIR}", f"--from={start}"], full=True)
    if not start:
        mp4_copy(out)
        thumbnail(out.parent / "thumbnail.png")
    print(f"ready: {out}")


def mp4_copy(avi):
    """Writes an .mp4 beside the .avi: about a tenth of its size, and the format Steam wants, with its sound brought to
    the loudness video sites play at. Skipped without ffmpeg."""
    if not FFMPEG.exists():
        print("no ffmpeg, so no .mp4 copy")
        return
    subprocess.run([str(FFMPEG), "-y", "-loglevel", "error", "-i", str(avi), "-c:v", "libx264", "-preset", "slow", "-crf", "16",
                    "-pix_fmt", "yuv420p", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "48000", "-c:a", "aac", "-b:a", "192k",
                    "-movflags", "+faststart", str(avi.with_suffix(".mp4"))], check=True)


def edit_frame(at, out):
    """Renders a moment of the trailer from the recorded shots and keeps it as a still."""
    tmp = WORK / "still"
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)
    godot(["--write-movie", str(tmp / "e.png"), "--fixed-fps", str(FPS), "--quit-after", "2", "res://tools/trailer/edit.tscn",
           "--", "--no-save", f"--shots={SHOTS_DIR}", f"--from={at}"], full=True)
    shutil.copy(sorted(tmp.glob("e*.png"))[-1], out)


def cut_list():
    """The edit's segments as (label, start, length) in seconds, read from edit.gd's cut list."""
    import re
    text = (ROOT / "game" / "tools" / "trailer" / "edit.gd").read_text(encoding="utf-8")
    beat = float(re.search(r"const BEAT := ([\d.]+)", text).group(1))
    cut = text.split("const TRAILER := [", 1)[1].split("\n]", 1)[0]
    out = []
    frame = 0
    for m in re.finditer(r'\{"(card|shot|end)": "((?:[^"\\]|\\.)*)".*?"beats": ([\d.]+)', cut):
        frames = round(float(m.group(3)) * beat * FPS)
        label = m.group(2).replace(r"\n", " ") if m.group(1) == "card" else m.group(2)
        out.append((label, frame / FPS, frames / FPS))
        frame += frames
    return out


def thumbnail(out):
    label, start, length = cut_list()[-1]
    edit_frame(start + 4.0, out)


def stills(folder):
    """Records any shot not yet recorded, then saves a contact sheet of one frame from the middle of every segment of
    the edit, as the trailer will show it, and the end card at full size."""
    from PIL import Image, ImageDraw
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    for shot in SHOTS:
        if not (SHOTS_DIR / shot / "f.wav").exists():
            record(shot)
    segments = cut_list()
    cols, w, h = 4, 640, 360
    rows = (len(segments) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, rows * (h + 24)), (20, 16, 14))
    draw = ImageDraw.Draw(sheet)
    for i, (label, start, length) in enumerate(segments):
        # The end card is shown once it has settled; every other segment at its middle.
        at = start + (4.0 if i == len(segments) - 1 else length / 2.0)
        frame = folder / f"seg_{i + 1:02d}.png"
        edit_frame(at, frame)
        x, y = (i % cols) * w, (i // cols) * (h + 24)
        sheet.paste(Image.open(frame).convert("RGB").resize((w, h), Image.LANCZOS), (x, y + 24))
        draw.text((x + 6, y + 5), f"{i + 1}. {label}   {start:.1f}s + {length:.1f}s", fill=(240, 220, 160))
    sheet.save(folder / "contact_sheet.png")
    shutil.copy(folder / f"seg_{len(segments):02d}.png", folder / "end_card.png")


def main():
    args = sys.argv[1:]
    if args[:1] == ["stills"]:
        stills(args[1])
        return
    if args[:1] == ["shots"]:
        for shot in args[1:] or SHOTS:
            record(shot)
        return
    if args[:1] != ["render"]:
        for shot in SHOTS:
            if not (SHOTS_DIR / shot / "f.wav").exists():
                record(shot)
    render(float(args[1]) if args[:1] == ["render"] and len(args) > 1 else 0.0)


if __name__ == "__main__":
    main()
