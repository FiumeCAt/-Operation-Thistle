"""Procedural studio-grade tactical darksynth / industrial ambient BGM library generator.

Generates 8 compact Ogg Vorbis (.ogg, ~1.1-1.6 MB each, 1:45-2:00 duration) tracks
harmonically locked to adjacent minor keys (Am / Dm / Em) with smooth pad intros/outros
so crossfading between Menu, Explore, and Combat feels completely seamless.

Usage:
    python tools/gen_bgm_library.py
"""
from __future__ import annotations

import json
import math
import subprocess
import tempfile
import wave
from pathlib import Path

import imageio_ffmpeg
import numpy as np

SR = 44100
BGM_DIR = Path(r"D:\AI Game\HellWalker\HellWalker_DollProtocol\assets\audio\bgm")
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()


def midi_to_hz(note: float) -> float:
    return 440.0 * (2.0 ** ((note - 69.0) / 12.0))


def one_pole_lp(x: np.ndarray, cutoff_hz: float) -> np.ndarray:
    """Fast vectorized resonant-free 1-pole lowpass via FFT for crisp warm analog tone."""
    n = x.shape[0]
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    h = 1.0 / np.sqrt(1.0 + (freqs / max(cutoff_hz, 20.0)) ** 4)
    return np.fft.irfft(np.fft.rfft(x) * h, n=n).astype(np.float32)


def bandpass_fft(x: np.ndarray, lo_hz: float, hi_hz: float) -> np.ndarray:
    n = x.shape[0]
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    hp = (freqs / max(lo_hz, 10.0)) ** 2 / np.sqrt(1.0 + (freqs / max(lo_hz, 10.0)) ** 4)
    lp = 1.0 / np.sqrt(1.0 + (freqs / max(hi_hz, lo_hz + 50.0)) ** 4)
    return np.fft.irfft(np.fft.rfft(x) * (hp * lp), n=n).astype(np.float32)


def add_stereo_delay(buf: np.ndarray, delay_sec_l: float, delay_sec_r: float,
                     fb: float = 0.36, wet: float = 0.30, lpf: float = 3400.0) -> np.ndarray:
    """Ping-pong multi-tap stereo echo with warm high-cut damping."""
    n = buf.shape[0]
    out = np.zeros_like(buf)
    dl = int(delay_sec_l * SR)
    dr = int(delay_sec_r * SR)
    gain = wet
    src_l = one_pole_lp(buf[:, 0], lpf)
    src_r = one_pole_lp(buf[:, 1], lpf)
    for tap in range(1, 6):
        off_l = dl * tap
        off_r = dr * tap
        if off_l < n:
            if tap % 2 == 1:
                out[off_l:, 0] += src_r[:n - off_l] * gain
            else:
                out[off_l:, 0] += src_l[:n - off_l] * gain
        if off_r < n:
            if tap % 2 == 1:
                out[off_r:, 1] += src_l[:n - off_r] * gain
            else:
                out[off_r:, 1] += src_r[:n - off_r] * gain
        gain *= fb
    return buf + out


def add_room_reverb(buf: np.ndarray, wet: float = 0.24, decay: float = 0.52) -> np.ndarray:
    """Lush, clean multi-tap diffused stereo reverb using prime-ish reflection delays."""
    n = buf.shape[0]
    dry_l = one_pole_lp(buf[:, 0], 4200.0)
    dry_r = one_pole_lp(buf[:, 1], 4200.0)
    rev = np.zeros_like(buf)
    taps_l = [0.029, 0.047, 0.071, 0.113, 0.173, 0.257, 0.379, 0.541]
    taps_r = [0.031, 0.053, 0.079, 0.127, 0.191, 0.277, 0.401, 0.569]
    for i, (tl, tr) in enumerate(zip(taps_l, taps_r)):
        g = wet * (decay ** (i * 0.55)) * (0.42 if i > 0 else 0.55)
        ol = int(tl * SR)
        orr = int(tr * SR)
        if ol < n:
            rev[ol:, 0] += (dry_l[:n - ol] * 0.72 + dry_r[:n - ol] * 0.28) * g
        if orr < n:
            rev[orr:, 1] += (dry_r[:n - orr] * 0.72 + dry_l[:n - orr] * 0.28) * g
    return buf + rev


