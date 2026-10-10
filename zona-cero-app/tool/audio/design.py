"""Zona Cero — sound design build script.

Builds every SfxId / Ambience file from CC0 recordings + synthesis.
Usage: python -I design.py <scratch_root> <assets_audio_dir> [name ...]
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import numpy as np  # noqa: E402

from dsp import *  # noqa: E402,F403
from dsp import SR, db, fade, lufs, mix, secs  # noqa: E402

ROOT = sys.argv[1]
OUT = sys.argv[2]
ONLY = set(sys.argv[3:])
DL = os.path.join(ROOT, "dl")
WAV_OUT = os.path.join(ROOT, "out", "wav")

# ---------------------------------------------------------------------------
# Sources (for CREDITS.md)
# ---------------------------------------------------------------------------

SOURCES = {
    "kenney_ui": ("UI Audio", "Kenney (kenney.nl)", "https://kenney.nl/assets/ui-audio", "CC0 1.0"),
    "kenney_rpg": ("RPG Audio", "Kenney (kenney.nl)", "https://kenney.nl/assets/rpg-audio", "CC0 1.0"),
    "kenney_impact": ("Impact Sounds", "Kenney (kenney.nl)", "https://kenney.nl/assets/impact-sounds", "CC0 1.0"),
    "firearm": ("The Free Firearm Sound Library (Prepared)", "Free Firearm Sound Library team, posted by Bart K.",
                "https://opengameart.org/content/the-free-firearm-sound-library", "CC0 1.0"),
    "ghoul": ("Hungry ghoul", "darsycho", "https://opengameart.org/content/hungry-ghoul", "CC0 1.0"),
    "enemy": ("Enemy sounds", "AbnormalHumanBeing", "https://opengameart.org/content/enemy-sounds", "CC0 1.0"),
    "growls16": ("16 Monster Growls", "StarNinjas", "https://opengameart.org/content/16-monster-growls", "CC0 1.0"),
    "ghostmoans": ("Ghost Monster Voice Moaning & Growling", "qubodup",
                   "https://opengameart.org/content/ghost-monster-voice-moaning-growling", "CC0 1.0"),
    "scream": ("Horror scream1", "vinrax", "https://opengameart.org/content/horror-scream1", "CC0 1.0"),
    "creature": ("80 CC0 creature SFX", "rubberduck", "https://opengameart.org/content/80-cc0-creature-sfx", "CC0 1.0"),
    "creature2": ("80 CC0 creture SFX #2", "rubberduck", "https://opengameart.org/content/80-cc0-creture-sfx-2", "CC0 1.0"),
    "splash": ("40 CC0 water / splash / slime SFX", "rubberduck",
               "https://opengameart.org/content/40-cc0-water-splash-slime-sfx", "CC0 1.0"),
    "mud": ("25 CC0 mud sfx", "rubberduck", "https://opengameart.org/content/25-cc0-mud-sfx", "CC0 1.0"),
    "rain2": ("AMB Rain Loop 2", "Kresiek the Furry", "https://opengameart.org/content/amb-rain-loop-2", "CC0 1.0"),
    "gutter": ("Rain in the Gutter Loop", "ogrebane", "https://opengameart.org/content/rain-gutter-loop", "CC0 1.0"),
    "synth": ("Original synthesis (numpy/scipy)", "Zona Cero audio", "—", "Original work, part of this project"),
}

USED: dict[str, set[str]] = {}
NOTES: dict[str, str] = {}


def use(name: str, *keys: str):
    USED.setdefault(name, set()).update(keys)


# ---------------------------------------------------------------------------
# Source loaders
# ---------------------------------------------------------------------------

def K(pack: str, f: str) -> np.ndarray:
    folder = {"ui": "kenney_ui-audio", "rpg": "kenney_rpg-audio", "imp": "kenney_impact-sounds",
              "if": "kenney_interface-sounds"}[pack]
    return load(os.path.join(DL, "kenney", folder, "Audio", f))


def O(rel: str, start=None, dur=None, mono=True) -> np.ndarray:
    return load(os.path.join(DL, "oga", rel), start=start, dur=dur, mono=mono)


def seg(kind: str, i: int) -> np.ndarray:
    return load(os.path.join(ROOT, "seg", kind, f"{kind}_{i:02d}.wav"))


FIRE = os.path.join(DL, "oga", "firearm", "x", "Prepared SFX Library")


def gunshot(rel: str, n: int = 0, pre: float = 0.004, dur: float = 1.6) -> np.ndarray:
    x = load(os.path.join(FIRE, rel))
    from scipy.signal import find_peaks
    env = np.abs(x)
    pk, _ = find_peaks(env, height=0.4 * env.max(), distance=int(0.5 * SR))
    p = pk[n]
    # walk back to the onset (first sample above 2% of the peak within 20 ms)
    a = p - secs(0.02)
    on = a + int(np.argmax(env[a:p] > 0.02 * env[p]))
    return x[max(0, on - secs(pre)): on + secs(dur)]


def r(seed):
    return rng(seed)


# ---------------------------------------------------------------------------
# Shared processing
# ---------------------------------------------------------------------------

def body(x, f=160, g=3.0):
    """Phone-speaker friendly low end: add harmonics of sub layers."""
    return x + hp(drive(lp(x, f * 1.5), 3.0), f * 0.7) * db(g - 6)


def tail_env(dur, hold, tau):
    """Flat for `hold` seconds then exponential decay (keeps gunshot tails from being pumped)."""
    t = np.arange(secs(dur)) / SR
    e = np.exp(-np.maximum(t - hold, 0) / tau)
    return fade(e, 0, 0.05)


def sub_boom(f0=70, f1=38, dur=0.9, tau=0.25, seed=0, click=True):
    """Low boom with saturation harmonics (audible on phones) and a noise click."""
    f = glide(f0, f1, dur)
    y = osc(f) * env_exp(dur, tau, 0.002)
    y = drive(y * 1.4, 2.2)
    if click:
        c = lp(white(dur, r(seed)), 1800) * env_exp(dur, 0.012, 0.0005) * 0.8
        y = y + c
    return y


def finish(name, x, target=-16.0, ceiling=-1.0, hpf=30, tail_rel=-58, fin=0.0008, fout=0.03):
    """HPF, peak-relative trim, fades, then iterative LUFS normalisation through a look-ahead limiter."""
    x = hp(x, hpf, 2)
    x = norm_peak(x, -1.0)
    x = trim(x, tail_rel, pre=0.0015, post=0.05)
    x = fade(x, fin, min(fout, len(x) / SR * 0.25))
    src = x
    gain = target - lufs(src)
    for _ in range(4):
        y = limiter(src * db(gain), ceiling, release=0.05)
        err = target - lufs(y)
        if abs(err) < 0.25:
            break
        gain += err
        gain = min(gain, target - lufs(src) + 6.0)  # never squash more than ~6 dB
    y = fade(y, 0, min(0.015, len(y) / SR * 0.2))
    return y


def finish_amb(x, target=-22.0, ceiling=-3.0):
    L = lufs(x)
    x = x * db(target - L)
    return limiter(x, ceiling, release=0.2)


def room(x, decay=0.5, mix=0.15, damp=3500, seed=11):
    return reverb(x, decay=decay, mix=mix, damp=damp, seed=seed, predelay=0.006)


def hall(x, decay=2.4, mix=0.3, damp=3200, seed=21, predelay=0.02):
    return reverb(x, decay=decay, mix=mix, damp=damp, seed=seed, predelay=predelay)


def radio(x, seed=4):
    y = bp(x, 320, 3400, 2)
    y = drive(y * 2.0, 1.8)
    y = crush(y, 10)
    crack = (r(seed).random(len(y)) < 0.0015) * r(seed + 1).uniform(-0.5, 0.5, len(y))
    return y + hp(crack, 2000)


REG: dict[str, tuple] = {}


def sfx(name, target=-16.0, kbps=128, note=""):
    def deco(fn):
        REG[name] = ("sfx", fn, target, kbps)
        NOTES[name] = note or (fn.__doc__ or "").strip()
        return fn
    return deco


def amb(name, kbps=160, note=""):
    def deco(fn):
        REG[name] = ("amb", fn, -22.0, kbps)
        NOTES[name] = note or (fn.__doc__ or "").strip()
        return fn
    return deco


# ===========================================================================
# UI
# ===========================================================================

@sfx("ui_tap", target=-21)
def ui_tap():
    """Recorded mechanical switch (Kenney) trimmed to its transient + a dark 1.6 kHz terminal tick and a 190 Hz body thump."""
    use("ui_tap", "kenney_ui", "synth")
    c = trim(K("ui", "switch2.ogg"), -40)[: secs(0.06)]
    c = lp(hp(c, 350), 8000)
    tick = osc(glide(1700, 1550, 0.03)) * env_exp(0.03, 0.005, 0.0006)
    thump = osc(glide(210, 160, 0.04)) * env_exp(0.04, 0.012, 0.001)
    return mix(0.09, (c, 0, 0), (tick, 0.001, -9), (thump, 0, -8))


@sfx("ui_tab", target=-20)
def ui_tab():
    """Heavier switch click (Kenney) + short radio chirp (900→1350 Hz) through a band-limited 'terminal' filter, tiny room."""
    use("ui_tab", "kenney_ui", "synth")
    c = trim(K("ui", "switch7.ogg"), -40)[: secs(0.08)]
    c = lp(hp(c, 250), 7500)
    ch = osc(glide(900, 1350, 0.07), kind="tri") * env_points(0.07, [(0, 0), (0.008, 1), (0.05, 0.6), (0.07, 0)])
    ch = bp(ch, 500, 3000)
    nz = bp(white(0.05, r(3)), 1500, 5000) * env_exp(0.05, 0.01)
    y = mix(0.2, (c, 0, 0), (ch, 0.012, -10), (nz, 0.01, -18))
    return room(y, 0.35, 0.12)


@sfx("ui_open", target=-19)
def ui_open():
    """Holographic panel open: rising band-passed noise whoosh, low thud (Kenney impact) and a two-note shimmer (E6/B6) with chorus + short hall."""
    use("ui_open", "kenney_impact", "kenney_ui", "synth")
    d = 0.55
    w = sweep_filter(white(d, r(5)), 350, 3200, "bp", q=2.5) * env_points(d, [(0, 0), (0.25, 1), (0.42, 0.4), (d, 0)])
    th = lp(K("imp", "impactPunch_heavy_000.ogg"), 220)[: secs(0.3)]
    tones = (osc(1318.5, 0.35) * env_exp(0.35, 0.09, 0.004) + osc(1975.5, 0.35) * env_exp(0.35, 0.07, 0.004) * 0.6)
    tones = chorus(tones, 0.002, 1.3, 0.5)
    c = lp(hp(trim(K("ui", "switch2.ogg"), -40)[: secs(0.05)], 400), 7000)
    y = mix(0.75, (w, 0, -6), (th, 0, -4), (c, 0, -6), (tones, 0.16, -14), (tones * 0.7, 0.26, -18))
    return hall(y, 0.9, 0.22, 4500)


@sfx("ui_error", target=-17)
def ui_error():
    """'Denied' double buzz: two detuned square pulses (110/98 Hz) with drive, band-limited to 140–2600 Hz, plus a relay click."""
    use("ui_error", "kenney_ui", "synth")

    def pulse(f, d=0.095):
        y = osc(f, d, "square") * 0.6 + osc(f * 1.007, d, "saw") * 0.5
        y = drive(y, 2.5) * env_points(d, [(0, 0), (0.004, 1), (d - 0.015, 0.8), (d, 0)])
        return bp(y, 140, 2600)
    c = lp(hp(trim(K("ui", "switch7.ogg"), -40)[: secs(0.05)], 300), 6000)
    y = mix(0.33, (c, 0, -6), (pulse(110), 0.004, 0), (pulse(98), 0.135, -1))
    return room(y, 0.3, 0.1)


# ===========================================================================
# Map
# ===========================================================================

@sfx("scan_charge", target=-17)
def scan_charge():
    """Capacitor charge-up: exponential sine/triangle sweep 180→1650 Hz with accelerating tremolo, noise riser and sub swell, ending in a lock click."""
    use("scan_charge", "kenney_ui", "synth")
    d = 1.25
    f = glide(180, 1650, d)
    trem_rate = glide(7, 34, d)
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * np.cumsum(trem_rate) / SR)
    tone = (osc(f) + 0.35 * osc(f * 2.0, kind="tri") + 0.15 * osc(f * 0.5)) * trem
    e = env_points(d, [(0, 0), (0.15, 0.25), (1.05, 1.0), (1.18, 0.85), (d, 0)], curve=1.4)
    nz = sweep_filter(white(d, r(9)), 500, 6000, "bp", q=3) * env_points(d, [(0, 0), (1.1, 1), (d, 0)])
    sub = drive(osc(glide(38, 82, d)) * env_points(d, [(0, 0), (1.1, 1), (d, 0)]), 2.0)
    c = lp(hp(trim(K("ui", "switch7.ogg"), -40)[: secs(0.06)], 300), 7000)
    y = mix(1.45, (tone * e, 0, -6), (nz, 0, -16), (sub, 0, -10), (c, 1.17, -4))
    return room(y, 0.5, 0.15)


@sfx("scan_pulse", target=-16)
def scan_pulse():
    """Hero sonar pulse: saturated sub boom (72→36 Hz), inharmonic bell ping at 1150 Hz with outbound noise sweep, sonar echo taps and a 3 s dark hall."""
    use("scan_pulse", "synth")
    d = 1.6
    boom = sub_boom(72, 36, d, 0.32, seed=12)
    f = glide(1160, 1090, d)
    ping = (osc(f) + 0.28 * osc(f * 2.76) + 0.12 * osc(f * 5.4) + 0.4 * osc(f * 0.5)) * env_exp(d, 0.42, 0.003)
    ping = ping * (1 + 0.15 * np.sin(2 * np.pi * 5.5 * np.arange(len(ping)) / SR))
    sweep = sweep_filter(white(1.3, r(13)), 3200, 280, "bp", q=4) * env_points(1.3, [(0, 0), (0.05, 1), (1.3, 0)])
    dry = mix(d + 0.2, (boom, 0, -2), (ping, 0.004, -7), (sweep, 0.02, -15))
    tail = echo(lp(ping, 2500) * 0.6, 0.42, 0.42, 4, 1800)
    y = mix(3.0, (dry, 0, 0), (tail, 0.42, -12))
    return hall(y, 3.0, 0.38, 3000, predelay=0.03)


@sfx("contact_ping", target=-19)
def contact_ping():
    """Radar contact blip: two short FM-wobbled pings (1320 Hz then 990 Hz) with a soft click, short hall tail."""
    use("contact_ping", "synth")

    def p(f, d=0.22):
        vib = 1 + 0.004 * np.sin(2 * np.pi * 28 * np.arange(secs(d)) / SR)
        return (osc(f * vib) + 0.2 * osc(f * 2.01, d)) * env_exp(d, 0.05, 0.002)
    click = hp(white(0.01, r(17)), 2500) * env_exp(0.01, 0.0015)
    y = mix(0.5, (click, 0, -14), (p(1320), 0.001, 0), (p(990), 0.085, -3))
    return hall(y, 1.0, 0.28, 4000)


@sfx("signal_radio", target=-17)
def signal_radio():
    """Distress-signal pickup: squelch burst, tuning sweep, three Morse-like 1 kHz beeps, crackle and a closing squelch, all through a band-limited, driven 'radio' chain."""
    use("signal_radio", "synth")
    d = 1.7
    rr = r(31)
    sq1 = white(0.16, rr) * env_points(0.16, [(0, 0), (0.005, 1), (0.1, 0.7), (0.16, 0)])
    tune = osc(glide(520, 1900, 0.32), kind="tri") * env_points(0.32, [(0, 0), (0.03, 1), (0.28, 0.8), (0.32, 0)])
    tune = tune * (0.6 + 0.4 * np.sin(2 * np.pi * 17 * np.arange(len(tune)) / SR))
    beeps = []
    for i, (t0, L) in enumerate([(0.62, 0.08), (0.74, 0.08), (0.86, 0.2)]):
        b = osc(1000, L, "square") * env_points(L, [(0, 0), (0.004, 1), (L - 0.006, 1), (L, 0)])
        beeps.append((b, t0, -6))
    hiss = white(d, rr) * env_points(d, [(0, 0.15), (1.2, 0.12), (d, 0)])
    sq2 = white(0.3, rr) * env_points(0.3, [(0, 0), (0.01, 1), (0.3, 0)], curve=2)
    raw = mix(d, (sq1, 0, -2), (tune, 0.14, -8), *beeps, (hiss, 0, -14), (sq2, 1.18, -4))
    y = radio(raw, 33)
    return room(y, 0.45, 0.12)


@sfx("loot", target=-16)
def loot():
    """Rummage: cloth and leather handling (Kenney RPG), a metal latch clink and a subdued low 'reward' fifth (G2/D3) underneath."""
    use("loot", "kenney_rpg", "synth")
    cl = K("rpg", "cloth1.ogg")[: secs(0.5)]
    lea = K("rpg", "handleSmallLeather.ogg")
    lat = trim(K("rpg", "metalLatch.ogg"), -45)
    belt = trim(K("rpg", "beltHandle1.ogg"), -45)
    tone = (osc(98.0, 0.8) + 0.7 * osc(146.8, 0.8) + 0.25 * osc(196, 0.8, "tri")) * env_points(0.8, [(0, 0), (0.12, 1), (0.8, 0)])
    tone = body(tone, 140, 2)
    y = mix(1.4, (cl, 0, -2), (lea, 0.05, 2), (belt, 0.16, -3), (lat, 0.34, -5), (tone, 0.3, -27))
    return room(y, 0.45, 0.14)


@sfx("deliver", target=-16)
def deliver():
    """Crate set down at the node: wood plank + steel plate impacts (Kenney), latch, and a warm A-major swell (A2/C#3/E3) with soft hall."""
    use("deliver", "kenney_impact", "kenney_rpg", "synth")
    wood = K("imp", "impactPlank_medium_000.ogg")
    plate = K("imp", "impactPlate_heavy_002.ogg")
    lat = trim(K("rpg", "metalLatch.ogg"), -45)
    d = 1.1
    ch = sum(osc(f, d, "saw") * g for f, g in [(110, 1.0), (138.6, 0.6), (164.8, 0.7), (220, 0.35)])
    ch = lp(ch, 900) * env_points(d, [(0, 0), (0.25, 1), (0.6, 0.7), (d, 0)])
    y = mix(1.4, (wood, 0, 0), (plate, 0.012, -9), (sub_boom(80, 50, 0.4, 0.1, 41), 0, -10), (lat, 0.27, -5), (ch, 0.18, -17))
    return hall(y, 1.4, 0.18, 3500)


@sfx("level_up", target=-16)
def level_up():
    """Cinematic rank-up: reversed-noise riser into a saturated boom, open D-major low chord with filter sweep, inharmonic bell partials and a 3 s hall."""
    use("level_up", "kenney_impact", "synth")
    rr = r(51)
    rise = hp(white(0.6, rr), 1800) * env_points(0.6, [(0, 0), (0.58, 1), (0.6, 0)], curve=2.5)
    hit = sub_boom(62, 34, 1.2, 0.35, 52)
    punch = lp(K("imp", "impactPunch_heavy_000.ogg"), 600)
    d = 2.3
    notes = [73.4, 110.0, 146.8, 185.0, 220.0, 293.7]
    pad = sum(osc(f * (1 + dt), d, "saw") for f in notes for dt in (-0.003, 0.0, 0.004)) / 6
    cut = np.concatenate([glide(350, 2600, 1.0), glide(2600, 900, d - 1.0)])[: secs(d)]
    pad = svf(pad, cut, 0.9, "lp") * env_points(d, [(0, 0), (0.08, 1), (1.4, 0.7), (d, 0)])
    bell_f = 1174.7
    bell = sum(osc(bell_f * k, 2.0) * g * env_exp(2.0, 0.9 / k ** 0.5, 0.003) for k, g in [(1, 1), (2.01, 0.4), (2.76, 0.3), (4.1, 0.15)])
    y = mix(3.2, (rise, 0, -10), (hit, 0.6, -1), (punch, 0.6, -6), (pad, 0.6, -8), (bell, 0.62, -17), (bell * 0.6, 0.95, -22))
    return hall(y, 3.0, 0.3, 3500)


# ===========================================================================
# Creatures
# ===========================================================================

@sfx("zombie_groan", target=-16)
def zombie_groan():
    """Caminante: long raspy ghoul moan (darsycho) varispeeded to 0.82× over a tonal ghost-moan layer (qubodup) at 0.7×, chest EQ, grit and a small dark room."""
    use("zombie_groan", "ghoul", "ghostmoans")
    a = pitch_resample(seg("ghoul", 6), 0.82)
    m = pitch_resample(O("ghostmoans/x/qubodup-GhostMoans/wav/qubodup-GhostMoan01.wav", 0.5, 2.0), 0.7)
    m = lp(m, 2500)
    y = mix(2.6, (a, 0, 0), (m, 0.05, -9))
    y = y * env_points(2.6, [(0, 1), (2.1, 1), (2.6, 0)])
    y = hp(y, 70)
    y = peq(y, 260, 3.5, 0.9)
    y = peq(y, 3200, -4, 1.0)
    y = drive(y * 1.3, 1.6)
    return room(y, 0.6, 0.16)


@sfx("zombie_attack", target=-15)
def zombie_attack():
    """Lunge and bite: aggressive ghoul snarl at 0.9× + 'enemy' snarl layer, lunge whoosh (Kenney knife slice, low-passed), punch impact and wet squelch."""
    use("zombie_attack", "ghoul", "enemy", "kenney_rpg", "kenney_impact", "splash")
    v = pitch_resample(seg("ghoul", 7), 0.9)
    s = pitch_resample(seg("enemy", 8), 0.92)
    wh = lp(K("rpg", "knifeSlice.ogg"), 2600)
    hit = K("imp", "impactPunch_medium_002.ogg")
    wet = trim(O("splash40/x/slime_03.ogg"), -45)
    y = mix(1.2, (wh, 0, -6), (v, 0.02, 0), (s, 0.05, -5), (hit, 0.36, -3), (wet, 0.37, -7))
    y = drive(y * 1.2, 1.5)
    y = peq(y, 1800, 2.5, 1.2)
    return room(y, 0.5, 0.12)


@sfx("zombie_hurt", target=-16)
def zombie_hurt():
    """Short pained grunt (ghoul take at 0.85×) over a heavy body punch (Kenney) and a small wet splat."""
    use("zombie_hurt", "ghoul", "kenney_impact", "splash")
    v = pitch_resample(seg("ghoul", 9)[: secs(0.5)], 0.85)
    v = v * env_points(len(v) / SR, [(0, 1), (0.4, 1), (len(v) / SR, 0)])
    hit = K("imp", "impactPunch_heavy_000.ogg")
    wet = trim(O("splash40/x/slime_07.ogg"), -45)
    y = mix(0.75, (hit, 0, -2), (wet, 0.005, -9), (v, 0.03, 0))
    y = drive(y * 1.1, 1.4)
    return room(y, 0.45, 0.12)


@sfx("zombie_death", target=-16)
def zombie_death():
    """Death: falling-off ghoul moan at 0.8×, a pitched-down bubbling gurgle, then a body collapse (Kenney soft + punch impacts) in a dark room."""
    use("zombie_death", "ghoul", "splash", "kenney_impact")
    v = pitch_resample(seg("ghoul", 12), 0.8)[: secs(2.2)]
    v = v * env_points(2.2, [(0, 1), (1.5, 0.9), (2.2, 0)])
    g = pitch_resample(trim(O("splash40/x/bubble_01.ogg"), -45), 0.6)
    fall1 = K("imp", "impactSoft_heavy_001.ogg")
    fall2 = lp(K("imp", "impactPunch_heavy_000.ogg"), 900)
    y = mix(3.0, (v, 0, 0), (g, 0.9, -9), (fall1, 1.95, -2), (fall2, 1.97, -5), (sub_boom(60, 40, 0.5, 0.12, 61), 1.95, -9))
    y = hp(y, 60)
    y = drive(y * 1.1, 1.3)
    return room(y, 0.7, 0.16)


@sfx("screamer_scream", target=-15)
def screamer_scream():
    """Chillón: horror scream (vinrax) layered with a rubberduck scream at 1.25×, a 1.7 kHz ring-modulated inhuman edge, presence boost, drive and a 1.6 s hall."""
    use("screamer_scream", "scream", "creature")
    a = O("scream1/scream_horror1_0.mp3", 0.9, 2.1)
    b = pitch_resample(O("creature1/x/scream_01.ogg"), 1.25)
    ring = ringmod(hp(a, 600), 1700)
    y = mix(2.2, (a, 0, 0), (b, 0.05, -6), (ring, 0, -14))
    y = y * env_points(2.2, [(0, 0), (0.02, 1), (1.6, 0.9), (2.2, 0)])
    y = shelf(y, 2800, 4, True)
    y = peq(y, 400, -3, 1.0)
    y = drive(y * 1.2, 1.4)
    return hall(y, 1.6, 0.24, 5000)


@sfx("brute_roar", target=-16)
def brute_roar():
    """Bruto: two monster growls (StarNinjas) and an 'enemy' roar varispeeded to 0.62–0.7×, a saturated 46 Hz sub-growl following the voice envelope, chest resonance and hall."""
    use("brute_roar", "growls16", "enemy", "synth")
    a = pitch_resample(O("growls16/x/monster.8.ogg"), 0.62)
    b = pitch_resample(O("growls16/x/monster.11.ogg"), 0.65)
    c = pitch_resample(seg("enemy", 7), 0.7)
    d = 2.6
    y = mix(d, (a, 0, 0), (b, 0.08, -3), (c, 0.0, -4))
    env = np.convolve(np.abs(y), np.ones(secs(0.03)) / secs(0.03), "same")
    env = env / (env.max() + 1e-9)
    sub = drive(osc(46 + 6 * np.sin(2 * np.pi * 9 * np.arange(len(y)) / SR) * env, kind="saw") * env, 2.5)
    sub = lp(sub, 220)
    y = y + sub * db(-6)
    y = y * env_points(d, [(0, 1), (2.1, 1), (d, 0)])
    y = lp(hp(y, 40), 6500)
    y = peq(y, 120, 5, 0.8)
    y = drive(y * 1.2, 1.5)
    return hall(y, 1.8, 0.2, 2800)


@sfx("bloater_burst", target=-15)
def bloater_burst():
    """Hinchado: gurgling moan (ghoul at 0.7×) and bubbling mud, then a wet burst (splash + mud splatters + saturated low boom) with dripping debris."""
    use("bloater_burst", "ghoul", "splash", "mud", "kenney_impact", "synth")
    gm = pitch_resample(seg("ghoul", 10)[: secs(0.75)], 0.7)
    gm = gm * env_points(len(gm) / SR, [(0, 0), (0.1, 1), (len(gm) / SR, 0.3)])
    bub = pitch_resample(trim(O("splash40/x/bubble_02.ogg"), -45), 0.7)
    mud1 = pitch_resample(trim(O("mud25/x/mud_04.ogg"), -45), 0.75)
    sp = trim(O("splash40/x/splash_05.ogg"), -45)
    sp2 = pitch_resample(trim(O("splash40/x/splash_11.ogg"), -45), 0.8)
    mud2 = trim(O("mud25/x/mud_12.ogg"), -45)
    boom = sub_boom(64, 30, 0.8, 0.22, 71)
    soft = K("imp", "impactSoft_heavy_001.ogg")
    drips = [(pitch_resample(trim(O(f"splash40/x/slime_{k:02d}.ogg"), -45), 0.9 + 0.1 * i), 1.15 + 0.17 * i, -14 - 2 * i)
             for i, k in enumerate((2, 9, 12))]
    y = mix(2.1, (gm, 0, -2), (bub, 0.05, -8), (mud1, 0.35, -8), (sp, 0.82, 0), (sp2, 0.83, -3), (mud2, 0.86, -4),
            (boom, 0.8, -2), (soft, 0.8, -4), *drips)
    y = drive(y * 1.1, 1.4)
    return room(y, 0.6, 0.15)


@sfx("runner_snarl", target=-15)
def runner_snarl():
    """Corredor: fast snarl — monster growl (StarNinjas) at 1.12×, 'enemy' snarl and a rubberduck attack bark, hard drive with 1–3 kHz aggression peak."""
    use("runner_snarl", "growls16", "enemy", "creature2")
    a = pitch_resample(O("growls16/x/monster.13.ogg"), 1.12)
    b = seg("enemy", 6)[: secs(0.8)]
    c = O("creature2/x/attack_04.ogg")
    y = mix(1.1, (a, 0, 0), (b, 0.03, -5), (c, 0.0, -7))
    y = y * env_points(1.1, [(0, 1), (0.8, 1), (1.1, 0)])
    y = hp(y, 90)
    y = peq(y, 2000, 3.5, 0.9)
    y = drive(y * 1.5, 1.8)
    return room(y, 0.4, 0.12)


# ===========================================================================
# Player
# ===========================================================================

@sfx("pistol_shot", target=-15)
def pistol_shot():
    """.45 1911 at near distance (Free Firearm Library, 96 kHz) + the mid-distance take for urban slapback, saturated sub punch and transient crack; soft-clipped."""
    use("pistol_shot", "firearm", "synth")
    near = gunshot("1911/A_42P.wav", 0, dur=1.3)
    mid = gunshot("1911/A_34P.wav", 0, dur=1.3)
    crack = hp(white(0.008, r(81)), 2500) * env_exp(0.008, 0.0015, 0.0002)
    sub = sub_boom(85, 45, 0.25, 0.06, 82, click=False)
    y = mix(1.3, (near, 0, 0), (mid, 0.003, -10), (sub, 0, -5), (crack, 0, -10))
    y = drive(y * 2.2, 2.0)  # soft-clip the muzzle blast
    y = y * tail_env(1.3, 0.05, 0.26)
    y = lp(y, 15000)
    return y


@sfx("shotgun_shot", target=-14.5)
def shotgun_shot():
    """12-gauge Benelli Nova at near distance (Free Firearm Library) + Model 12 mid-distance tail, heavy saturated sub thump; soft-clipped and long tail."""
    use("shotgun_shot", "firearm", "synth")
    near = gunshot("Nova/O_21P.wav", 0, dur=1.8)
    mid = gunshot("Model 12/K_17P.wav", 0, dur=1.8)
    sub = sub_boom(70, 32, 0.6, 0.12, 91, click=False)
    y = mix(1.8, (near, 0, 0), (mid, 0.004, -7), (sub, 0, -2))
    y = drive(y * 2.2, 2.0)
    y = y * tail_env(1.8, 0.08, 0.38)
    y = lp(y, 14000)
    return y


@sfx("melee_swing", target=-17)
def melee_swing():
    """Heavy whoosh: white noise through a state-variable band-pass sweeping 450→2300→650 Hz with a bell envelope, plus a low air layer for weight."""
    use("melee_swing", "synth")
    d = 0.42
    n = white(d, r(101))
    f = np.concatenate([glide(450, 2300, 0.17), glide(2300, 650, d - 0.17)])[: secs(d)]
    w = svf(n, f, 1.6, "bp")
    e = env_points(d, [(0, 0), (0.15, 1), (0.3, 0.35), (d, 0)], curve=1.5)
    air = lp(n, 380) * env_points(d, [(0, 0), (0.16, 1), (d, 0)])
    return mix(d, (w * e, 0, 0), (air, 0, -6))


@sfx("melee_impact", target=-15)
def melee_impact():
    """Blunt hit: heavy punch + chop crunch (Kenney), synthetic bone crackle (sparse impulses band-passed 1.5–5 kHz), wet flesh splat and saturated sub."""
    use("melee_impact", "kenney_impact", "kenney_rpg", "splash", "synth")
    p = K("imp", "impactPunch_heavy_000.ogg")
    ch = trim(K("rpg", "chop.ogg"), -45)
    rr = r(111)
    crk = (rr.random(secs(0.05)) < 0.04) * rr.uniform(-1, 1, secs(0.05))
    crk = bp(crk, 1500, 5000) * env_exp(0.05, 0.015)
    wet = trim(O("splash40/x/slime_05.ogg"), -45)
    y = mix(0.7, (p, 0, 0), (ch, 0.003, -3), (crk, 0.004, -6), (wet, 0.01, -10), (sub_boom(90, 50, 0.3, 0.06, 112), 0, -6))
    y = drive(y * 1.3, 1.6)
    return room(y, 0.4, 0.12)


@sfx("headshot", target=-15)
def headshot():
    """Headshot: sharp skull crack (layered synthetic crackle + chop), medium punch, big wet splatter (rubberduck splash) and a dull thump, short room."""
    use("headshot", "kenney_impact", "kenney_rpg", "splash", "synth")
    rr = r(121)
    crk = (rr.random(secs(0.08)) < 0.06) * rr.uniform(-1, 1, secs(0.08))
    crk = hp(crk, 1200) * env_exp(0.08, 0.02)
    ch = trim(K("rpg", "chop.ogg"), -45)
    p = K("imp", "impactPunch_medium_002.ogg")
    sp = trim(O("splash40/x/splash_09.ogg"), -45)
    sp2 = trim(O("splash40/x/slime_11.ogg"), -45)
    y = mix(1.0, (crk, 0, -2), (ch, 0, -2), (p, 0.002, -2), (sp, 0.02, -3), (sp2, 0.1, -9), (sub_boom(110, 55, 0.3, 0.05, 122), 0, -7))
    y = drive(y * 1.3, 1.6)
    return room(y, 0.5, 0.14)


@sfx("empty_click", target=-20)
def empty_click():
    """Dry-fire: two mechanical clicks (Kenney switch + metal click) high-passed, almost no room — the dreaded empty chamber."""
    use("empty_click", "kenney_ui", "kenney_rpg")
    a = hp(trim(K("ui", "switch7.ogg"), -40)[: secs(0.06)], 300)
    b = hp(trim(K("rpg", "metalClick.ogg"), -45)[: secs(0.08)], 250)
    y = mix(0.2, (a, 0, 0), (b, 0.045, -2))
    return room(y, 0.25, 0.08)


@sfx("player_hurt", target=-16)
def player_hurt():
    """Taking a hit: heavy body punch (Kenney), low 'whump' + sub, a muffled heartbeat thump and a 3.6 kHz tinnitus ring that fades out."""
    use("player_hurt", "kenney_impact", "synth")
    p = K("imp", "impactPunch_heavy_000.ogg")
    wh = lp(white(0.3, r(131)), 500) * env_exp(0.3, 0.06, 0.003)
    hb = sub_boom(60, 42, 0.3, 0.07, 132, click=False)
    ring = osc(3620, 1.2) * env_points(1.2, [(0, 0), (0.06, 1), (0.4, 0.6), (1.2, 0)], curve=1.5)
    y = mix(1.3, (p, 0, 0), (wh, 0, -4), (sub_boom(75, 40, 0.4, 0.09, 133), 0, -4), (hb, 0.32, -6), (ring, 0.02, -24))
    y = drive(y * 1.2, 1.4)
    return room(y, 0.4, 0.1)


@sfx("heal", target=-17)
def heal():
    """Medkit: velcro/strap rustle (Kenney cloth belt), a glass vial tink, injector hiss and a warm rising tone (D4→A4) with chorus."""
    use("heal", "kenney_rpg", "kenney_impact", "synth")
    belt = K("rpg", "clothBelt.ogg")[: secs(0.45)]
    gl = K("imp", "impactGlass_light_002.ogg")
    hiss = hp(white(0.22, r(141)), 3500) * env_points(0.22, [(0, 0), (0.01, 1), (0.22, 0)], curve=2)
    d = 0.9
    tone = (osc(glide(293.7, 440, d)) + 0.4 * osc(glide(587.3, 880, d), kind="tri")) * env_points(d, [(0, 0), (0.3, 1), (d, 0)])
    tone = lp(chorus(tone, 0.002, 0.9, 0.4), 1800)
    y = mix(1.6, (belt, 0, -1), (gl, 0.38, -8), (hiss, 0.45, -10), (tone, 0.5, -18))
    return room(y, 0.7, 0.18)


@sfx("defend", target=-16)
def defend():
    """Brace/block: cloth swish, heavy steel plate + wood impacts (Kenney) and a low thump."""
    use("defend", "kenney_rpg", "kenney_impact", "synth")
    sw = K("rpg", "cloth1.ogg")[: secs(0.2)]
    plate = K("imp", "impactPlate_heavy_002.ogg")
    wood = K("imp", "impactWood_heavy_003.ogg")
    y = mix(0.75, (sw, 0, -6), (plate, 0.08, 0), (wood, 0.082, -3), (sub_boom(90, 55, 0.3, 0.06, 151), 0.08, -6))
    y = compress(y, -22, 3.0, 0.001, 0.08)
    return room(y, 0.45, 0.12)


@sfx("flee", target=-17)
def flee():
    """Retreat: quick whoosh then six concrete footsteps (Kenney) accelerating away — each step quieter and darker (receding), ending in silence."""
    use("flee", "kenney_impact", "synth")
    wh = svf(white(0.3, r(161)), glide(1800, 400, 0.3), 1.2, "bp") * env_points(0.3, [(0, 0), (0.08, 1), (0.3, 0)])
    layers = [(wh, 0, -10)]
    times = [0.08, 0.32, 0.54, 0.74, 0.92, 1.08]
    for i, t in enumerate(times):
        st = K("imp", f"footstep_concrete_00{i % 5}.ogg")
        st = lp(st, 9000 * (0.62 ** i) + 600)
        layers.append((st, t, -2 - 2.6 * i))
    y = mix(1.4, *layers)
    y = compress(y, -24, 3.0, 0.001, 0.06)
    return room(y, 0.6, 0.18)


@sfx("victory", target=-16)
def victory():
    """Survived: taiko-like low hit, then an A-minor swell that resolves to A major (Picardy third) with filter bloom, high bell partials and a dark hall."""
    use("victory", "synth")
    hit = sub_boom(68, 40, 1.0, 0.3, 171) + lp(white(1.0, r(172)), 700) * env_exp(1.0, 0.05, 0.001) * 0.5
    d1, d2 = 0.7, 1.8

    def chord(freqs, d, cut0, cut1):
        y = sum(osc(f * (1 + dt), d, "saw") for f in freqs for dt in (-0.004, 0.003)) / len(freqs)
        return svf(y, glide(cut0, cut1, d), 0.8, "lp")
    am = chord([110, 164.8, 220, 261.6], d1, 300, 1200) * env_points(d1, [(0, 0), (0.15, 1), (d1, 0.9)])
    A = chord([110, 164.8, 220, 277.2, 329.6], d2, 1200, 2600) * env_points(d2, [(0, 0.9), (0.4, 1), (d2, 0)])
    bell = sum(osc(880 * k, 1.8) * g * env_exp(1.8, 0.8 / k, 0.002) for k, g in [(1, 1), (1.5, 0.5), (2.76, 0.2)])
    y = mix(3.0, (hit, 0, 0), (am, 0.05, -8), (A, 0.05 + d1, -7), (bell, 0.05 + d1, -18))
    return hall(y, 2.8, 0.32, 3200)


@sfx("defeat", target=-16)
def defeat():
    """Fallen: boom, a detuned saw drone gliding down 110→65 Hz with a minor-second cluster, slowing heartbeats and a distant low moan; filter closes into the hall."""
    use("defeat", "ghostmoans", "synth")
    d = 3.0
    f = glide(110, 65, d)
    drone = sum(osc(f * m, kind="saw") for m in (1.0, 1.0045, 1.059)) / 3
    drone = svf(drone, glide(1400, 220, d), 0.9, "lp") * env_points(d, [(0, 0), (0.15, 1), (2.2, 0.7), (d, 0)])

    def beat(g):
        return sub_boom(58, 40, 0.25, 0.06, 181, click=False) * db(g)
    moan = lp(pitch_resample(O("ghostmoans/x/qubodup-GhostMoans/wav/qubodup-GhostMoan03.wav", 1.0, 2.0), 0.6), 900)
    y = mix(3.4, (sub_boom(55, 30, 1.2, 0.4, 182), 0, 0), (drone, 0, -6), (beat(0), 0.5, -4), (beat(-3), 0.78, -6),
            (beat(-5), 1.6, -6), (beat(-8), 1.88, -8), (beat(-12), 2.9, -8), (moan, 0.6, -16))
    return hall(y, 2.6, 0.3, 2500)


@sfx("heartbeat", target=-16)
def heartbeat():
    """Single lub-dub: two saturated sub thumps (56→42 Hz, 50→38 Hz) with 140 Hz chest body and a soft valve click — audible on phone speakers."""
    use("heartbeat", "synth")

    def thump(f0, f1, seed):
        y = osc(glide(f0, f1, 0.22)) * env_exp(0.22, 0.055, 0.004)
        y = drive(y * 1.6, 2.4)
        chest = bp(white(0.22, r(seed)), 80, 260) * env_exp(0.22, 0.035, 0.002)
        return y + chest * 0.6
    y = mix(0.75, (thump(56, 42, 191), 0, 0), (thump(50, 38, 192), 0.27, -3))
    y = body(y, 140, 4)
    return lp(y, 1600)


# ===========================================================================
# Ambience (stereo, seamless loops)
# ===========================================================================

def siren(dur, f_lo=640, f_hi=880, rate=0.16, seed=0):
    """Distant air-raid style wail: slow up/down glide, heavily filtered and reverberated."""
    t = np.arange(secs(dur)) / SR
    f = f_lo + (f_hi - f_lo) * (0.5 - 0.5 * np.cos(2 * np.pi * rate * t))
    y = osc(f, kind="tri") + 0.3 * osc(f * 2, kind="tri")
    y = lp(y, 1600) * env_points(dur, [(0, 0), (dur * 0.2, 1), (dur * 0.8, 1), (dur, 0)])
    return y


def thunder(dur=6.0, seed=0):
    rr = r(seed)
    y = brown(dur, rr)
    e = env_points(dur, [(0, 0), (0.15, 1), (0.6, 0.55), (1.2, 0.8), (dur, 0)], curve=1.6)
    crackle = lp(hp(white(dur, rr), 200), 1200) * env_exp(dur, 0.25, 0.01) * 0.3
    return lp(y * e + crackle, 450)


def rain_bed(dur, start=200.0, lp_hz=11000):
    x = O("rain2/amb_rain2.flac", start, dur, mono=False)
    return lp(x, lp_hz)


@amb("amb_city_rain")
def amb_city_rain():
    """Map: steady city rain (Kresiek, CC0) as the bed + low urban drone (filtered brown noise with slow movement), wind gusts, a distant two-tone siren and a far thunder roll, all placed away from the loop seam; 32 s seamless loop."""
    use("amb_city_rain", "rain2", "synth")
    L, X = 32.0, 3.0
    d = L + X
    rr = r(201)
    rain = rain_bed(d, 300.0)
    drone = lp(brown(d, rr), 140) * (0.75 + 0.25 * np.sin(2 * np.pi * np.arange(secs(d)) / SR / 11.0))[:secs(d)]
    wind = svf(pink(d, rr), 380 + 260 * np.sin(2 * np.pi * np.arange(secs(d)) / SR / 7.0), 1.4, "bp")
    wind = wind * (0.5 + 0.5 * np.sin(2 * np.pi * np.arange(secs(d)) / SR / 9.0 + 1.0)) ** 2
    sir = hall(siren(11.0, seed=202), 3.5, 0.6, 1800)
    sir = lp(sir, 1300)
    th = hall(thunder(6.5, 203), 3.0, 0.4, 900)
    y = mix(d, (rain, 0, 0), (drone, 0, -12, -0.2), (drone[::-1], 0, -14, 0.3), (wind, 0, -19, 0.4),
            (sir, 6.0, -30, -0.55), (th, 19.0, -11, 0.25), stereo=True)
    y = loopify(y, X)
    return y


@amb("amb_combat")
def amb_combat():
    """Combat bed: dark detuned low drone with breathing filter, slow 64 BPM sub pulse, a high beating dissonant shimmer, muffled rain and distant reverberant ghoul moans; 28 s seamless loop."""
    use("amb_combat", "rain2", "ghoul", "synth")
    L, X = 28.0, 3.0
    d = L + X
    t = np.arange(secs(d)) / SR
    dr = sum(osc(f * (1 + dt), d, "saw") for f in (41.2, 61.7, 82.4) for dt in (-0.003, 0.002))
    dr = svf(dr, 180 + 140 * (0.5 + 0.5 * np.sin(2 * np.pi * t / 7.0)), 1.1, "lp")
    dr = body(dr, 120, 0)
    pulse = np.zeros(secs(d))
    beat = sub_boom(52, 40, 0.4, 0.09, 211, click=False)
    period = L / 30  # 64.3 BPM, an exact divisor of the loop so the pulse never stumbles at the seam
    k = 0.0
    while k < d - 0.5:
        s = secs(k)
        pulse[s:s + len(beat)] += beat[: len(pulse) - s]
        k += period
    shimmer = (osc(1244.5, d) + osc(1318.5, d) * 0.8 + osc(1864.7, d) * 0.3) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 5.6)) ** 2
    shimmer = stereoize(lp(shimmer, 2500), 0.6)
    rain = lp(rain_bed(d, 520.0), 1800)
    g1 = hall(lp(pitch_resample(seg("ghoul", 4), 0.72), 1500), 3.5, 0.65, 1200)
    g2 = hall(lp(pitch_resample(seg("ghoul", 2), 0.65), 1300), 3.5, 0.65, 1100)
    y = mix(d, (dr, 0, -6, 0), (stereoize(pulse, 0.2), 0, -9), (shimmer, 0, -31), (rain, 0, -9),
            (g1, 7.0, -24, -0.6), (g2, 17.5, -26, 0.6), stereo=True)
    y = loopify(y, X)
    return y


