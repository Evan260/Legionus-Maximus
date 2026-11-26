"""Make the Steam trailer, the Google Play listing's video and the vertical shorts for YouTube Shorts, Reels and TikTok:
record each staged shot in movie mode, then cut them together with the captions, the end card and the game's own music,
all in Godot, and keep an .mp4 copy beside the .avi.

Usage:
  python tools/trailer/make_trailer.py              records any shot not yet recorded, then renders the trailer
  python tools/trailer/make_trailer.py shots horde  records just those shots again
  python tools/trailer/make_trailer.py render       renders from the shots already recorded
  python tools/trailer/make_trailer.py render 40    renders a preview from 40 seconds in, into recordings/content/
  python tools/trailer/make_trailer.py stills DIR   records any missing shot, then saves into DIR a contact sheet of
                                                    one frame per segment of the edit and the end card at 1920x1080
  Add --cut=play_store to the first four for the Google Play video, whose shots, named in PHONE_SHOTS, are recorded
  with the phone's touch controls (--phone) into marketing/recordings/content/phone_shots/.
  Add --cut=NAME to the first four for one of the shorts named in SHORTS, whose shots, in SHORT_SHOTS, are recorded in a
  tall 360 by 640 view into marketing/recordings/content/short_shots/. Each short goes to its own folder as an .avi, an
  .mp4 with the App Store and Google Play badges on its end card and a _steam_only.mp4 without them, all at the Google
  Play video's loudness, beside a thumbnail.

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
MIXED = "archer:2,cavalry:2,ballista:1,centurion:1"
LARGE = "archer:4,cavalry:4,ballista:2,centurion:2,standard_bearer:1,medicus:1"


def province(name, go_to, hud, march):
    """A shot for the provinces' run of quick cuts: a large legion in gold marching through a ring of the province's own
    barbarians, beside the province's own scenery when `go_to` names it."""
    return (6, 2.5, [*LOOK, "--trailer-shot=hold", f"--province={name}", "--men=40", f"--give={LARGE}",
                     *([f"--go-to={go_to}"] if go_to else []), "--livery=2,2", f"--hud={hud}", f"--march={march}"])