def synth_pad_chord(notes: list[int], dur_sec: float, cutoff: float = 1300.0,
                    detune: float = 0.0055, vol: float = 0.22, attack: float = 0.35,
                    release: float = 0.45) -> np.ndarray:
    """Warm stereo detuned analog saw/triangle pad."""
    n = int(dur_sec * SR)
    t = np.arange(n, dtype=np.float32) / SR
    left = np.zeros(n, dtype=np.float32)
    right = np.zeros(n, dtype=np.float32)
    for idx, m in enumerate(notes):
        f = midi_to_hz(m)
        # 3 detuned voices per chord tone
        for dv, pan in ((-detune, 0.28), (0.0, 0.5), (detune, 0.72)):
            ph = (t * f * (1.0 + dv) + (idx * 0.17)) % 1.0
            saw = 2.0 * ph - 1.0
            tri = 2.0 * np.abs(2.0 * ph - 1.0) - 1.0
            sig = 0.55 * saw + 0.45 * tri
            left += sig * (1.0 - pan)
            right += sig * pan
    norm = max(len(notes) * 1.9, 1.0)
    left = one_pole_lp(left / norm, cutoff)
    right = one_pole_lp(right / norm, cutoff)
    # Slow breathing LFO
    lfo = 0.88 + 0.12 * np.sin(2.0 * np.pi * 0.22 * t)
    env = np.ones(n, dtype=np.float32)
    a_n = min(int(attack * SR), n // 2)
    r_n = min(int(release * SR), n // 2)
    if a_n > 0:
        env[:a_n] = np.linspace(0.0, 1.0, a_n, dtype=np.float32) ** 1.5
    if r_n > 0:
        env[-r_n:] = np.linspace(1.0, 0.0, r_n, dtype=np.float32) ** 1.5
    env *= lfo * vol
    return np.stack([left * env, right * env], axis=1)


def synth_pluck(note: int, dur_sec: float, bright: float = 2.4, vol: float = 0.22,
                pan: float = 0.5) -> np.ndarray:
    """Warm FM Rhodes / glass tactical synth pluck."""
    n = int(dur_sec * SR)
    t = np.arange(n, dtype=np.float32) / SR
    f = midi_to_hz(note)
    mod_env = np.exp(-t * 9.0) * bright
    amp_env = (1.0 - np.exp(-t * 280.0)) * np.exp(-t * (3.2 / max(dur_sec, 0.25)))
    # Slight smooth tail fade to prevent click
    fade = min(int(0.015 * SR), n)
    amp_env[-fade:] *= np.linspace(1.0, 0.0, fade, dtype=np.float32)
    mod = np.sin(2.0 * np.pi * f * 2.0 * t) * mod_env
    car = np.sin(2.0 * np.pi * f * t + mod) + 0.24 * np.sin(2.0 * np.pi * f * 0.5 * t)
    sig = car * amp_env * vol
    return np.stack([sig * math.cos(pan * math.pi * 0.5),
                     sig * math.sin(pan * math.pi * 0.5)], axis=1)


def synth_bass_note(note: int, dur_sec: float, grit: float = 0.45, cutoff: float = 520.0,
                    vol: float = 0.32) -> np.ndarray:
    """Punchy analog sub + filtered saw bass."""
    n = int(dur_sec * SR)
    t = np.arange(n, dtype=np.float32) / SR
    f = midi_to_hz(note)
    sub = np.sin(2.0 * np.pi * f * t)
    ph1 = (t * f) % 1.0
    ph2 = (t * f * 1.004) % 1.0
    saw = ((2.0 * ph1 - 1.0) + (2.0 * ph2 - 1.0)) * 0.5
    saw_f = one_pole_lp(saw, cutoff)
    sig = (1.0 - grit) * sub + grit * saw_f
    sig = np.tanh(sig * (1.2 + grit * 1.1))
    env = (1.0 - np.exp(-t * 220.0)) * np.exp(-t * (1.8 / max(dur_sec, 0.15)))
    fade = min(int(0.012 * SR), n)
    env[-fade:] *= np.linspace(1.0, 0.0, fade, dtype=np.float32)
    mono = sig * env * vol
    return np.stack([mono, mono], axis=1)


def synth_lead_note(note: int, dur_sec: float, cutoff: float = 2400.0, vol: float = 0.18,
                    pan: float = 0.52) -> np.ndarray:
    """Crisp darksynth lead with gentle vibrato and smooth glide envelope."""
    n = int(dur_sec * SR)
    t = np.arange(n, dtype=np.float32) / SR
    f = midi_to_hz(note)
    vib = 1.0 + 0.004 * np.sin(2.0 * np.pi * 5.2 * t) * np.clip(t * 2.5, 0.0, 1.0)
    ph = np.cumsum((f * vib) / SR) % 1.0
    ph2 = np.cumsum((f * 1.005 * vib) / SR) % 1.0
    raw = (2.0 * ph - 1.0) * 0.55 + (2.0 * ph2 - 1.0) * 0.35 + np.sign(np.sin(2.0 * np.pi * ph)) * 0.15
    filt = one_pole_lp(raw, cutoff)
    a_n = min(int(0.018 * SR), n // 3)
    r_n = min(int(0.08 * SR), n // 2)
    env = np.ones(n, dtype=np.float32)
    if a_n > 0:
        env[:a_n] = np.linspace(0.0, 1.0, a_n, dtype=np.float32)
    if r_n > 0:
        env[-r_n:] = np.linspace(1.0, 0.0, r_n, dtype=np.float32) ** 1.4
    sig = filt * env * vol
    return np.stack([sig * math.cos(pan * math.pi * 0.5),
                     sig * math.sin(pan * math.pi * 0.5)], axis=1)


def synth_kick(vol: float = 0.55, punch: float = 1.0) -> np.ndarray:
    n = int(0.32 * SR)
    t = np.arange(n, dtype=np.float32) / SR
    freq = 44.0 + (115.0 * punch) * np.exp(-t * 34.0)
    ph = 2.0 * np.pi * np.cumsum(freq) / SR
    body = np.sin(ph) * np.exp(-t * 10.5)
    click = np.sin(2.0 * np.pi * 1200.0 * t) * np.exp(-t * 140.0) * 0.18 * punch
    sig = np.tanh((body + click) * 1.35) * vol
    return np.stack([sig, sig], axis=1)


def synth_snare(rng: np.random.Generator, vol: float = 0.32, tight: bool = True) -> np.ndarray:
    n = int((0.20 if tight else 0.28) * SR)
    t = np.arange(n, dtype=np.float32) / SR
    noise = rng.standard_normal(n).astype(np.float32)
    snap = bandpass_fft(noise, 1100.0, 7200.0) * np.exp(-t * (22.0 if tight else 14.0))
    tone = np.sin(2.0 * np.pi * (185.0 + 70.0 * np.exp(-t * 40.0)) * t) * np.exp(-t * 24.0) * 0.55
    sig = np.tanh((snap * 0.85 + tone) * 1.2) * vol
    return np.stack([sig, sig * 0.97], axis=1)


def synth_hat(rng: np.random.Generator, open_hat: bool = False, vol: float = 0.11) -> np.ndarray:
    dur = 0.16 if open_hat else 0.055
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float32) / SR
    noise = rng.standard_normal(n).astype(np.float32)
    hp = bandpass_fft(noise, 5500.0, 14500.0)
    env = np.exp(-t * (18.0 if open_hat else 78.0))
    sig = hp * env * vol
    return np.stack([sig * 0.92, sig * 1.05], axis=1)


def synth_sonar_ping(note: int, vol: float = 0.16, pan: float = 0.65) -> np.ndarray:
    n = int(1.4 * SR)
    t = np.arange(n, dtype=np.float32) / SR
    f = midi_to_hz(note)
    sig = (np.sin(2.0 * np.pi * f * t) + 0.18 * np.sin(2.0 * np.pi * f * 2.0 * t)) * np.exp(-t * 3.1)
    sig *= (1.0 - np.exp(-t * 160.0)) * vol
    return np.stack([sig * math.cos(pan * math.pi * 0.5),
                     sig * math.sin(pan * math.pi * 0.5)], axis=1)


def mix_at(dst: np.ndarray, src: np.ndarray, start_sample: int) -> None:
    if start_sample >= dst.shape[0]:
        return
    if start_sample < 0:
        src = src[-start_sample:]
        start_sample = 0
    end = min(start_sample + src.shape[0], dst.shape[0])
    dst[start_sample:end] += src[:end - start_sample]


def apply_sidechain_duck(buf: np.ndarray, kick_samples: list[int], depth: float = 0.42,
                         release_sec: float = 0.18) -> np.ndarray:
    gain = np.ones(buf.shape[0], dtype=np.float32)
    rel_n = int(release_sec * SR)
    curve = 1.0 - depth * np.exp(-np.linspace(0.0, 4.5, rel_n, dtype=np.float32))
    for ks in kick_samples:
        end = min(ks + rel_n, buf.shape[0])
        if end > ks:
            gain[ks:end] = np.minimum(gain[ks:end], curve[:end - ks])
    return buf * gain[:, None]


def finalize_and_export_ogg(stereo: np.ndarray, out_ogg: Path, target_rms_db: float = -15.5) -> None:
    # Seamless gentle intro/outro fade (0.12s) + RMS loudness normalization + soft peak limiter
    n = stereo.shape[0]
    fade_in = int(0.12 * SR)
    fade_out = int(0.45 * SR)
    stereo[:fade_in] *= np.linspace(0.0, 1.0, fade_in, dtype=np.float32)[:, None]
    stereo[-fade_out:] *= np.linspace(1.0, 0.0, fade_out, dtype=np.float32)[:, None]

    rms = float(np.sqrt(np.mean(stereo ** 2)) + 1e-8)
    target_rms = 10.0 ** (target_rms_db / 20.0)
    stereo = stereo * (target_rms / rms)
    # Soft analog tape saturation / limiter so peak never clips
    stereo = np.tanh(stereo * 0.92) * 0.90

    pcm = np.clip(stereo * 32767.0, -32767.0, 32767.0).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        tmp_wav = Path(tf.name)
    try:
        with wave.open(str(tmp_wav), "wb") as wf:
            wf.setnchannels(2)
            wf.setsampwidth(2)
            wf.setframerate(SR)
            wf.writeframes(pcm.tobytes())
        cmd = [
            FFMPEG, "-y", "-loglevel", "error",
            "-i", str(tmp_wav),
            "-c:a", "libvorbis", "-q:a", "3",
            str(out_ogg),
        ]
        subprocess.run(cmd, check=True)
    finally:
        if tmp_wav.exists():
            tmp_wav.unlink()


# ==============================================================================
# Track Compositions (8 original tracks, 1:45 - 2:00 each, harmonically linked)
# ==============================================================================

def compose_menu_track(seed: int, bpm: float, bars: int, chords: list[list[int]],
                       arp_scale: list[int], rain_bed: bool = False) -> np.ndarray:
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar = beat * 4.0
    total_n = int(bars * bar * SR)
    pads = np.zeros((total_n, 2), dtype=np.float32)
    mel = np.zeros((total_n, 2), dtype=np.float32)
    bass = np.zeros((total_n, 2), dtype=np.float32)
    drums = np.zeros((total_n, 2), dtype=np.float32)
    kicks: list[int] = []

    kick_s = synth_kick(0.32, punch=0.55)
    rim_s = synth_snare(rng, 0.11, tight=True)
    hat_c = synth_hat(rng, False, 0.045)

    for b in range(bars):
        ch = chords[b % len(chords)]
        t0 = int(b * bar * SR)
        # Structure: intro(0-3), verse(4-15), bloom(16-27), calm(28-35), outro(36-39)
        section = "intro" if b < 4 else ("verse" if b < 16 else ("bloom" if b < 28 else ("calm" if b < 36 else "outro")))
        cut = 900.0 if section in ("intro", "outro") else (1550.0 if section == "bloom" else 1180.0)
        mix_at(pads, synth_pad_chord(ch, bar * 1.06, cutoff=cut, vol=0.23, attack=0.45, release=0.55), t0)

        if section != "intro":
            root = ch[0] - 12
            mix_at(bass, synth_bass_note(root, bar * 0.92, grit=0.22, cutoff=340.0, vol=0.26), t0)
            if section in ("bloom", "verse") and b % 2 == 1:
                mix_at(bass, synth_bass_note(root + 7, beat * 1.8, grit=0.20, cutoff=320.0, vol=0.18),
                       int((b * 4 + 2.5) * beat * SR))

        # Soft electric-piano / glass arpeggio motif
        step_cnt = 8 if section == "bloom" else 4
        step_dur = bar / step_cnt
        for s in range(step_cnt):
            if section == "outro" and s % 2 == 1:
                continue
            if section == "intro" and s not in (0, 2):
                continue
            if rng.random() < (0.88 if section == "bloom" else 0.72):
                deg = (b * 2 + s + (1 if section == "calm" else 0)) % len(arp_scale)
                note = arp_scale[deg] + (12 if (section == "bloom" and s in (3, 7)) else 0)
                pan = 0.30 + 0.40 * ((s % 4) / 3.0)
                mix_at(mel, synth_pluck(note, step_dur * 1.45, bright=1.6, vol=0.14, pan=pan),
                       int((b * bar + s * step_dur) * SR))

        # Minimal chill pulse in verse & bloom
        if section in ("verse", "bloom"):
            for bt in (0.0, 2.5):
                ks = int((b * 4 + bt) * beat * SR)
                mix_at(drums, kick_s, ks)
                kicks.append(ks)
            if section == "bloom":
                mix_at(drums, rim_s, int((b * 4 + 2.0) * beat * SR))
                for s8 in range(8):
                    if s8 % 2 == 1:
                        mix_at(drums, hat_c, int((b * 4 + s8 * 0.5) * beat * SR))

    if rain_bed:
        noise_l = bandpass_fft(rng.standard_normal(total_n).astype(np.float32), 650.0, 5200.0) * 0.022
        noise_r = bandpass_fft(rng.standard_normal(total_n).astype(np.float32), 700.0, 5000.0) * 0.022
        pads[:, 0] += noise_l
        pads[:, 1] += noise_r

    mel = add_stereo_delay(mel, beat * 0.75, beat * 0.5, fb=0.40, wet=0.35, lpf=2800.0)
    pads = apply_sidechain_duck(pads, kicks, depth=0.22, release_sec=0.24)
    mix = add_room_reverb(pads + mel + bass * 0.95, wet=0.28, decay=0.58) + drums
    return mix


def compose_explore_track(seed: int, bpm: float, bars: int, chords: list[list[int]],
                          scale: list[int], pulse_style: str = "sonar") -> np.ndarray:
    """Restrained dark tactical stealth/exploration track (leaves mids open for footsteps/SFX)."""
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar = beat * 4.0
    total_n = int(bars * bar * SR)
    pads = np.zeros((total_n, 2), dtype=np.float32)
    pulse = np.zeros((total_n, 2), dtype=np.float32)
    bass = np.zeros((total_n, 2), dtype=np.float32)
    fx = np.zeros((total_n, 2), dtype=np.float32)
    drums = np.zeros((total_n, 2), dtype=np.float32)
    kicks: list[int] = []

    kick_s = synth_kick(0.38, punch=0.65)
    rim_s = synth_snare(rng, 0.14, tight=True)
    hat_c = synth_hat(rng, False, 0.055)
    hat_o = synth_hat(rng, True, 0.05)

    for b in range(bars):
        ch = chords[(b // 2) % len(chords)]
        t0 = int(b * bar * SR)
        # Structure: 0-3 haze, 4-19 stealth_a, 20-35 tension_b, 36-43 wind_down
        sec = "haze" if b < 4 else ("stealth" if b < 20 else ("tension" if b < 36 else "outro"))
        cut = 720.0 if sec in ("haze", "outro") else (1050.0 if sec == "tension" else 860.0)
        if b % 2 == 0:
            mix_at(pads, synth_pad_chord(ch, bar * 2.08, cutoff=cut, detune=0.0065,
                                         vol=0.21, attack=0.65, release=0.75), t0)

        root = ch[0] - 12
        # Deep tactical bassline
        if pulse_style == "airduct" and sec in ("stealth", "tension"):
            for s8 in range(8):
                if s8 in (0, 2, 3, 5, 6):
                    n_off = 0 if s8 in (0, 2, 5) else (7 if s8 == 6 else 3)
                    mix_at(bass, synth_bass_note(root + n_off, beat * 0.44, grit=0.35, cutoff=420.0, vol=0.24),
                           int((b * 4 + s8 * 0.5) * beat * SR))
        else:
            mix_at(bass, synth_bass_note(root, bar * 0.94, grit=0.28, cutoff=360.0, vol=0.28), t0)
            if sec == "tension":
                mix_at(bass, synth_bass_note(root + 12, beat * 0.45, grit=0.35, cutoff=480.0, vol=0.14),
                       int((b * 4 + 3.5) * beat * SR))

        # Sparse muted rhythmic stealth pluck / ticking synth
        if sec in ("stealth", "tension"):
            sub_steps = 8 if (sec == "tension" or pulse_style == "airduct") else 4
            sd = bar / sub_steps
            for s in range(sub_steps):
                if (s % 2 == 0) or (sec == "tension" and rng.random() < 0.55):
                    note = scale[(b + s * 2) % len(scale)]
                    pan = 0.25 if s % 2 == 0 else 0.75
                    mix_at(pulse, synth_pluck(note, sd * 0.85, bright=1.35, vol=0.10, pan=pan),
                           int((b * bar + s * sd) * SR))

        # Atmospheric sonar ping / metallic industrial chime every 2-4 bars
        if b % 4 == 2 or (sec == "tension" and b % 2 == 1 and pulse_style == "sonar"):
            ping_note = scale[(b * 3) % len(scale)] + 12
            mix_at(fx, synth_sonar_ping(ping_note, vol=0.11, pan=0.22 if b % 4 == 2 else 0.78),
                   int((b * 4 + 1.5) * beat * SR))

        # Subtle tactical percussion groove
        if sec in ("stealth", "tension"):
            beat_hits = [0.0, 2.0] if sec == "stealth" else [0.0, 1.5, 2.0, 3.5]
            for bt in beat_hits:
                ks = int((b * 4 + bt) * beat * SR)
                mix_at(drums, kick_s, ks)
                kicks.append(ks)
            if sec == "tension":
                mix_at(drums, rim_s, int((b * 4 + 1.0) * beat * SR))
                mix_at(drums, rim_s, int((b * 4 + 3.0) * beat * SR))
            for s16 in range(16):
                if s16 % 4 == 2 or (sec == "tension" and s16 % 2 == 0):
                    mix_at(drums, hat_o if s16 == 14 and sec == "tension" else hat_c,
                           int((b * 4 + s16 * 0.25) * beat * SR))

    pulse = add_stereo_delay(pulse, beat * 0.75, beat * 0.5, fb=0.42, wet=0.36, lpf=2400.0)
    fx = add_stereo_delay(fx, beat * 1.0, beat * 0.75, fb=0.48, wet=0.45, lpf=3200.0)
    pads = apply_sidechain_duck(pads, kicks, depth=0.26, release_sec=0.20)
    mix = add_room_reverb(pads + pulse + fx + bass, wet=0.26, decay=0.55) + drums
    return mix


def compose_combat_track(seed: int, bpm: float, bars: int, chords: list[list[int]],
                         scale: list[int], motif_a: list[int], motif_b: list[int],
                         drum_style: str = "four_on_floor") -> np.ndarray:
    """High-energy darksynth / industrial tactical combat track with full arc & smooth loop tail."""
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar = beat * 4.0
    total_n = int(bars * bar * SR)
    pads = np.zeros((total_n, 2), dtype=np.float32)
    bass = np.zeros((total_n, 2), dtype=np.float32)
    arp = np.zeros((total_n, 2), dtype=np.float32)
    lead = np.zeros((total_n, 2), dtype=np.float32)
    drums = np.zeros((total_n, 2), dtype=np.float32)
    kicks: list[int] = []

    kick_s = synth_kick(0.54, punch=1.15)
    snare_s = synth_snare(rng, 0.30, tight=True)
    hat_c = synth_hat(rng, False, 0.085)
    hat_o = synth_hat(rng, True, 0.095)

    for b in range(bars):
        ch = chords[b % len(chords)]
        t0 = int(b * bar * SR)
        # 60-bar arc: 0-3 ramp, 4-19 assault_a, 20-35 assault_b, 36-43 tactical_break, 44-55 climax, 56-59 resolve
        if b < 4:
            sec = "ramp"
        elif b < 20:
            sec = "assault_a"
        elif b < 36:
            sec = "assault_b"
        elif b < 44:
            sec = "break"
        elif b < 56:
            sec = "climax"
        else:
            sec = "resolve"

        # Aggressive dark pad bed
        pad_cut = 1100.0 if sec in ("ramp", "break", "resolve") else 1750.0
        mix_at(pads, synth_pad_chord(ch, bar * 1.05, cutoff=pad_cut, detune=0.007,
                                     vol=0.18, attack=0.18, release=0.25), t0)

        # Rolling 16th octave cyber-bass
        root = ch[0] - 12
        if sec == "break":
            mix_at(bass, synth_bass_note(root, bar * 0.94, grit=0.55, cutoff=480.0, vol=0.30), t0)
        else:
            for s16 in range(16):
                if sec == "resolve" and s16 % 2 == 1:
                    continue
                if sec == "ramp" and s16 % 4 not in (0, 2):
                    continue
                note = root + (12 if (s16 % 4 == 2 and sec != "ramp") else 0)
                if s16 == 15 and b % 2 == 1:
                    note = root + 7
                v = 0.28 if s16 % 4 == 0 else (0.22 if s16 % 2 == 0 else 0.16)
                cut = 680.0 if sec == "climax" else 540.0
                mix_at(bass, synth_bass_note(note, beat * 0.24, grit=0.58, cutoff=cut, vol=v),
                       int((b * 4 + s16 * 0.25) * beat * SR))

        # Tight arpeggiated tension layer
        if sec in ("assault_a", "assault_b", "climax", "break"):
            for s8 in range(8):
                n_idx = (b + s8) % len(ch)
                anote = ch[n_idx] + (12 if s8 % 4 == 3 else 0)
                pan = 0.24 if s8 % 2 == 0 else 0.76
                mix_at(arp, synth_pluck(anote, beat * 0.42, bright=2.2,
                                        vol=0.12 if sec != "break" else 0.09, pan=pan),
                       int((b * 4 + s8 * 0.5) * beat * SR))

        # Driving tactical synth lead melody
        if sec in ("assault_a", "assault_b", "climax"):
            motif = motif_a if sec == "assault_a" else motif_b
            bar_in_phrase = b % 4
            step_len = beat * 0.5
            for s8 in range(8):
                m_val = motif[(bar_in_phrase * 8 + s8) % len(motif)]
                if m_val < 0:
                    continue
                lnote = scale[m_val % len(scale)] + (12 if sec == "climax" else 0)
                mix_at(lead, synth_lead_note(lnote, step_len * 0.92,
                                             cutoff=2700.0 if sec == "climax" else 2100.0,
                                             vol=0.16 if sec == "climax" else 0.13,
                                             pan=0.54 if s8 % 2 == 0 else 0.46),
                       int((b * 4 + s8 * 0.5) * beat * SR))

        # Drums
        if sec != "break":
            if drum_style == "four_on_floor":
                k_beats = [0.0, 1.0, 2.0, 3.0] if sec != "resolve" else [0.0, 2.0]
                sn_beats = [1.0, 3.0] if sec != "ramp" else [3.0]
            else:
                k_beats = [0.0, 0.75, 2.0, 2.5, 3.5] if sec in ("assault_b", "climax") else [0.0, 1.5, 2.0, 3.5]
                sn_beats = [1.0, 3.0] if sec != "ramp" else [3.0]
            for bt in k_beats:
                ks = int((b * 4 + bt) * beat * SR)
                mix_at(drums, kick_s, ks)
                kicks.append(ks)
            for bt in sn_beats:
                mix_at(drums, snare_s, int((b * 4 + bt) * beat * SR))
            if sec in ("assault_a", "assault_b", "climax"):
                for s16 in range(16):
                    if s16 % 2 == 0 or (sec == "climax" and s16 % 4 == 3):
                        mix_at(drums, hat_o if s16 == 14 else hat_c,
                               int((b * 4 + s16 * 0.25) * beat * SR))
        else:
            # Breakdown heartbeat kick
            ks = int((b * 4) * beat * SR)
            mix_at(drums, kick_s * 0.75, ks)
            kicks.append(ks)

    arp = add_stereo_delay(arp, beat * 0.5, beat * 0.75, fb=0.34, wet=0.28, lpf=2900.0)
    lead = add_stereo_delay(lead, beat * 0.75, beat * 0.5, fb=0.35, wet=0.30, lpf=3400.0)
    pads = apply_sidechain_duck(pads, kicks, depth=0.44, release_sec=0.16)
    bass = apply_sidechain_duck(bass, kicks, depth=0.32, release_sec=0.12)
    mix = add_room_reverb(pads + arp + lead, wet=0.20, decay=0.45) + bass + drums
    return mix


def main() -> None:
    BGM_DIR.mkdir(parents=True, exist_ok=True)

    # All tracks live in Am / Dm / Em (Circle-of-Fifths neighbors) for butter-smooth crossfades!
    am_scale = [57, 59, 60, 62, 64, 65, 67, 69]  # A3 minor
    dm_scale = [62, 64, 65, 67, 69, 70, 72, 74]  # D4 minor
    em_scale = [64, 66, 67, 69, 71, 72, 74, 76]  # E4 minor

    specs = [
        # ---- Menu (2 new) ----
        ("menu_silent_terminal", "静默终端", ["menu"], 1.0, lambda: compose_menu_track(
            seed=101, bpm=86.0, bars=40,
            chords=[[45, 52, 57, 60, 64], [41, 48, 53, 57, 60], [50, 57, 60, 65, 69], [40, 47, 52, 55, 62]],
            arp_scale=am_scale, rain_bed=False)),
        ("menu_rainy_outpost", "雨夜哨站", ["menu"], 1.0, lambda: compose_menu_track(
            seed=102, bpm=82.0, bars=40,
            chords=[[50, 57, 62, 65, 69], [46, 53, 58, 62, 65], [43, 50, 55, 58, 62], [45, 52, 57, 62, 64]],
            arp_scale=dm_scale, rain_bed=True)),
        # ---- Explore (3 new) ----
        ("explore_cold_corridor", "冷灰走廊", ["explore"], 1.0, lambda: compose_explore_track(
            seed=201, bpm=96.0, bars=44,
            chords=[[45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59], [40, 47, 52, 55]],
            scale=am_scale, pulse_style="sonar")),
        ("explore_blackout_deck", "断电层巡检", ["explore"], 1.0, lambda: compose_explore_track(
            seed=202, bpm=92.0, bars=44,
            chords=[[40, 47, 52, 55], [48, 55, 60, 64], [45, 52, 57, 60], [47, 54, 59, 62]],
            scale=em_scale, pulse_style="sonar")),
        ("explore_airduct_shadow", "暗道潜行", ["explore"], 1.0, lambda: compose_explore_track(
            seed=203, bpm=100.0, bars=44,
            chords=[[50, 57, 62, 65], [46, 53, 58, 62], [48, 55, 60, 64], [45, 52, 57, 60]],
            scale=dm_scale, pulse_style="airduct")),
        # ---- Combat (3 new) ----
        ("combat_breach_protocol", "交火协议", ["combat"], 1.0, lambda: compose_combat_track(
            seed=301, bpm=124.0, bars=60,
            chords=[[45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59], [40, 47, 52, 55]],
            scale=am_scale,
            motif_a=[0, -1, 2, 4, -1, 3, 2, -1,  0, -1, 4, 5, -1, 4, 2, 0,
                     0, -1, 2, 4, -1, 7, 6, -1,  4, -1, 3, 2, 1, -1, 0, -1],
            motif_b=[4, 4, 5, 7, -1, 5, 4, 2,   4, -1, 2, 0, -1, 2, 4, -1,
                     5, 5, 7, 7, -1, 6, 4, 3,   4, -1, 2, 1, 0, -1, -1, -1],
            drum_style="four_on_floor")),
        ("combat_iron_curtain", "铁幕压制", ["combat"], 1.0, lambda: compose_combat_track(
            seed=302, bpm=128.0, bars=60,
            chords=[[50, 57, 62, 65], [46, 53, 58, 62], [48, 55, 60, 64], [45, 52, 57, 61]],
            scale=dm_scale,
            motif_a=[0, 0, -1, 3, 4, -1, 2, 0,  -1, 0, 5, 4, 3, -1, 2, -1,
                     0, 0, -1, 4, 5, -1, 7, 5,  4, -1, 3, 2, 0, -1, -1, -1],
            motif_b=[7, -1, 5, 4, 5, -1, 3, 2,  4, -1, 2, 0, 2, 3, 4, -1,
                     5, -1, 7, 7, 5, 4, 3, 2,   4, 3, 2, 0, -1, 0, -1, -1],
            drum_style="breakbeat")),
        ("combat_zero_defense", "零号防线", ["combat"], 1.0, lambda: compose_combat_track(
            seed=303, bpm=130.0, bars=60,
            chords=[[40, 47, 52, 55], [48, 55, 60, 64], [50, 57, 62, 66], [47, 54, 59, 62]],
            scale=em_scale,
            motif_a=[0, -1, 4, 4, 5, -1, 4, 2,  0, -1, 2, 4, -1, 2, 1, -1,
                     0, -1, 4, 5, 7, -1, 5, 4,  2, -1, 1, 2, 4, -1, -1, -1],
            motif_b=[7, 7, -1, 6, 4, -1, 5, 4,  2, -1, 4, 5, 4, 2, 0, -1,
                     4, 4, 5, 7, -1, 7, 6, 4,   5, 4, 2, 1, 0, -1, -1, -1],
            drum_style="four_on_floor")),
    ]

    meta: dict[str, dict] = {
        "bgm_menu": {"title": "霓虹机库", "pools": ["menu"], "weight": 1.0},
        "bgm_explore": {"title": "暗区低潜", "pools": ["explore"], "weight": 1.0},
        "bgm_combat": {"title": "蓟花突击", "pools": ["combat"], "weight": 1.0},
    }

    for base, cn_title, pools, weight, builder in specs:
        out_path = BGM_DIR / f"{base}.ogg"
        stereo = builder()
        dur_sec = stereo.shape[0] / SR
        finalize_and_export_ogg(stereo, out_path)
        size_kb = out_path.stat().st_size / 1024.0
        meta[base] = {"title": cn_title, "pools": pools, "weight": weight}
        print(f"OK {out_path.name:28s} | {cn_title:8s} | {int(dur_sec // 60)}:{int(dur_sec % 60):02d} | {size_kb:6.1f} KB")

    tracks_json = BGM_DIR / "tracks.json"
    tracks_json.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote metadata: {tracks_json} ({len(meta)} tracks total)")


if __name__ == "__main__":
    main()
