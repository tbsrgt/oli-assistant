#!/usr/bin/env python3
"""Palette sonore d'Oli : 29 petits sons chaleureux, générés (aucun échantillon externe).

Usage : python3 tools/oli-sounds.py [dossier de sortie]
Par défaut : OliAssistant/Resources/sounds/<nom>.wav (44,1 kHz, 16 bits, mono).

Matières : kalimba (FM douce), clochette (partiels inharmoniques), bulles (balayages de
hauteur), souffles (bruit filtré), le tout dans une gamme majeure pentatonique avec une
petite réverbération pour la rondeur.
"""
import pathlib
import sys
import wave

import numpy as np

SR = 44_100
rng = np.random.default_rng(7)

# --- notes (gamme de do majeur pentatonique) ------------------------------------------
def note(name: str) -> float:
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    letter, octave = name[0], int(name[-1])
    semis = names[letter] + (1 if "#" in name else 0) + (octave - 4) * 12
    return 440.0 * 2 ** (semis / 12)

def t_axis(dur):
    return np.arange(int(dur * SR)) / SR

# --- matières --------------------------------------------------------------------------
def kalimba(f, dur=0.45, bright=1.0):
    t = t_axis(dur)
    index = 2.2 * bright * np.exp(-t * 18)                 # FM qui s'éteint vite : attaque « tine »
    mod = np.sin(2 * np.pi * f * 3.5 * t) * index
    body = np.sin(2 * np.pi * f * t + mod)
    body += 0.18 * np.sin(2 * np.pi * f * 5.95 * t) * np.exp(-t * 30)   # petit partiel métallique
    env = (1 - np.exp(-t * 900)) * np.exp(-t * (5.5 / dur))
    return body * env

def bell(f, dur=0.9):
    t = t_axis(dur)
    out = np.zeros_like(t)
    for ratio, amp, decay in [(1, 1.0, 3.2), (2.0, 0.42, 4.5), (2.76, 0.35, 6), (5.4, 0.12, 11), (8.93, 0.05, 18)]:
        out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t * decay / dur * 0.9)
    return out * (1 - np.exp(-t * 1500))

def bubble(f0, f1, dur=0.12, curve=2.0):
    t = t_axis(dur)
    x = t / dur
    f = f0 * (f1 / f0) ** (x ** (1 / curve))
    phase = 2 * np.pi * np.cumsum(f) / SR
    env = np.sin(np.pi * np.clip(x, 0, 1)) ** 1.5
    return np.sin(phase) * env

def glide(f0, f1, dur, shape=1.0, vibrato=0.0, vib_rate=6.0):
    t = t_axis(dur)
    x = t / dur
    f = f0 * (f1 / f0) ** (x ** shape)
    f = f * (1 + vibrato * np.sin(2 * np.pi * vib_rate * t))
    phase = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(phase) + 0.25 * np.sin(2 * phase) + 0.08 * np.sin(3 * phase)
    env = (1 - np.exp(-t * 200)) * np.clip(1.15 - x, 0, 1) ** 1.2
    return tone * env

def swoosh(dur, up=True, center=1800, amount=0.6):
    t = t_axis(dur)
    x = t / dur
    noise = rng.standard_normal(len(t))
    # filtre passe-bande glissant (deux pôles simples)
    out = np.zeros_like(noise)
    y1 = y2 = 0.0
    for i, n in enumerate(noise):
        fc = center * (0.45 + 1.1 * (x[i] if up else 1 - x[i]))
        a = np.exp(-2 * np.pi * fc / SR)
        y1 = (1 - a) * n + a * y1
        y2 = (1 - a) * y1 + a * y2
        out[i] = y1 - y2
    env = np.sin(np.pi * x) ** 2
    return out / (np.max(np.abs(out)) + 1e-9) * env * amount

def thump(f=110, dur=0.18):
    t = t_axis(dur)
    f_t = f * (1 + 1.5 * np.exp(-t * 40))
    phase = 2 * np.pi * np.cumsum(f_t) / SR
    return np.sin(phase) * np.exp(-t * 22)

def click(dur=0.025, tone=3200):
    t = t_axis(dur)
    return np.sin(2 * np.pi * tone * t) * np.exp(-t * 260)

