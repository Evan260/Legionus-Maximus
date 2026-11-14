"""Builds the game's two music loops from CC0 samples: a calm harp layer and a drum layer of the same length and tempo.

Run: python tools/audio/make_music.py
The harp plays an arpeggiated A minor progression from the VSCO 2 CE harp notes, retuned to each pitch. The drums play a march
on a bass drum, a taiko and a frame drum, with a fill on the last bar. Both loops are 16 bars at 90 BPM, so they stay in step
when started together, and each tail wraps round to the start so the loop has no seam. The result is game/assets/audio/music/.
"""
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DOWNLOADS = ROOT / "tools" / "audio" / "downloads"
OUT = ROOT / "game" / "assets" / "audio" / "music"
RATE = 44100
FFMPEG = "ffmpeg"
BPM = 90
BARS = 16
BEAT = 60.0 / BPM
LOOP = int(round(BARS * 4 * BEAT * RATE))

# Freesound id of each harp note, by MIDI pitch.
HARP = {59: 373559, 62: 373565, 65: 373570, 69: 373556, 72: 373563, 76: 373568, 79: 373573, 83: 373560, 86: 373566, 89: 373571}
# Chord roots in MIDI and whether the chord is minor, one chord per bar, repeated twice over the 16 bars.
CHORDS = [(57, True), (53, False), (60, False), (55, False), (57, True), (53, False), (50, True), (52, False)]
PATTERNS = [[0, 2, 3, 2, 4, 3, 2, 1], [0, 1, 2, 4, 3, 2, 1, 2], [0, 2, 4, 3, 5, 4, 3, 2]]


def read(sid):
    src = DOWNLOADS / f"{sid}.mp3"
    if not src.exists():
        sys.exit(f"missing recording {src}, run fetch_sounds.py")
    raw = subprocess.run([FFMPEG, "-v", "error", "-i", str(src), "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def onset(x):
    env = np.convolve(np.abs(x), np.ones(220) / 220, mode="same")
    above = np.nonzero(env > np.max(env) * 0.03)[0]
    return max(0, int(above[0]) - int(RATE * 0.004)) if len(above) else 0


def retune(x, semitones, length):
    """The sample played faster or slower so it sounds that many semitones away, cut to `length` seconds with a fade-out."""
    ratio = 2.0 ** (semitones / 12.0)
    n = int(length * RATE)
    src = np.arange(n) * ratio
    src = src[src < len(x) - 1]
    y = np.interp(src, np.arange(len(x)), x)
    fade = min(len(y), int(RATE * min(1.2, length * 0.5)))
    y[-fade:] *= np.linspace(1, 0, fade) ** 2
    return y


def add(buf, clip, at, gain, pan=0.0):
    """Mixes a clip into the stereo buffer at a time in seconds, wrapping the end round to the start."""
    start = int(at * RATE) % LOOP
    idx = (start + np.arange(len(clip))) % LOOP
    left = gain * (1.0 - max(0.0, pan))
    right = gain * (1.0 + min(0.0, pan))
    np.add.at(buf[0], idx, clip * left)
    np.add.at(buf[1], idx, clip * right)


def reverb(buf, wet):
    """Adds a soft room round the loop; the convolution is circular, so the tail carries over the seam."""
    rng = np.random.default_rng(5)
    n = int(1.8 * RATE)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (0.5 * RATE))
    ir = np.convolve(ir, np.ones(8) / 8, mode="same")
    ir /= np.sqrt(np.sum(ir ** 2))
    pad = np.zeros(LOOP)
    pad[:n] = ir
    f = np.fft.rfft(pad)
    return np.stack([channel + wet * np.fft.irfft(np.fft.rfft(channel) * f, LOOP) for channel in buf])


def harp(samples):
    rng = np.random.default_rng(11)
    buf = np.zeros((2, LOOP))
    for bar in range(BARS):
        root, minor = CHORDS[bar % len(CHORDS)]
        third = 3 if minor else 4
        tones = [root, root + third, root + 7, root + 12, root + 12 + third, root + 19]
        t0 = bar * 4 * BEAT
        pattern = PATTERNS[(bar // 4) % len(PATTERNS)] if bar % 8 != 7 else PATTERNS[1]
        for k, step in enumerate(pattern):
            midi = tones[step] + (12 if bar >= 8 and k % 4 == 3 else 0)
            at = t0 + k * BEAT / 2 + rng.uniform(-0.008, 0.008)
            vel = (0.7 if k % 4 == 0 else 0.45) * rng.uniform(0.85, 1.1)
            note(buf, samples, midi, at, vel)
        note(buf, samples, root, t0, 0.8, 3.5)
        if bar % 2 == 1:
            note(buf, samples, root + 7, t0 + 2 * BEAT, 0.5, 3.0)
    buf = reverb(buf, 0.35)
    return buf / np.max(np.abs(buf)) * 10 ** (-3 / 20)


def note(buf, samples, midi, at, vel, length=2.6):
    base = min(HARP, key=lambda m: abs(m - midi))
    clip = retune(samples[base], midi - base, length)
    add(buf, clip, at, vel, pan=(midi - 66) / 40.0)


def drums():
    rng = np.random.default_rng(23)
    buf = np.zeros((2, LOOP))
    kick = read(375287)
    kick = kick[onset(kick):]
    taiko = read(486140)
    taiko = taiko[onset(taiko):]
    frame = read(345635)
    frame = frame[onset(frame):]
    tom = read(581467)
    tom = tom[onset(tom):]

    def hit(sample, at, gain, semitones=0.0, length=1.0, pan=0.0):
        add(buf, retune(sample, semitones, length), at + rng.uniform(-0.006, 0.006), gain * rng.uniform(0.9, 1.05), pan)

    for bar in range(BARS):
        t0 = bar * 4 * BEAT
        hit(taiko, t0, 0.9, -5, 1.2)
        hit(kick, t0, 0.8, -3, 0.7)
        hit(kick, t0 + 2 * BEAT, 0.7, -3, 0.7)
        if bar % 2 == 1:
            hit(kick, t0 + 2.5 * BEAT, 0.5, -3, 0.6)
        for beat in (1, 3):
            hit(frame, t0 + beat * BEAT, 0.55, 0, 0.5, 0.2)
        for k in range(8):
            if k % 2 == 1:
                hit(frame, t0 + k * BEAT / 2, 0.14, 4, 0.3, -0.25)
        if bar % 8 == 7:
            for k in range(8):
                hit(tom, t0 + 3 * BEAT + k * BEAT / 8, 0.4 + 0.07 * k, -2 - (k % 3) * 2, 0.6, (k - 4) / 8)
    buf = reverb(buf, 0.12)
    return buf / np.max(np.abs(buf)) * 10 ** (-3 / 20)


def write_ogg(path, buf):
    subprocess.run([FFMPEG, "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "-", "-c:a", "libvorbis",
                    "-q:a", "2", str(path)], input=buf.T.astype(np.float32).tobytes(), check=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    samples = {m: read(sid)[onset(read(sid)):] for m, sid in HARP.items()}
    write_ogg(OUT / "calm.ogg", harp(samples))
    write_ogg(OUT / "drums.ogg", drums())
    print(f"loops of {LOOP / RATE:.3f} s written to {OUT}")


if __name__ == "__main__":
    main()
