"""
Monrovia Life - synthesises every sound effect, ambience loop and music track used by the
3D game, so the game's audio is original and free of third-party licences.

Output: proto3d/audio/*.wav (22.05 kHz, 16-bit mono; Godot compresses them on import).

    SFX:       engine_car, engine_keke, engine_truck (seamless loops, pitched by RPM in game),
               horn_car, horn_keke, siren (loop), skid (loop), crash, explosion, gunshot,
               punch, step_hard_1/2, step_soft_1/2, door, cash, ui_click, ui_confirm
    Ambience:  amb_city_day, amb_city_night, amb_market, amb_waves, amb_rain (seamless loops)
    Music:     music_menu (calm theme), radio_highlife, radio_hipco, radio_palmwine (loops)

Run (needs Python 3 + numpy; Blender's bundled Python has both):
    "C:\\Program Files\\Blender Foundation\\Blender 5.3\\5.3\\python\\bin\\python.exe" -I tools\\make_audio.py
"""
import math
import os
import wave

import numpy as np

SR = 22050
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "proto3d", "audio")
rng = np.random.default_rng(1847)


# ------------------------------------------------------------------ helpers
def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def lowpass(x, cutoff):
    """One-pole low-pass (fine for shaping noise)."""
    a = math.exp(-2 * math.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    b = 1 - a
    for i in range(len(x)):
        acc = b * x[i] + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def env(n, attack, decay, sustain=0.0, release=None):
    """Attack/decay envelope in seconds over n samples (exponential decay)."""
    e = np.ones(n)
    a = max(1, int(attack * SR))
    e[:a] = np.linspace(0, 1, a)
    rest = np.arange(n - a) / SR
    e[a:] = sustain + (1 - sustain) * np.exp(-rest / max(decay, 1e-4))
    return e


def noise(n):
    return rng.uniform(-1, 1, n)


def brown(n):
    b = np.cumsum(rng.uniform(-1, 1, n))
    b -= lowpass(b, 2.0)          # remove drift
    return b / (np.abs(b).max() + 1e-9)


def norm(x, peak=0.9):
    m = np.abs(x).max()
    return x * (peak / m) if m > 0 else x


def loopify(x, fade=0.25):
    """Makes a loop seamless by cross-fading its end into its start."""
    f = int(fade * SR)
    head = x[:f].copy()
    tail = x[-f:]
    w = np.linspace(0, 1, f)
    x = x[:-f].copy()
    x[:f] = head * w + tail * (1 - w)
    return x


def save(name, x, peak=0.9):
    os.makedirs(OUT, exist_ok=True)
    data = (np.clip(norm(x, peak), -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("  %-18s %5.1f s" % (name, len(data) / SR))


def place(buf, sound, at, gain=1.0):
    i = int(at * SR)
    if i >= len(buf):
        return
    n = min(len(sound), len(buf) - i)
    buf[i:i + n] += sound[:n] * gain


# ------------------------------------------------------------------ vehicles
def engine(freq, harmonics, rasp, sec=1.0):
    """Combustion pulses at `freq`: decaying harmonic bursts plus filtered noise."""
    n = int(SR * sec)
    t = np.arange(n) / SR
    phase = (t * freq) % 1.0
    pulse = np.exp(-phase * 6.0)
    tone = sum(np.sin(2 * np.pi * freq * k * t) / k for k in range(1, harmonics + 1))
    grit = lowpass(noise(n), 900) * rasp
    x = tone * (0.55 + 0.45 * pulse) + grit * pulse
    return x  # an exact number of cycles in 1 s, so it loops cleanly


def horn(freqs, sec, gaps=None):
    t = t_axis(sec)
    x = sum(np.sign(np.sin(2 * np.pi * f * t)) * 0.5 + np.sin(2 * np.pi * f * t) for f in freqs)
    x = lowpass(x, 2500)
    e = env(len(t), 0.01, 10, 1.0)
    e[-int(0.04 * SR):] *= np.linspace(1, 0, int(0.04 * SR))
    if gaps:
        for a, b in gaps:
            e[int(a * SR):int(b * SR)] = 0
    return x * e


def siren(sec=2.0):
    t = t_axis(sec)
    tri = 1 - np.abs(((t / sec) * 2) % 2 - 1)           # one up-down sweep per loop
    f = 650 + tri * 650
    ph = np.cumsum(2 * np.pi * f / SR)
    x = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
    return lowpass(x, 3000)


def skid(sec=1.0):
    n = int(SR * sec)
    x = bandpass(noise(n), 900, 3200)
    wob = 0.75 + 0.25 * np.sin(2 * np.pi * 7 * np.arange(n) / SR)
    return loopify(x * wob, 0.1)


def crash(sec=0.9):
    n = int(SR * sec)
    t = np.arange(n) / SR
    body = lowpass(noise(n), 1800) * env(n, 0.002, 0.12)
    thump = np.sin(2 * np.pi * 70 * t) * env(n, 0.002, 0.15)
    clank = sum(np.sin(2 * np.pi * f * t) * env(n, 0.001, d) for f, d in ((1230, 0.25), (1870, 0.18), (2650, 0.12), (3400, 0.08)))
    glass = highpass(noise(n), 4000) * env(n, 0.01, 0.2) * 0.4
    return body + thump * 0.8 + clank * 0.25 + glass


def explosion(sec=2.6):
    n = int(SR * sec)
    t = np.arange(n) / SR
    boom = lowpass(brown(n), 300) * env(n, 0.005, 0.6)
    crack = lowpass(noise(n), 3000) * env(n, 0.001, 0.08)
    sub = np.sin(2 * np.pi * (45 - 15 * t) * t) * env(n, 0.005, 0.5)
    debris = sum(highpass(noise(n), 2000) * env(n, 0.001, 0.03) * (np.arange(n) >= int(SR * d)) for d in (0.3, 0.55, 0.8, 1.1)) * 0.15
    return boom + crack * 0.6 + sub + debris


def gunshot(sec=0.6):
    n = int(SR * sec)
    t = np.arange(n) / SR
    crack = noise(n) * env(n, 0.0005, 0.02)
    body = lowpass(noise(n), 2500) * env(n, 0.001, 0.09)
    thump = np.sin(2 * np.pi * 110 * t) * env(n, 0.001, 0.06)
    tail = lowpass(noise(n), 800) * env(n, 0.02, 0.25) * 0.25
    return crack * 0.8 + body + thump * 0.7 + tail


def punch(sec=0.25):
    n = int(SR * sec)
    t = np.arange(n) / SR
    return lowpass(noise(n), 900) * env(n, 0.001, 0.04) + np.sin(2 * np.pi * (140 - 200 * t) * t) * env(n, 0.001, 0.06)


def step(hard, seed, sec=0.18):
    n = int(SR * sec)
    local = np.random.default_rng(seed).uniform(-1, 1, n)
    if hard:
        x = bandpass(local, 600, 5000) * env(n, 0.001, 0.025) + lowpass(local, 300) * env(n, 0.001, 0.05) * 0.6
    else:
        x = lowpass(local, 1200) * env(n, 0.005, 0.05)
    return x


def door(sec=0.4):
    n = int(SR * sec)
    t = np.arange(n) / SR
    latch = highpass(noise(n), 2500) * env(n, 0.001, 0.015) * (t > 0.03)
    slam = lowpass(noise(n), 600) * env(n, 0.002, 0.07) + np.sin(2 * np.pi * 85 * t) * env(n, 0.002, 0.08)
    return slam + latch * 0.5


def chime(freqs, sec, decay):
    t = t_axis(sec)
    n = len(t)
    return sum(np.sin(2 * np.pi * f * t) * env(n, 0.002, decay) * (0.6 ** i) for i, f in enumerate(freqs))


# ------------------------------------------------------------------ ambience
def amb_city(night, sec=30.0):
    n = int(SR * sec)
    hum = lowpass(brown(n), 180) * (0.35 if night else 0.8)
    hiss = lowpass(noise(n), 2000) * (0.03 if night else 0.08)
    x = hum + hiss
    if night:          # crickets: fast amplitude-modulated chirps
        t = np.arange(n) / SR
        for f, rate, phase in ((4300, 2.1, 0.0), (4700, 2.6, 0.7), (3900, 1.7, 1.9)):
            gate = (np.sin(2 * np.pi * rate * t + phase) > 0.6).astype(float)
            gate = lowpass(gate, 30)
            x += np.sin(2 * np.pi * f * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 28 * t)) * gate * 0.05
    else:              # distant horns and engines
        for k in range(9):
            h = horn([rng.uniform(380, 620), rng.uniform(450, 700)], rng.uniform(0.2, 0.6))
            place(x, lowpass(h, 1200) * 0.06, rng.uniform(0.5, sec - 1.5))
    return loopify(x, 0.5)


def amb_market(sec=30.0):
    n = int(SR * sec)
    t = np.arange(n) / SR
    x = np.zeros(n)
    # babble: several "voices" = formant-band noise with syllable-rate modulation
    for v in range(10):
        f1 = rng.uniform(350, 800)
        f2 = rng.uniform(1100, 2200)
        src = noise(n)
        voice = bandpass(src, f1 * 0.7, f1 * 1.3) + 0.6 * bandpass(src, f2 * 0.8, f2 * 1.2)
        syl = np.clip(np.sin(2 * np.pi * rng.uniform(3.0, 5.5) * t + rng.uniform(0, 6)), 0, 1)
        phrase = (np.sin(2 * np.pi * rng.uniform(0.15, 0.35) * t + rng.uniform(0, 6)) > -0.2).astype(float)
        x += voice * lowpass(syl * phrase, 20) * rng.uniform(0.4, 1.0)
    x = lowpass(x, 3000) + lowpass(brown(n), 200) * 0.3
    for k in range(14):  # clinks of pots and coins
        place(x, chime([rng.uniform(1800, 3200), rng.uniform(2500, 4200)], 0.4, 0.06) * 0.15, rng.uniform(0.2, sec - 0.5))
    return loopify(x, 0.5)


def amb_waves(sec=30.0):
    n = int(SR * sec)
    t = np.arange(n) / SR
    x = np.zeros(n)
    at = 0.0
    while at < sec:      # each wave: swell up, crash, wash back
        period = rng.uniform(5.5, 8.5)
        m = int(period * SR)
        w = np.zeros(n)
        i = int(at * SR)
        seg = min(m, n - i)
        tt = np.arange(seg) / SR
        shape = np.clip(np.sin(np.pi * tt / period), 0, 1) ** 2.5
        w[i:i + seg] = shape
        x += lowpass(noise(n), 1400) * w * rng.uniform(0.7, 1.0)
        at += period * rng.uniform(0.55, 0.8)
    x += lowpass(noise(n), 500) * 0.15
    return loopify(x, 1.0)


def amb_rain(sec=20.0):
    n = int(SR * sec)
    x = highpass(noise(n), 1500) * 0.5 + lowpass(noise(n), 4000) * 0.3
    for k in range(250):
        place(x, highpass(noise(int(0.02 * SR)), 3000) * env(int(0.02 * SR), 0.001, 0.004), rng.uniform(0, sec - 0.1), 0.6)
    return loopify(x, 0.3)


# ------------------------------------------------------------------ music
NOTE = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def hz(name, octave):
    return 440.0 * 2 ** ((NOTE[name] + (octave - 4) * 12 - 9) / 12)


def pluck(f, sec, bright=0.5, seed=0):
    """Karplus-Strong plucked string (guitar)."""
    n = int(sec * SR)
    p = max(2, int(SR / f))
    buf = np.random.default_rng(seed).uniform(-1, 1, p) * bright + (1 - bright) * np.sin(np.linspace(0, 2 * np.pi, p))
    out = np.empty(n)
    idx = 0
    for i in range(n):
        out[i] = buf[idx]
        nxt = (idx + 1) % p
        buf[idx] = 0.996 * 0.5 * (buf[idx] + buf[nxt])
        idx = nxt
    return out * env(n, 0.002, sec * 0.6, 0.0)


def bass(f, sec):
    t = t_axis(sec)
    n = len(t)
    return (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)) * env(n, 0.005, sec * 0.5)


def kick():
    t = t_axis(0.35)
    return np.sin(2 * np.pi * (55 + 90 * np.exp(-t * 30)) * t) * env(len(t), 0.001, 0.12)


def snare():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    return highpass(noise(n), 1200) * env(n, 0.001, 0.06) + np.sin(2 * np.pi * 190 * t) * env(n, 0.001, 0.04) * 0.5


def hat(open_=False):
    n = int((0.25 if open_ else 0.06) * SR)
    return highpass(noise(n), 6000) * env(n, 0.001, 0.08 if open_ else 0.015)


def shaker():
    n = int(0.09 * SR)
    return bandpass(noise(n), 5000, 9000) * env(n, 0.01, 0.03)


CHORDS = {"C": ["C", "E", "G"], "F": ["F", "A", "C"], "G": ["G", "B", "D"], "Am": ["A", "C", "E"],
          "Dm": ["D", "F", "A"], "Em": ["E", "G", "B"]}


def song(bpm, bars, progression, style, seed):
    beat = 60.0 / bpm
    sec = bars * 4 * beat
    n = int(sec * SR) + SR * 2
    mix = np.zeros(n)
    r = np.random.default_rng(seed)
    for bar in range(bars):
        chord = progression[bar % len(progression)]
        notes = CHORDS[chord]
        root = notes[0]
        t0 = bar * 4 * beat
        if style == "highlife":
            # bright interlocking guitar: arpeggio in 8ths + a second guitar on the offbeats
            for k in range(8):
                nm = notes[[0, 1, 2, 1, 2, 0, 1, 2][k]]
                place(mix, pluck(hz(nm, 4 + (k % 3 == 2)), beat * 0.9, 0.6, seed + bar * 8 + k) * 0.55, t0 + k * beat / 2)
            for k in range(4):
                place(mix, pluck(hz(notes[(k + 1) % 3], 5), beat * 0.5, 0.8, seed + 900 + bar * 4 + k) * 0.25, t0 + k * beat + beat / 2)
            for k, b in enumerate([0, 1.5, 2, 3]):
                place(mix, bass(hz(root if k != 2 else notes[2], 2), beat * 0.9) * 0.7, t0 + b * beat)
            for k in range(4):
                place(mix, kick() * 0.6, t0 + k * beat)
                place(mix, hat() * 0.3, t0 + k * beat + beat / 2)
            place(mix, snare() * 0.35, t0 + 1 * beat)
            place(mix, snare() * 0.35, t0 + 3 * beat)
        elif style == "hipco":
            # drum machine groove, deep bass and short synth chords
            for k in (0, 1.75, 2.5):
                place(mix, kick() * 0.9, t0 + k * beat)
            for k in (1, 3):
                place(mix, snare() * 0.6, t0 + k * beat)
            for k in range(8):
                place(mix, hat(k % 4 == 3) * 0.25, t0 + k * beat / 2)
            for b in (0, 1.75, 2.5, 3.5):
                place(mix, bass(hz(root, 1), beat * 0.6) * 0.9, t0 + b * beat)
            for b in (0.5, 2.0):
                stab = sum(np.sign(np.sin(2 * np.pi * hz(nm, 4) * t_axis(beat * 0.4))) for nm in notes)
                place(mix, lowpass(stab, 1800) * env(int(beat * 0.4 * SR), 0.005, 0.1) * 0.12, t0 + b * beat)
        elif style == "palmwine":
            # gentle finger-picked guitar and a shaker
            pattern = [0, 2, 1, 2, 0, 2, 1, 2]
            for k in range(8):
                place(mix, pluck(hz(notes[pattern[k]], 3 + (k % 2)), beat * 1.2, 0.35, seed + bar * 8 + k) * 0.6, t0 + k * beat / 2)
            place(mix, bass(hz(root, 2), beat * 1.8) * 0.5, t0)
            place(mix, bass(hz(notes[2], 2), beat * 1.8) * 0.4, t0 + 2 * beat)
            for k in range(8):
                place(mix, shaker() * (0.25 if k % 2 else 0.15), t0 + k * beat / 2)
        elif style == "menu":
            # slow pad chords with a soft arpeggio on top
            t = t_axis(4 * beat)
            pad = sum(np.sin(2 * np.pi * hz(nm, 3) * t) + 0.5 * np.sin(2 * np.pi * hz(nm, 4) * t * 1.003) for nm in notes)
            pad *= np.minimum(1, np.minimum(t / 0.8, (4 * beat - t) / 0.8))
            place(mix, lowpass(pad, 1200) * 0.12, t0)
            for k in range(4):
                place(mix, pluck(hz(notes[k % 3], 5), beat * 1.5, 0.3, seed + bar * 4 + k) * 0.3, t0 + k * beat + r.uniform(0, 0.02))
    loop = mix[:int(sec * SR)]
    tail = mix[int(sec * SR):int(sec * SR) + SR]
    loop[:len(tail)] += tail                  # wrap the ringing tail to the start: seamless loop
    return loop


def main():
    print("SFX")
    save("engine_car", engine(48.0, 6, 0.5), 0.8)
    save("engine_keke", engine(36.0, 9, 1.4) + 0.3 * engine(72.0, 4, 0.8), 0.8)
    save("engine_truck", engine(30.0, 7, 1.0), 0.85)
    save("horn_car", horn([420, 525], 0.6))
    save("horn_keke", horn([760], 0.55, gaps=[(0.18, 0.28)]))
    save("siren", siren(), 0.7)
    save("skid", skid(), 0.7)
    save("crash", crash())
    save("explosion", explosion())
    save("gunshot", gunshot())
    save("punch", punch())
    save("step_hard_1", step(True, 11), 0.6)
    save("step_hard_2", step(True, 12), 0.6)
    save("step_soft_1", step(False, 13), 0.6)
    save("step_soft_2", step(False, 14), 0.6)
    save("door", door())
    save("cash", chime([1568, 2093, 2637], 0.6, 0.18), 0.7)
    save("ui_click", chime([1200], 0.08, 0.02), 0.5)
    save("ui_confirm", chime([880, 1320], 0.25, 0.08), 0.6)
    print("Ambience")
    save("amb_city_day", amb_city(False), 0.7)
    save("amb_city_night", amb_city(True), 0.6)
    save("amb_market", amb_market(), 0.7)
    save("amb_waves", amb_waves(), 0.7)
    save("amb_rain", amb_rain(), 0.6)
    print("Music")
    save("music_menu", song(72, 16, ["C", "Am", "F", "G"], "menu", 5), 0.75)
    save("radio_highlife", song(124, 32, ["C", "F", "G", "C", "Am", "F", "G", "C"], "highlife", 7), 0.8)
    save("radio_hipco", song(96, 24, ["Am", "F", "C", "G"], "hipco", 9), 0.8)
    save("radio_palmwine", song(88, 24, ["C", "F", "C", "G"], "palmwine", 11), 0.75)
    print("done ->", OUT)


if __name__ == "__main__":
    main()