# --- assemblage ------------------------------------------------------------------------
def mix(parts, total=None):
    """parts : [(signal, départ_s, gain)]"""
    end = max(start + len(sig) / SR for sig, start, _ in parts)
    out = np.zeros(int(((total or end) + 0.01) * SR))
    for sig, start, gain in parts:
        i = int(start * SR)
        n = min(len(sig), len(out) - i)
        out[i:i + n] += sig[:n] * gain
    return out

_ir = None
def reverb(sig, wet=0.16, size=0.55):
    global _ir
    if _ir is None:
        t = t_axis(size)
        _ir = rng.standard_normal(len(t)) * np.exp(-t * 7.5)
        _ir[: int(0.012 * SR)] = 0                        # petite pré-délai
        _ir /= np.sqrt(np.sum(_ir ** 2))
    tail = np.convolve(sig, _ir)[: len(sig) + len(_ir)]
    dry = np.concatenate([sig, np.zeros(len(tail) - len(sig))])
    return dry * (1 - wet * 0.5) + tail * wet

def finish(sig, level=0.85, wet=0.16):
    sig = reverb(sig, wet=wet)
    sig = np.tanh(sig / (np.max(np.abs(sig)) + 1e-9) * 1.15)   # chaleur douce, pas de clip dur
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * level
    fade = min(len(sig), int(0.03 * SR))
    sig[-fade:] *= np.linspace(1, 0, fade)
    # coupe le silence de fin
    keep = np.nonzero(np.abs(sig) > 0.001)[0]
    return sig[: keep[-1] + 1] if len(keep) else sig