# name: (seconds to record, the second a quick screenshot of it is taken at, its look flags). The edit takes its part of each from
# edit.gd; a shot runs a moment before the part that is used, so the field has settled. --livery sets the armour and cloth the
# legion has earned by that point of the story, from iron and red at the start to gold and purple at the end, --hud the
# level, clock and kills of a run at that point, and --march keeps the legion on the move, as a player always is.
SHOTS = {
    "hook": (13, 4.0, [*LOOK, "--trailer-shot=hook", f"--give={LARGE}", "--men=80", "--livery=2,2", "--hud=31,702,4870",
                       "--march=0.5,0.15"]),
    # The hook again without the top bar, for the thumbnail.
    "thumb": (7, 5.5, [*LOOK, "--trailer-shot=hook", f"--give={LARGE}", "--men=80", "--livery=2,2", "--march=0.5,0.15"]),
    "skirmish": (8, 3.0, [*LOOK, "--trailer-shot=skirmish", "--men=2", "--zoom=2", "--livery=0,0", "--hud=2,41,23",
                          "--march=0.45,0"]),
    "levelup": (8, 2.5, [*LOOK, "--trailer-shot=levelup", "--men=2", "--zoom=2", "--livery=0,0", "--hud=1,58,31",
                         "--march=0.45,0"]),
    "march": (8, 3.0, [*LOOK, "--trailer-shot=field", "--province=gaul", "--men=80", f"--give={LARGE}", "--go-to=field",
                       "--livery=1,1", "--hud=22,455,1630", "--march=-0.7,0"]),
    "archers": (8, 3.0, [*LOOK, "--trailer-shot=archers", "--men=4:legionary", "--give=archer:7,ballista:2", "--zoom=2",
                         "--livery=0,0", "--hud=8,190,380", "--march=0.35,0"]),
    "dodge": (8, 1.0, [*LOOK, "--trailer-shot=whirl", "--men=10", f"--give={MIXED}", "--boss=berserker", "--boss-act=whirl",
                       "--zoom=2", "--livery=1,1", "--hud=14,330,900"]),
    **{f"livery{k}": (6, 2.5, [*LOOK, "--trailer-shot=livery", "--men=16", f"--give={MIXED}", "--zoom=2", f"--livery={k},{k}",
                               "--hud=12,288,690", "--march=0.45,0"]) for k in range(3)},
    "fell": (9, 5.0, [*LOOK, "--trailer-shot=fell", "--men=14", f"--give={MIXED}", "--zoom=2", "--livery=1,1",
                      "--hud=16,372,1120"]),
    "ravine": (8, 1.5, [*LOOK, "--trailer-shot=ravine", "--men=24", f"--give={MIXED}", "--go-to=ravine", "--boss=berserker",
                        "--boss-act=fall", "--livery=1,1", "--hud=18,430,1310"]),
    "p_germania": province("germania", None, "24,500,2010", "0.5,-0.2"),
    "p_gaul": province("gaul", "field", "25,520,2140", "0.5,0.2"),
    "p_britannia": province("britannia", "circle", "26,545,2330", "-0.5,-0.15"),
    "p_hispania": province("hispania", "olives", "27,566,2510", "0.5,-0.2"),
    "p_aegyptus": province("aegyptus", "palms", "27,590,2690", "-0.45,0.2"),
    "p_parthia": (7, 3.0, [*LOOK, "--trailer-shot=hold", "--province=parthia", "--men=30", f"--give={LARGE},onager:2",
                           "--boss=war_elephant", "--boss-act=trample", "--livery=2,2", "--hud=28,612,2880", "--march=0.4,0.1"]),
    "p_dacia": (8, 1.5, [*LOOK, "--trailer-shot=onrush", "--province=dacia", "--men=30", f"--give={LARGE}", "--boss=falx_band",
                         "--boss-act=onrush", "--livery=2,2", "--hud=29,640,3090", "--march=0.4,0"]),
    "p_sarmatia": province("sarmatia", "kurgan", "30,668,3300", "0.5,0.15"),
    "gods": (9, 3.5, [*LOOK, "--trailer-shot=gods", f"--give={LARGE}", "--men=80", "--god=choose", "--god-at=1",
                      "--livery=2,2", "--hud=33,735,5300", "--march=0.45,0.1"]),
    "reveal": (9, 2.6, [*LOOK, "--trailer-shot=reveal", f"--give={LARGE}", "--men=80", "--god=jupiter", "--god-at=2",
                        "--livery=2,2", "--hud=33,741,5330", "--march=0.45,0.1"]),
    "chief": (9, 3.0, [*LOOK, "--trailer-shot=chief", "--men=60", f"--give={LARGE}", "--boss=chieftain", "--boss-act=die",
                       "--livery=2,2", "--hud=35,802,5980"]),
    "fort": (11, 3.0, [*LOOK, "--trailer-shot=fort", "--province=britannia", "--men=50", f"--give={LARGE}", "--go-to=fort",
                       "--livery=2,2", "--hud=36,840,6240"]),
    "endcard": (10, 3.0, [*LOOK, "--trailer-shot=endcard", "--province=gaul", "--men=85", f"--give={LARGE}", "--go-to=field",
                          "--livery=2,2"]),
}
SHOTS_DIR = WORK / "trailer_shots"
# The Google Play video shows the game as a phone gives it: these shots again with the phone's touch controls, a thumb on
# the stick, and no store but Google Play's named.
PHONE_SHOTS = ["hook", "skirmish", "march", "archers", "dodge", "ravine", "p_gaul", "p_aegyptus", "p_parthia", "p_dacia",
               "gods", "reveal", "chief", "endcard"]
