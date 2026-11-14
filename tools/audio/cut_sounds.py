"""Cuts the game's sound effects out of the recordings in tools/audio/downloads into game/assets/audio/sfx/*.ogg.

Run: python tools/audio/cut_sounds.py
Each effect is trimmed to its first sound, faded out, peak-normalised and written as mono Vorbis. Sources and licences are in CREDITS.md.
"""
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DOWNLOADS = ROOT / "tools" / "audio" / "downloads"
OUT = ROOT / "game" / "assets" / "audio" / "sfx"
RATE = 44100
FFMPEG = "ffmpeg"

# output name: (Freesound id, seconds to skip after the first sound or None to start at it, length in seconds, fade-out
# seconds, peak in dB)
CUTS = {
    "hit_1": (547042, 0.0, 0.45, 0.2, -3), "hit_2": (442769, 0.0, 0.5, 0.2, -3), "hit_3": (426322, 0.0, 0.45, 0.2, -3),
    "hit_4": (334169, 0.0, 0.4, 0.15, -3), "hit_5": (175949, 0.0, 0.5, 0.2, -3),
    "thump_1": (370203, 0.0, 0.5, 0.2, -3), "thump_2": (792354, 0.0, 0.5, 0.2, -3), "thump_3": (138489, 0.0, 0.11, 0.04, -3),
    "arrow_1": (394179, 0.0, 0.3, 0.1, -3), "arrow_2": (263675, 0.0, 0.5, 0.2, -3),
    "pilum_1": (420670, 0.0, 0.36, 0.15, -3), "pilum_2": (420668, 0.0, 0.18, 0.06, -3),
    "bolt_1": (163453, 0.0, 0.2, 0.05, -3), "bolt_2": (249810, 0.0, 0.8, 0.3, -3),
    "horn_1": (539956, 0.0, 3.0, 1.2, -3), "horn_2": (482686, 0.0, 4.5, 1.8, -3),
    "roar_1": (651646, 0.0, 4.5, 1.6, -3), "roar_2": (267248, 0.0, 4.0, 1.5, -3),
    "drum_1": (486140, 0.0, 1.2, 0.5, -3), "drum_2": (486141, 0.0, 1.2, 0.5, -3), "drum_3": (375287, 0.0, 0.8, 0.3, -3),
    "drum_4": (581467, 0.0, 0.9, 0.3, -3),
    "hurt_1": (547209, 0.0, 0.32, 0.1, -3), "hurt_2": (464486, 0.0, 0.55, 0.2, -3),
    "die_1": (416839, 0.0, 0.7, 0.25, -3), "die_2": (416838, 0.0, 0.8, 0.3, -3), "die_3": (554443, 0.0, 0.7, 0.25, -3),
    "die_4": (577032, 0.0, 0.9, 0.3, -3),
    "coin_1": (347174, 0.0, 0.3, 0.1, -3), "coin_2": (350875, 0.0, 0.26, 0.1, -3),
    "level_1": (442943, 0.0, 1.4, 0.5, -3), "level_2": (609335, 0.0, 0.6, 0.2, -3),
    "click_1": (546974, 0.0, 0.2, 0.08, -3), "click_2": (467951, 0.0, 0.12, 0.05, -3), "click_3": (253168, 0.0, 0.16, 0.05, -3),
}


def read(sid):
    """A downloaded recording as mono float samples at 44.1 kHz, decoded by ffmpeg."""
    src = DOWNLOADS / f"{sid}.mp3"
    if not src.exists():
        sys.exit(f"missing recording {src}, run fetch_sounds.py")
    raw = subprocess.run([FFMPEG, "-v", "error", "-i", str(src), "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def first_sound(x):
    """Where the sound starts: the first moment above a small share of the loudest, a few milliseconds early."""
    env = np.convolve(np.abs(x), np.ones(220) / 220, mode="same")
    above = np.nonzero(env > np.max(env) * 0.03)[0]
    return max(0, int(above[0]) - int(RATE * 0.006)) if len(above) else 0


def write_ogg(path, x):
    subprocess.run([FFMPEG, "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-", "-c:a", "libvorbis",
                    "-q:a", "4", str(path)], input=x.astype(np.float32).tobytes(), check=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.ogg"):
        old.unlink()
    for name, (sid, skip, length, fade_out, peak_db) in CUTS.items():
        x = read(sid)
        a = first_sound(x) + int(skip * RATE)
        clip = x[a:a + int(length * RATE)].copy()
        n_in = int(RATE * 0.002)
        n_out = min(len(clip), int(RATE * fade_out))
        clip[:n_in] *= np.linspace(0, 1, n_in)
        clip[-n_out:] *= np.linspace(1, 0, n_out) ** 2
        clip *= 10 ** (peak_db / 20) / max(np.max(np.abs(clip)), 1e-9)
        write_ogg(OUT / f"{name}.ogg", clip)
        print(f"{name}: {sid} from {a / RATE:.2f}s, {len(clip) / RATE:.2f}s")


if __name__ == "__main__":
    main()