# --- la palette ------------------------------------------------------------------------
N = note
SOUNDS = {
    # îlot
    "peek":     lambda: finish(mix([(kalimba(N("G5"), .3), 0, .8), (kalimba(N("C6"), .35), .07, .7)]), .55),
    "open":     lambda: finish(mix([(swoosh(.42, True, 1500, .5), 0, 1), (kalimba(N("C5"), .4), .1, .7),
                                     (kalimba(N("E5"), .4), .17, .6), (kalimba(N("G5"), .5), .24, .7),
                                     (bell(N("C6"), .7), .3, .25)]), .7),
    "close":    lambda: finish(mix([(swoosh(.32, False, 1300, .45), 0, 1), (kalimba(N("G5"), .3), .02, .6),
                                     (kalimba(N("C5"), .4), .1, .6)]), .55),
    "hover":    lambda: finish(mix([(bubble(N("E6"), N("G6"), .05), 0, 1)]), .22, wet=.08),
    "tick":     lambda: finish(mix([(click(.03, 2900), 0, 1), (kalimba(N("C7"), .08, .4), 0, .3)]), .35, wet=.05),
    "blip":     lambda: finish(mix([(bubble(N("C6"), N("G6"), .09), 0, 1)]), .5, wet=.1),
    "pop":      lambda: finish(mix([(bubble(N("G5"), N("D7"), .07, 1.2), 0, 1), (click(.02, 4200), .055, .4)]), .55, wet=.1),
    # bonjour
    "greet":    lambda: finish(mix([(kalimba(N("C5"), .4), 0, .8), (kalimba(N("E5"), .4), .1, .75),
                                     (kalimba(N("G5"), .4), .2, .75), (bell(N("C6"), .9), .3, .45)]), .7),
    "greeting": lambda: finish(mix([(kalimba(N("G4"), .4), 0, .7), (kalimba(N("C5"), .4), .12, .75),
                                     (kalimba(N("E5"), .4), .24, .75), (kalimba(N("G5"), .45), .36, .8),
                                     (bell(N("C6"), 1.1), .5, .5), (bell(N("E6"), 1.0), .62, .25)]), .75),
    # travail
    "work":     lambda: finish(mix([(kalimba(N("D5"), .18, .6), 0, .6), (kalimba(N("G5"), .2, .6), .09, .5)]), .4, wet=.1),
    "think":    lambda: finish(mix([(bell(N("A5"), .8), 0, .5), (bell(N("A5") * 1.006, .8), .02, .4),
                                     (bell(N("E6"), .7), .14, .3)]), .45, wet=.25),
    "search":   lambda: finish(mix([(bell(N("E6"), .6), 0, .6), (bell(N("E6"), .5), .26, .25)]), .45, wet=.3),
    # questions et accords
    "question": lambda: finish(mix([(kalimba(N("E5"), .3), 0, .8), (glide(N("G5"), N("C6"), .22, .7), .12, .45),
                                     (kalimba(N("C6"), .4), .14, .5)]), .65),
    "approval": lambda: finish(mix([(bell(N("G5"), .5), 0, .7), (bell(N("C6"), .6), .14, .75),
                                     (bell(N("G5"), .5), .4, .55), (bell(N("C6"), .7), .54, .65)]), .8),
    "approve":  lambda: finish(mix([(kalimba(N("C6"), .3), 0, .8), (kalimba(N("E6"), .45), .08, .8),
                                     (bell(N("G6"), .5), .12, .25)]), .6),
    "finish":   lambda: finish(mix([(kalimba(N("C5"), .3), 0, .7), (kalimba(N("E5"), .3), .08, .7),
                                     (kalimba(N("G5"), .3), .16, .7), (kalimba(N("C6"), .5), .24, .8),
                                     (bell(N("E6"), .9), .3, .35), (bell(N("G6"), .9), .38, .25)]), .75),
    # alerte : bien audible mais sympathique (« oh-oh »)
    "error":    lambda: finish(mix([(glide(N("E5"), N("D5"), .2, 1, .006), 0, .9), (kalimba(N("E5"), .25, 1.4), 0, .5),
                                     (glide(N("C5"), N("A4"), .34, 1.4, .012), .22, .95), (kalimba(N("C5"), .4, 1.4), .22, .5)]), .95, wet=.1),
    # humeurs
    "annoyed":  lambda: finish(mix([(glide(N("D4"), N("A3"), .3, 1, .03, 9), 0, 1), (thump(140, .15), 0, .5)]), .55, wet=.08),
    "dizzy":    lambda: finish(mix([(glide(N("C6"), N("C5"), .7, 1, .05, 7), 0, .8), (glide(N("E6"), N("E5"), .7, 1, .05, 5), .05, .4)]), .5),
    "slap":     lambda: finish(mix([(thump(120, .16), 0, 1), (bubble(N("E6"), N("C7"), .08), .05, .4)]), .6, wet=.08),
    "love":     lambda: finish(mix([(kalimba(N("E5"), .3), 0, .7), (kalimba(N("G5"), .4), .12, .7),
                                     (bell(N("E6"), .8), .2, .35), (bell(N("A6"), .7), .28, .2)]), .6, wet=.25),
    "proud":    lambda: finish(mix([(kalimba(N("G4"), .25), 0, .7), (kalimba(N("C5"), .25), .1, .7),
                                     (kalimba(N("G5"), .5), .2, .8), (bell(N("C6"), .8), .2, .35)]), .65),
    "wink":     lambda: finish(mix([(glide(N("G5"), N("D6"), .12, .6), 0, .7), (click(.02, 3800), .1, .4)]), .45, wet=.1),
    "yawn":     lambda: finish(mix([(glide(N("A4"), N("D4"), .9, 1.6, .01, 4), 0, .8)]), .45, wet=.2),
    "sleep":    lambda: finish(mix([(bell(N("E5"), 1.0), 0, .5), (bell(N("C5"), 1.2), .45, .45)]), .4, wet=.3),
    "rate":     lambda: finish(mix([(kalimba(N("G5"), .3), 0, .6), (kalimba(N("E5"), .3), .14, .6), (kalimba(N("C5"), .5), .28, .6)]), .55),
    # fichiers et messages
    "attach":   lambda: finish(mix([(click(.02, 3000), 0, .6), (click(.02, 3600), .04, .5), (kalimba(N("G5"), .35), .08, .7)]), .5),
    "send":     lambda: finish(mix([(swoosh(.28, True, 2200, .6), 0, 1), (kalimba(N("C6"), .3), .16, .5)]), .55),
    "gulp":     lambda: finish(mix([(bubble(N("A4"), N("D4"), .14, .8), 0, 1), (bubble(N("C5"), N("G5"), .08), .12, .5)]), .55, wet=.1),
}

def write(path: pathlib.Path, sig: np.ndarray):
    data = (np.clip(sig, -1, 1) * 32_000).astype("<i2").tobytes()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)

if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parent.parent
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "OliAssistant/Resources/sounds"
    out.mkdir(parents=True, exist_ok=True)
    for name, make in SOUNDS.items():
        sig = make()
        write(out / f"{name}.wav", sig)
        print(f"{name:9s} {len(sig) / SR:4.2f} s  crête {np.max(np.abs(sig)):.2f}")