PHONE_DIR = WORK / "phone_shots"
PHONE_OUT = VIDEOS / "play_store_trailer" / "play_store_trailer.avi"
# The shorts' tall frame, the game's view inside it at three screen pixels to the game pixel, and where their shots are kept.
TALL = (1080, 1920)
TALL_VIEW = (360, 640)
SHORT_DIR = WORK / "short_shots"
# The shorts' shots: (seconds to record, look flags). --fixed keeps a legion to the men it starts with, --mortal lets it
# lose them, --testudo raises the shields against a charge and --aim moves the view off the commander.
SHORT_SHOTS = {
    "how_many": (19, [*LOOK, "--trailer-shot=hook", "--province=gaul", "--men=8", "--give=archer:2,centurion:1", "--livery=2,2",
                      "--fixed"]),
    "storm": (20, [*LOOK, "--trailer-shot=storm", "--men=12", f"--give={MIXED}", "--livery=1,1", "--god=jupiter",
                   "--god-at=12.65"]),
    "whirl": (5, [*LOOK, "--trailer-shot=whirl", "--men=10", f"--give={MIXED}", "--boss=berserker", "--boss-act=whirl",
                  "--zoom=2", "--livery=1,1"]),
    "cliff": (20, [*LOOK, "--trailer-shot=ravine", "--give=legionary:24,centurion:2,standard_bearer:1,medicus:1",
                   "--go-to=ravine", "--boss=berserker", "--boss-act=fall", "--livery=1,1", "--back=300", "--pace=0.35"]),
    "volley": (14, [*LOOK, "--trailer-shot=volley", "--commander=archer_captain", "--give=archer:37", "--livery=1,1",
                    "--aim=0,-110"]),
    "trample": (8, [*LOOK, "--trailer-shot=elephant", "--province=parthia", "--men=12:legionary", "--give=archer:4",
                    "--boss=war_elephant", "--boss-act=trample", "--livery=0,0"]),
    "trample_testudo": (8, [*LOOK, "--trailer-shot=elephant", "--province=parthia", "--men=12:legionary", "--give=archer:4",
                            "--boss=war_elephant", "--boss-act=trample", "--livery=0,0", "--testudo"]),
    "first": (8, [*LOOK, "--trailer-shot=skirmish", "--men=2", "--zoom=2", "--livery=0,0", "--march=0,-0.45"]),
    "last": (10, [*LOOK, "--trailer-shot=hold", "--province=sarmatia", "--men=45", f"--give={LARGE}", "--go-to=kurgan",
                  "--livery=2,2", "--march=0,-0.4"]),
    "close": (22, [*LOOK, "--trailer-shot=close", "--province=sarmatia", "--hard", "--men=4", "--mortal", "--fixed",
                   "--livery=0,0", "--crowd=80", "--zoom=2"]),
    "endcard": (9, [*LOOK, "--trailer-shot=endcard", "--province=gaul", "--men=85", f"--give={LARGE}", "--go-to=field",
                    "--livery=2,2"]),
}
# Each short's edit in edit.gd: (its folder's name after short_, its shots, the second its thumbnail is taken at).
SHORTS = {
    "how_many": ("guess_how_many", ["how_many", "endcard"], 6.0),
    "jupiter": ("pray_to_jupiter", ["storm", "endcard"], 7.0),
    "cliff": ("off_a_cliff", ["whirl", "cliff", "endcard"], 7.0),
    "archers": ("archers", ["volley", "endcard"], 6.0),
    "testudo": ("testudo", ["trample", "trample_testudo", "endcard"], 7.0),
    "first_vs_last": ("first_vs_last", ["first", "last", "endcard"], 8.0),
    "close_call": ("close_call", ["close", "endcard"], 10.0),
}
# The loudness the Google Play video's .mp4 measures at, in LUFS, which the shorts are brought to, and the most bits a
# second their .mp4s take, so a horde of moving pixels stays a size the phone apps accept.
SHORT_LUFS = -16.2
SHORT_RATE = "20M"
# The thumbnail: the second of the thumb shot it is taken from, the logo's size in screen pixels to its own, and its top.
THUMB_AT = 5.5
THUMB_LOGO_SCALE = 4
THUMB_LOGO_Y = 60
OUT = VIDEOS / "steam_trailer" / "steam_trailer.avi"


def godot(args, size=SIZE, full=False, view=None):
    """Runs Godot in a window of the given size. Movie mode records the game's own 640 by 360 view, or the `view` given,
    which the edit scales up by whole pixels; with `full` the view is the whole window, so the edit itself is recorded
    at full size."""
    override = ROOT / "game" / "override.cfg"
    if override.exists():
        sys.exit(f"{override} already exists; move it aside first")
    if full:
        view = (f"window/size/viewport_width={size[0]}\nwindow/size/viewport_height={size[1]}\n"
                "window/stretch/mode=\"disabled\"\n")
    elif view:
        view = f"window/size/viewport_width={view[0]}\nwindow/size/viewport_height={view[1]}\n"
    else:
        view = ""
    override.write_text(f"[display]\n\nwindow/size/window_width_override={size[0]}\nwindow/size/window_height_override={size[1]}\n{view}\n"
                        "[editor]\n\nmovie_writer/mjpeg_quality=0.95\n")
    try:
        subprocess.run([str(GODOT), "--path", str(ROOT / "game"), *args], check=True)
    finally:
        override.unlink()


def record(name, phone=False):
    folder = (PHONE_DIR if phone else SHOTS_DIR) / name
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    seconds, _, flags = SHOTS[name]
    # A .png movie is written as numbered frames with the sound beside them in a .wav of the same name.
    godot(["--write-movie", str(folder / "f.png"), "--fixed-fps", str(FPS), "--quit-after", str(seconds * FPS), "--", *flags,
           *(["--phone"] if phone else [])])


