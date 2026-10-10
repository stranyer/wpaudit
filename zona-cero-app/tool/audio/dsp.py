"""Small DSP toolkit for Zona Cero sound design (numpy/scipy + ffmpeg)."""
from __future__ import annotations

import os
import subprocess
import tempfile
from fractions import Fraction

import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from scipy import signal

SR = 44100
RNG = np.random.default_rng(7)


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


# ---------------------------------------------------------------------------
# IO
# ---------------------------------------------------------------------------

def load(path: str, sr: int = SR, mono: bool = True, start: float | None = None, dur: float | None = None) -> np.ndarray:
    """Decode any audio file with ffmpeg to float32 at `sr`."""
    cmd = ["ffmpeg", "-v", "error"]
    if start is not None:
        cmd += ["-ss", str(start)]
    if dur is not None:
        cmd += ["-t", str(dur)]
    cmd += ["-i", path, "-f", "f32le", "-acodec", "pcm_f32le", "-ar", str(sr), "-ac", "1" if mono else "2", "-"]
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    if not mono:
        x = x.reshape(-1, 2)
    return x


def save_wav(path: str, x: np.ndarray, sr: int = SR) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    sf.write(path, np.clip(x, -1, 1).astype(np.float32), sr, subtype="FLOAT")


def encode_mp3(x: np.ndarray, path: str, kbps: int, sr: int = SR) -> None:
    """Encode with LAME (CBR, gapless LAME header) through ffmpeg."""
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as t:
        tmp = t.name
    try:
        sf.write(tmp, np.clip(x, -1, 1).astype(np.float32), sr, subtype="FLOAT")
        ch = 1 if x.ndim == 1 else 2
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", tmp, "-ac", str(ch), "-ar", str(sr), "-c:a", "libmp3lame",
             "-b:a", f"{kbps}k", "-compression_level", "0", "-map_metadata", "-1", "-id3v2_version", "0",
             "-write_xing", "1", path],
            check=True,
        )
    finally:
        os.unlink(tmp)


def rubberband(x: np.ndarray, pitch: float = 1.0, tempo: float = 1.0, formant: bool = False, sr: int = SR) -> np.ndarray:
    """High quality pitch shift / time stretch via ffmpeg's rubberband filter."""
    with tempfile.TemporaryDirectory() as d:
        a, b = os.path.join(d, "a.wav"), os.path.join(d, "b.wav")
        sf.write(a, x.astype(np.float32), sr, subtype="FLOAT")
        f = f"rubberband=pitch={pitch}:tempo={tempo}:transients=crisp:detector=compound:phase=laminar:window=standard:smoothing=on"
        if formant:
            f += ":formant=preserved"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a, "-af", f, "-c:a", "pcm_f32le", b], check=True)
        y, _ = sf.read(b, dtype="float64")
    return y


# ---------------------------------------------------------------------------
# Measurement
# ---------------------------------------------------------------------------

def to_mono(x: np.ndarray) -> np.ndarray:
    return x.mean(axis=1) if x.ndim == 2 else x


def lufs(x: np.ndarray, sr: int = SR) -> float:
    """Integrated loudness (ITU-R BS.1770-4). Short clips are padded to 0.4 s."""
    y = x if x.ndim == 2 else x[:, None]
    n = max(len(y), int(0.41 * sr))
    if len(y) < n:
        y = np.concatenate([y, np.zeros((n - len(y), y.shape[1]))])
    m = pyln.Meter(sr)
    return float(m.integrated_loudness(y if y.shape[1] > 1 else y[:, 0]))


def short_term_max(x: np.ndarray, sr: int = SR, win: float = 0.4) -> float:
    """Max momentary loudness (400 ms window, K-weighted) — robust for short SFX."""
    y = x if x.ndim == 2 else x[:, None]
    m = pyln.Meter(sr, block_size=win)
    w = int(win * sr)
    hop = int(0.05 * sr)
    best = -120.0
    if len(y) < w:
        y = np.concatenate([y, np.zeros((w - len(y), y.shape[1]))])
    for i in range(0, len(y) - w + 1, hop):
        seg = y[i:i + w]
        try:
            v = m.integrated_loudness(seg if seg.shape[1] > 1 else seg[:, 0])
        except Exception:
            continue
        if np.isfinite(v):
            best = max(best, v)
    return best


def true_peak_db(x: np.ndarray) -> float:
    y = signal.resample_poly(x, 4, 1, axis=0)
    p = np.max(np.abs(y))
    return 20 * np.log10(max(p, 1e-12))


def peak_db(x: np.ndarray) -> float:
    return 20 * np.log10(max(np.max(np.abs(x)), 1e-12))