@amb("amb_shelter")
def amb_shelter():
    """Node interior: rain on the roof (low-passed Kresiek rain) + gutter drips (ogrebane), a 50 Hz generator hum with wobble, faint radio-static murmurs and a timber creak (Kenney); 30 s seamless loop."""
    use("amb_shelter", "rain2", "gutter", "kenney_rpg", "synth")
    L, X = 30.0, 3.0
    d = L + X
    t = np.arange(secs(d)) / SR
    roof = lp(rain_bed(d, 610.0), 1400)
    gut = lp(O("rain4/rain-gutter-loop_0.mp3", 5.0, d, mono=False), 4000)
    wob = 1 + 0.003 * np.sin(2 * np.pi * t / 3.1)
    hum = (osc(50 * wob) + 0.5 * osc(100 * wob) + 0.3 * osc(150 * wob) + 0.12 * osc(250 * wob)) * (0.85 + 0.15 * np.sin(2 * np.pi * t / 6.7))
    hum = drive(hum * 0.8, 1.5)
    rr = r(221)
    stat = []
    for t0 in (8.0, 20.5):
        sd = 2.2
        n = bp(white(sd, rr), 400, 2800) * (0.5 + 0.5 * np.sin(2 * np.pi * 4.3 * np.arange(secs(sd)) / SR)) ** 2
        stat.append((radio(n * env_points(sd, [(0, 0), (0.3, 1), (1.8, 1), (sd, 0)]), 222), t0, -30, -0.4))
    creak = K("rpg", "creak2.ogg")
    y = mix(d, (roof, 0, 0), (gut, 0, -13), (hum, 0, -27, 0.1), *stat, (lp(creak, 3000), 13.5, -20, 0.5), stereo=True)
    y = loopify(y, X)
    return y


# ===========================================================================
# Build
# ===========================================================================

def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(WAV_OUT, exist_ok=True)
    report = {}
    for name, (kind, fn, target, kbps) in REG.items():
        if ONLY and name not in ONLY:
            continue
        x = fn()
        if kind == "sfx":
            x = to_mono(x) if x.ndim == 2 else x
            x = finish(name, x, target)
        else:
            x = finish_amb(x, target)
        save_wav(os.path.join(WAV_OUT, name + ".wav"), x)
        encode_mp3(x, os.path.join(OUT, name + ".mp3"), kbps)
        report[name] = {"kind": kind, "dur": len(x) / SR, "lufs": lufs(x), "tp": true_peak_db(x), "kbps": kbps,
                        "sources": sorted(USED.get(name, [])), "note": NOTES.get(name, "")}
        print(f"{name:18s} {len(x) / SR:5.2f}s  {report[name]['lufs']:6.1f} LUFS  TP {report[name]['tp']:5.1f}")
    path = os.path.join(ROOT, "out", "report.json")
    old = json.load(open(path)) if os.path.exists(path) else {}
    old.update(report)
    json.dump(old, open(path, "w"), indent=1)


if __name__ == "__main__":
    main()