def render(start=0.0, phone=False):
    """Renders the trailer, or the Google Play video, or with a start time a preview from that moment on into the work
    folder."""
    out = WORK / "preview.avi" if start else (PHONE_OUT if phone else OUT)
    out.parent.mkdir(parents=True, exist_ok=True)
    shots = PHONE_DIR if phone else SHOTS_DIR
    # The edit quits when it ends; the frame limit only stops a run whose script failed to load from going on forever.
    godot(["--write-movie", str(out), "--fixed-fps", str(FPS), "--quit-after", str(200 * FPS), "res://tools/trailer/edit.tscn",
           "--", "--no-save", f"--shots={shots}", f"--from={start}", f"--cut={'play_store' if phone else 'trailer'}"], full=True)
    if not start:
        mp4_copy(out)
        if not phone:
            thumbnail(out.parent / "thumbnail.png")
    print(f"ready: {out}")


def mp4_copy(avi, out=None, gain=None, rate=None):
    """Writes an .mp4 beside the .avi: about a tenth of its size, and the format Steam wants, with its sound brought to
    the loudness video sites play at, or changed by `gain` decibels, and its bit rate held under `rate` when given.
    Skipped without ffmpeg."""
    if not FFMPEG.exists():
        print("no ffmpeg, so no .mp4 copy")
        return
    # The AAC encoder overshoots sharp clicks by about 2 dB, so peaks are held at -3 dBTP to stay under 0 once encoded.
    sound = "loudnorm=I=-16:TP=-3:LRA=11" if gain is None else f"volume={gain:.2f}dB"
    cap = ["-maxrate", rate, "-bufsize", rate] if rate else []
    subprocess.run([str(FFMPEG), "-y", "-loglevel", "error", "-i", str(avi), "-c:v", "libx264", "-preset", "slow", "-crf", "16",
                    *cap, "-pix_fmt", "yuv420p", "-af", sound, "-ar", "48000", "-c:a", "aac", "-b:a", "192k",
                    "-movflags", "+faststart", str(out or avi.with_suffix(".mp4"))], check=True)


def record_short(name):
    folder = SHORT_DIR / name
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    seconds, flags = SHORT_SHOTS[name]
    godot(["--write-movie", str(folder / "f.png"), "--fixed-fps", str(FPS), "--quit-after", str(seconds * FPS), "--", *flags],
          TALL, view=TALL_VIEW)


def render_short(name, start=0.0):
    """Renders a short, or with a start time a preview from that moment on into the work folder. The .avi and the
    _steam_only.mp4 end on the Steam scroll alone; the .mp4 is rendered again with the store badges under it."""
    folder, _, thumb_at = SHORTS[name]
    out_dir = VIDEOS / f"short_{folder}"
    avi = WORK / "preview.avi" if start else out_dir / f"short_{folder}.avi"
    avi.parent.mkdir(parents=True, exist_ok=True)
    edit = ["--fixed-fps", str(FPS), "--quit-after", str(200 * FPS), "res://tools/trailer/edit.tscn", "--", "--no-save",
            f"--shots={SHORT_DIR}", f"--from={start}", f"--cut={name}"]
    godot(["--write-movie", str(avi), *edit], TALL, full=True)
    if start:
        print(f"ready: {avi}")
        return
    # One steady change of volume brings the short to the Google Play video's loudness without touching its dynamics.
    gain = SHORT_LUFS - loudness(avi)[0]
    level_avi(avi, gain)
    mp4_copy(avi, avi.with_name(f"short_{folder}_steam_only.mp4"), gain=0.0, rate=SHORT_RATE)
    badged = WORK / "badged.avi"
    try:
        godot(["--write-movie", str(badged), *edit, "--badges"], TALL, full=True)
        mp4_copy(badged, avi.with_suffix(".mp4"), gain=gain, rate=SHORT_RATE)
    finally:
        badged.unlink(missing_ok=True)
    subprocess.run([str(FFMPEG), "-y", "-loglevel", "error", "-ss", str(thumb_at), "-i", str(avi), "-frames:v", "1",
                    str(out_dir / "thumbnail.png")], check=True)
    print(f"ready: {avi}")