def db(g: float) -> float:
    return 10 ** (g / 20)


# ---------------------------------------------------------------------------
# Generators
# ---------------------------------------------------------------------------

def secs(n: float, sr: int = SR) -> int:
    return int(round(n * sr))


def t_axis(dur: float, sr: int = SR) -> np.ndarray:
    return np.arange(secs(dur, sr)) / sr


def white(dur: float, r: np.random.Generator | None = None) -> np.ndarray:
    r = r or RNG
    return r.standard_normal(secs(dur)) * 0.3


def pink(dur: float, r: np.random.Generator | None = None) -> np.ndarray:
    r = r or RNG
    n = secs(dur)
    X = np.fft.rfft(r.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    X /= np.sqrt(f)
    y = np.fft.irfft(X, n)
    return y / (np.std(y) + 1e-12) * 0.3


def brown(dur: float, r: np.random.Generator | None = None) -> np.ndarray:
    r = r or RNG
    n = secs(dur)
    X = np.fft.rfft(r.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    X /= f
    y = np.fft.irfft(X, n)
    y = hp(y, 20)
    return y / (np.std(y) + 1e-12) * 0.3


def osc(freq, dur: float | None = None, kind: str = "sine", phase0: float = 0.0) -> np.ndarray:
    """Oscillator with (optionally time-varying) frequency array."""
    if np.isscalar(freq):
        freq = np.full(secs(dur), float(freq))
    ph = 2 * np.pi * np.cumsum(freq) / SR + phase0
    if kind == "sine":
        return np.sin(ph)
    if kind == "saw":
        # band-limited-ish saw via additive (up to 40 harmonics under nyquist)
        y = np.zeros_like(ph)
        fmax = np.max(freq)
        for k in range(1, 60):
            if k * fmax > SR / 2 * 0.9:
                break
            y += np.sin(k * ph) / k
        return y * (2 / np.pi)
    if kind == "square":
        y = np.zeros_like(ph)
        fmax = np.max(freq)
        for k in range(1, 60, 2):
            if k * fmax > SR / 2 * 0.9:
                break
            y += np.sin(k * ph) / k
        return y * (4 / np.pi)
    if kind == "tri":
        y = np.zeros_like(ph)
        fmax = np.max(freq)
        for i, k in enumerate(range(1, 40, 2)):
            if k * fmax > SR / 2 * 0.9:
                break
            y += ((-1) ** i) * np.sin(k * ph) / (k * k)
        return y * (8 / np.pi ** 2)
    raise ValueError(kind)


def glide(f0: float, f1: float, dur: float, curve: str = "exp") -> np.ndarray:
    n = secs(dur)
    u = np.linspace(0, 1, n)
    if curve == "exp":
        return f0 * (f1 / f0) ** u
    return f0 + (f1 - f0) * u


# ---------------------------------------------------------------------------
# Envelopes
# ---------------------------------------------------------------------------

def env_exp(dur: float, tau: float, attack: float = 0.002) -> np.ndarray:
    """Exponential decay that always lands on zero (raised-cosine end fade → no truncation clicks)."""
    t = t_axis(dur)
    a = np.clip(t / max(attack, 1e-6), 0, 1)
    e = a * np.exp(-np.maximum(t - attack, 0) / tau)
    nf = max(1, min(len(e) // 4, secs(0.03)))
    e[-nf:] *= np.cos(np.linspace(0, np.pi / 2, nf)) ** 2
    return e


def env_adsr(dur: float, a: float, d: float, s: float, r: float) -> np.ndarray:
    n = secs(dur)
    t = np.arange(n) / SR
    e = np.ones(n) * s
    e[t < a] = t[t < a] / max(a, 1e-6)
    m = (t >= a) & (t < a + d)
    e[m] = 1 - (1 - s) * (t[m] - a) / max(d, 1e-6)
    rel = t > dur - r
    e[rel] *= np.clip((dur - t[rel]) / max(r, 1e-6), 0, 1)
    return e


def env_points(dur: float, pts: list[tuple[float, float]], curve: float = 1.0) -> np.ndarray:
    """Piecewise envelope from (time, value) points."""
    t = t_axis(dur)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    e = np.interp(t, xs, ys)
    return e ** curve if curve != 1.0 else e


def fade(x: np.ndarray, fin: float = 0.003, fout: float = 0.02) -> np.ndarray:
    y = x.copy()
    ni, no = secs(fin), secs(fout)
    if ni > 0:
        w = np.sin(np.linspace(0, np.pi / 2, ni)) ** 2
        y[:ni] = (y[:ni].T * w).T
    if no > 0:
        w = np.cos(np.linspace(0, np.pi / 2, no)) ** 2
        y[-no:] = (y[-no:].T * w).T
    return y


# ---------------------------------------------------------------------------
# Filters
# ---------------------------------------------------------------------------

def _sos(kind, f, order=4):
    return signal.butter(order, f, btype=kind, fs=SR, output="sos")


def lp(x, f, order=4):
    return signal.sosfilt(_sos("lowpass", min(f, SR / 2 * 0.98), order), x, axis=0)


def hp(x, f, order=4):
    return signal.sosfilt(_sos("highpass", f, order), x, axis=0)


def bp(x, f1, f2, order=2):
    return signal.sosfilt(_sos("bandpass", [f1, min(f2, SR / 2 * 0.98)], order), x, axis=0)


def biquad_peak(f0, gain_db, q):
    A = 10 ** (gain_db / 40)
    w = 2 * np.pi * f0 / SR
    al = np.sin(w) / (2 * q)
    b = [1 + al * A, -2 * np.cos(w), 1 - al * A]
    a = [1 + al / A, -2 * np.cos(w), 1 - al / A]
    return np.array(b) / a[0], np.array(a) / a[0]


def peq(x, f0, gain_db, q=1.0):
    b, a = biquad_peak(f0, gain_db, q)
    return signal.lfilter(b, a, x, axis=0)


def shelf(x, f0, gain_db, high=True):
    A = 10 ** (gain_db / 40)
    w = 2 * np.pi * f0 / SR
    al = np.sin(w) / 2 * np.sqrt(2)
    c = np.cos(w)
    if high:
        b = [A * ((A + 1) + (A - 1) * c + 2 * np.sqrt(A) * al), -2 * A * ((A - 1) + (A + 1) * c),
             A * ((A + 1) + (A - 1) * c - 2 * np.sqrt(A) * al)]
        a = [(A + 1) - (A - 1) * c + 2 * np.sqrt(A) * al, 2 * ((A - 1) - (A + 1) * c),
             (A + 1) - (A - 1) * c - 2 * np.sqrt(A) * al]
    else:
        b = [A * ((A + 1) - (A - 1) * c + 2 * np.sqrt(A) * al), 2 * A * ((A - 1) - (A + 1) * c),
             A * ((A + 1) - (A - 1) * c - 2 * np.sqrt(A) * al)]
        a = [(A + 1) + (A - 1) * c + 2 * np.sqrt(A) * al, -2 * ((A - 1) + (A + 1) * c),
             (A + 1) + (A - 1) * c - 2 * np.sqrt(A) * al]
    b, a = np.array(b) / a[0], np.array(a) / a[0]
    return signal.lfilter(b, a, x, axis=0)


def resonator(x, f0, q=30.0, gain_db=0.0):
    """Narrow bandpass ringing filter (constant peak gain)."""
    w = 2 * np.pi * f0 / SR
    al = np.sin(w) / (2 * q)
    b = np.array([al, 0, -al])
    a = np.array([1 + al, -2 * np.cos(w), 1 - al])
    return signal.lfilter(b / a[0], a / a[0], x, axis=0) * db(gain_db)


def sweep_filter(x, f_start, f_end, kind="bp", q=4.0, block=256):
    """Time-varying 2-pole filter (state-variable), freq glides exponentially."""
    n = len(x)
    fs = f_start * (f_end / f_start) ** (np.arange(n) / max(n - 1, 1))
    return svf(x, fs, q, kind)


def svf(x, freqs, q=2.0, kind="bp"):
    """Chamberlin/Simper SVF with per-sample cutoff (numpy loop, fine for SFX lengths)."""
    y = np.zeros_like(x)
    ic1 = ic2 = 0.0
    k = 1.0 / q
    for i in range(len(x)):
        g = np.tan(np.pi * min(freqs[i], SR * 0.45) / SR)
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
        v3 = x[i] - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        if kind == "lp":
            y[i] = v2
        elif kind == "hp":
            y[i] = x[i] - k * v1 - v2
        else:
            y[i] = v1
    return y


def formants(x, fmts, q=8.0):
    """Parallel formant bank: fmts = [(freq, gain_db), ...]."""
    y = np.zeros_like(x)
    for f, g in fmts:
        y += resonator(x, f, q, g)
    return y


# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------

def drive(x, amount=2.0, asym=0.0):
    y = np.tanh(amount * (x + asym)) - np.tanh(amount * asym)
    return y / np.tanh(amount)


def fold(x, amount=2.0):
    return np.sin(x * amount * np.pi / 2)


def crush(x, bits=8, down=1):
    q = 2 ** (bits - 1)
    y = np.round(x * q) / q
    if down > 1:
        y = np.repeat(y[::down], down)[: len(x)]
    return y


def ringmod(x, f):
    return x * np.sin(2 * np.pi * f * np.arange(len(x)) / SR)


def pitch_resample(x, factor):
    """Varispeed: factor>1 raises pitch and shortens."""
    fr = Fraction(1 / factor).limit_denominator(200)
    return signal.resample_poly(x, fr.numerator, fr.denominator, axis=0)


def make_ir(decay: float, sr: int = SR, predelay: float = 0.012, damp: float = 4500, size: float = 1.0, seed: int = 3,
            stereo: bool = False, early: int = 12) -> np.ndarray:
    """Synthetic room/hall IR: early taps + exponentially decaying filtered noise with HF damping."""
    r = rng(seed)
    n = secs(decay * 1.5 + predelay)
    chans = []
    for c in range(2 if stereo else 1):
        t = np.arange(n) / sr
        tail = r.standard_normal(n) * np.exp(-6.9 * t / decay)
        # Frequency dependent decay: split low / high bands with different decay.
        hi = hp(tail, damp) * np.exp(-6.9 * t / (decay * 0.35))
        lo = lp(tail, damp)
        tail = lo + hi
        ir = np.zeros(n)
        pd = secs(predelay)
        ir[pd:] += tail[: n - pd] * 0.6
        for _ in range(early):
            k = pd + int(r.uniform(0.001, 0.05 * size) * sr)
            if k < n:
                ir[k] += r.uniform(-0.6, 0.6)
        ir = fade(ir, 0, 0.05)
        chans.append(ir / np.sqrt(np.sum(ir ** 2)))
    return np.stack(chans, axis=1) if stereo else chans[0]


def reverb(x, decay=1.2, mix=0.25, predelay=0.012, damp=4500, seed=3, tail_pad=True, lowcut=120):
    ir = make_ir(decay, predelay=predelay, damp=damp, seed=seed)
    xx = np.concatenate([x, np.zeros(len(ir))]) if tail_pad else x
    wet = signal.fftconvolve(xx, ir)[: len(xx)]
    wet = hp(wet, lowcut, 2)
    dry = xx
    return dry * (1 - mix) + wet * mix * 1.6


def reverb_stereo(x, decay=2.0, mix=0.3, predelay=0.02, damp=4000, seed=5):
    """Mono or stereo in → stereo out with decorrelated tails."""
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    irl = make_ir(decay, predelay=predelay, damp=damp, seed=seed)
    irr = make_ir(decay, predelay=predelay * 1.13, damp=damp, seed=seed + 101)
    pad = np.zeros((len(irl), 2))
    xx = np.concatenate([x, pad])
    wl = signal.fftconvolve(xx[:, 0], irl)[: len(xx)]
    wr = signal.fftconvolve(xx[:, 1], irr)[: len(xx)]
    wet = np.stack([wl, wr], axis=1)
    return xx * (1 - mix) + wet * mix * 1.6


def echo(x, delay=0.25, fb=0.35, n=4, damp=3000):
    y = np.concatenate([x, np.zeros(secs(delay * n) + 1)])
    tap = x.copy()
    for i in range(1, n + 1):
        tap = lp(tap, damp, 2) * fb
        k = secs(delay * i)
        y[k:k + len(tap)] += tap
    return y


def chorus(x, depth=0.003, rate=0.6, mix=0.5, seed=1):
    n = len(x)
    t = np.arange(n) / SR
    r = rng(seed)
    out = x.copy() * (1 - mix)
    for v in range(2):
        d = (0.012 + depth * (1 + np.sin(2 * np.pi * (rate * (1 + 0.3 * v)) * t + r.uniform(0, 6)))) * SR
        idx = np.arange(n) - d
        out += np.interp(idx, np.arange(n), x, left=0, right=0) * mix / 2
    return out


def limiter(x, ceiling_db=-1.0, release=0.06, lookahead=0.003):
    """Look-ahead peak limiter (on 2x oversampled peaks estimation)."""
    ceil = db(ceiling_db)
    m = to_mono(np.abs(x)) if x.ndim == 1 else np.max(np.abs(x), axis=1)
    # estimate inter-sample peaks
    up = np.abs(signal.resample_poly(x if x.ndim == 1 else x, 4, 1, axis=0))
    up = up if up.ndim == 1 else np.max(up, axis=1)
    m = np.maximum(m, up.reshape(-1, 4)[: len(m)].max(axis=1) if len(up) >= 4 * len(m) else m)
    need = np.minimum(1.0, ceil / np.maximum(m, 1e-9))
    la = max(1, secs(lookahead))
    from scipy.ndimage import minimum_filter1d
    g = minimum_filter1d(need, size=2 * la + 1, origin=0)
    g = np.concatenate([g[la:], np.full(la, g[-1])])  # shift: look ahead
    # release smoothing (attack instant)
    coef = np.exp(-1 / (release * SR))
    out = np.empty_like(g)
    s = 1.0
    for i in range(len(g)):
        s = g[i] if g[i] < s else coef * s + (1 - coef) * g[i]
        out[i] = s
    out = np.minimum(out, g)
    y = (x.T * out).T
    return np.clip(y, -ceil, ceil)


def compress(x, thresh_db=-18, ratio=3.0, attack=0.005, release=0.08, makeup_db=0.0):
    env = to_mono(np.abs(x)) if x.ndim == 2 else np.abs(x)
    a = np.exp(-1 / (attack * SR))
    r = np.exp(-1 / (release * SR))
    lvl = np.empty_like(env)
    s = 0.0
    for i, v in enumerate(env):
        s = a * s + (1 - a) * v if v > s else r * s + (1 - r) * v
        lvl[i] = s
    ldb = 20 * np.log10(np.maximum(lvl, 1e-9))
    over = np.maximum(ldb - thresh_db, 0)
    gdb = -over * (1 - 1 / ratio) + makeup_db
    g = 10 ** (gdb / 20)
    return (x.T * g).T


def trim(x, thresh_db=-55, pre=0.002, post=0.03):
    m = to_mono(np.abs(x)) if x.ndim == 2 else np.abs(x)
    sm = signal.lfilter([1 / 64] * 64, [1], m)
    idx = np.where(sm > db(thresh_db))[0]
    if len(idx) == 0:
        return x
    a = max(0, idx[0] - 64 - secs(pre))
    b = min(len(x), idx[-1] + secs(post))
    return x[a:b]


def gate_tail(x, thresh_db=-60, hold=0.02):
    """Cut the tail once it stays below threshold; then fade."""
    y = trim(x, thresh_db, 0.0, hold)
    return fade(y, 0.0005, min(0.08, len(y) / SR * 0.2))


def norm_peak(x, peak_db_target=-1.0):
    p = np.max(np.abs(x))
    return x * (db(peak_db_target) / max(p, 1e-12))


def mix(length: float, *layers, stereo=False):
    """layers: (signal, offset_s, gain_db[, pan]) → summed buffer."""
    n = secs(length)
    out = np.zeros((n, 2)) if stereo else np.zeros(n)
    for L in layers:
        sig, off, g = L[0], L[1], L[2]
        pan = L[3] if len(L) > 3 else 0.0
        k = secs(off)
        if k >= n:
            continue
        s = sig[: n - k] * db(g)
        if stereo:
            if s.ndim == 1:
                lg = np.cos((pan + 1) * np.pi / 4)
                rg = np.sin((pan + 1) * np.pi / 4)
                s = np.stack([s * lg, s * rg], axis=1) * np.sqrt(2)
            out[k:k + len(s)] += s
        else:
            out[k:k + len(s)] += s if s.ndim == 1 else s.mean(axis=1)
    return out


def pad_to(x, dur):
    n = secs(dur)
    if len(x) >= n:
        return x[:n]
    z = np.zeros((n - len(x),) + x.shape[1:])
    return np.concatenate([x, z])


def loopify(x: np.ndarray, xfade: float) -> np.ndarray:
    """Make a seamless loop: the last `xfade` seconds are equal-power crossfaded into the head.

    Returns a buffer of len(x) - xfade samples whose end flows into its start.
    """
    n = secs(xfade)
    head = x[:n]
    tail = x[-n:]
    body = x[n:-n] if len(x) > 2 * n else x[n:]
    u = np.linspace(0, 1, n)
    fi = np.sin(u * np.pi / 2)
    fo = np.cos(u * np.pi / 2)
    if x.ndim == 2:
        fi, fo = fi[:, None], fo[:, None]
    joined = tail * fo + head * fi
    return np.concatenate([joined, body]) if len(x) > 2 * n else joined


def stereoize(x, width=0.4, delay=0.011, seed=0):
    """Mono → pseudo-stereo via complementary comb + haas (mono-compatible enough)."""
    d = secs(delay)
    dl = np.concatenate([np.zeros(d), x])[: len(x)]
    side = lp(hp(dl, 200), 7000) * width
    return np.stack([x + side, x - side], axis=1) / (1 + width * 0.5)