def loudness(media):
    """The integrated loudness in LUFS and the true peak in dBTP of a file's sound, as ffmpeg's ebur128 filter measures them."""
    import re
    run = subprocess.run([str(FFMPEG), "-hide_banner", "-nostats", "-i", str(media), "-vn", "-af", "ebur128=peak=true",
                          "-f", "null", "-"], capture_output=True, text=True, check=True)
    summary = run.stderr[run.stderr.rindex("Summary:"):]
    peak = re.search(r"Peak:\s+(-?[\d.]+|-inf) dBFS", summary).group(1)
    return float(re.search(r"I:\s+(-?[\d.]+) LUFS", summary).group(1)), float(peak.replace("-inf", "-1e9"))


def level_avi(avi, gain):
    """Changes the .avi's sound by `gain` decibels, leaving its picture as it is."""
    tmp = avi.with_name("levelled.avi")
    subprocess.run([str(FFMPEG), "-y", "-loglevel", "error", "-i", str(avi), "-c:v", "copy", "-af", f"volume={gain:.2f}dB",
                    "-c:a", "pcm_s16le", str(tmp)], check=True)
    tmp.replace(avi)


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
    first = float(re.search(r"const FIRST_BEAT := ([\d.]+)", text).group(1))
    cut = text.split("const TRAILER := [", 1)[1].split("\n]", 1)[0]
    # As in edit.gd, every cut but the first lands on a beat of the music.
    def frame_of(beats):
        return 0 if beats <= 0 else round((first + beats * beat) * FPS)
    out = []
    beats = 0.0
    for line in cut.splitlines():
        m = re.search(r'\{"(?:shot|end)": "([^"]+)".*?"beats": ([\d.]+)', line)
        if not m:
            continue
        caption = re.search(r'"caption": "([^"]+)"', line)
        label = m.group(1) + (f": {caption.group(1)}" if caption else "")
        start, end = frame_of(beats), frame_of(beats + float(m.group(2)))
        out.append((label, start / FPS, (end - start) / FPS))
        beats += float(m.group(2))
    return out


def thumbnail(out):
    """The opening battle at full brightness with the logo large over a soft dark glow, and nothing else, so it still
    reads at the size a thumbnail is seen at."""
    from PIL import Image, ImageDraw, ImageFilter
    frame = Image.open(SHOTS_DIR / "thumb" / f"f{round(THUMB_AT * FPS):08d}.png").convert("RGB")
    picture = frame.resize(SIZE, Image.NEAREST)
    logo = Image.open(ROOT / "game" / "assets" / "logo.png").convert("RGBA")
    logo = logo.resize((logo.width * THUMB_LOGO_SCALE, logo.height * THUMB_LOGO_SCALE), Image.NEAREST)
    at = ((SIZE[0] - logo.width) // 2, THUMB_LOGO_Y)
    glow = Image.new("L", SIZE, 0)
    ImageDraw.Draw(glow).ellipse((at[0] - 120, at[1] - 60, at[0] + logo.width + 120, at[1] + logo.height + 60), fill=170)
    glow = glow.filter(ImageFilter.GaussianBlur(70))
    picture = Image.composite(Image.new("RGB", SIZE, (12, 8, 6)), picture, glow)
    picture.paste(logo, at, logo)
    picture.save(out)


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
    short = next((a.split("=", 1)[1] for a in args if a.startswith("--cut=") and a != "--cut=play_store"), None)
    if short is not None:
        if short not in SHORTS:
            sys.exit(f"no short named {short}; the shorts are {', '.join(SHORTS)}")
        args = [a for a in args if not a.startswith("--cut=")]
        shots = SHORTS[short][1]
        if args[:1] == ["shots"]:
            for shot in args[1:] or shots:
                record_short(shot)
            return
        if args[:1] != ["render"]:
            for shot in shots:
                if not (SHORT_DIR / shot / "f.wav").exists():
                    record_short(shot)
        render_short(short, float(args[1]) if args[:1] == ["render"] and len(args) > 1 else 0.0)
        return
    phone = "--cut=play_store" in args
    args = [a for a in args if a != "--cut=play_store"]
    if args[:1] == ["stills"]:
        stills(args[1])
        return
    if args[:1] == ["shots"]:
        for shot in args[1:] or (PHONE_SHOTS if phone else SHOTS):
            record(shot, phone)
        return
    if args[:1] != ["render"]:
        for shot in PHONE_SHOTS if phone else SHOTS:
            if not ((PHONE_DIR if phone else SHOTS_DIR) / shot / "f.wav").exists():
                record(shot, phone)
    render(float(args[1]) if args[:1] == ["render"] and len(args) > 1 else 0.0, phone)


if __name__ == "__main__":
    main()
