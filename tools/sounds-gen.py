#!/usr/bin/env python3
"""
sounds-gen.py — Sound design v2 d'Oli (assistant Oculot dans l'encoche).

Génère les 29 fichiers WAV de OliAssistant/Resources/sounds/ en PURE PYTHON
(modules standard uniquement : math, wave, struct, random). 44,1 kHz, mono, 16 bits.

    python3 design/sounds-gen.py            # écrit dans OliAssistant/Resources/sounds/
    python3 design/sounds-gen.py --out DIR  # écrit ailleurs (test)
    python3 design/sounds-gen.py --list     # affiche la table des sons sans rien écrire

Principes (détail dans design/sounds/README.md) :
  * Timbre : synthèse FM à 2 opérateurs, index faible et décroissant
    (« bloop » doux, rond, légèrement électronique), petite sous-octave,
    enveloppes ADSR sans clic, delay court optionnel pour l'espace.
  * Signature « Oli » : do – mi – la (tierce majeure puis quarte, 0 / +4 / +9
    demi-tons). Elle se retrouve dans greet, greeting, finish, proud et approve,
    déclinée (plus courte, plus grave, plus aiguë).
  * Niveaux : chaque son est normalisé en crête vers la cible de sa famille,
    toutes ≤ -6 dBFS (micro-interactions à -14 dBFS). Jamais de clipping.
"""

import math
import os
import random
import struct
import sys
import wave

SR = 44100               # fréquence d'échantillonnage
TWO_PI = 2.0 * math.pi

# --------------------------------------------------------------------------
# Hauteurs
# --------------------------------------------------------------------------

A4 = 440.0


def note(semitones_from_a4):
    """Fréquence (Hz) d'une note exprimée en demi-tons depuis A4 (440 Hz)."""
    return A4 * (2.0 ** (semitones_from_a4 / 12.0))


# Degrés utiles, en demi-tons depuis A4. Le "do" de référence d'Oli est C5.
C5 = 3            # do
E5 = 7            # mi
A5 = 12           # la
C6 = 15
E6 = 19
A6 = 24
C4 = -9
E4 = -5
A4_ = 0
G5 = 10
F5 = 8
D5 = 5
B5 = 14
Bb5 = 13
Ab5 = 11
G4 = -2
B4 = 2

# Motif signature : do – mi – la (intervalle 0, +4, +9).
SIGNATURE = (0, 4, 9)


def sig(root, scale=1.0):
    """Les 3 degrés du motif signature transposés sur `root` (demi-tons A4)."""
    return [root + s * scale for s in SIGNATURE]


# --------------------------------------------------------------------------
# Briques de synthèse
# --------------------------------------------------------------------------

def silence(dur):
    return [0.0] * int(dur * SR)


def adsr(n, a, d, s, r):
    """Enveloppe ADSR lissée sur n échantillons. a/d/r en secondes, s niveau 0..1.
    L'attaque suit une courbe 1-exp (douce), la décroissance et la relâche sont
    exponentielles vers leur cible pour éviter tout clic."""
    env = [0.0] * n
    na = max(1, int(a * SR))
    nd = max(1, int(d * SR))
    nr = max(1, int(r * SR))
    rel_start = max(na, n - nr)
    for i in range(n):
        if i < na:
            x = i / na
            v = 1.0 - math.exp(-5.0 * x)
            v /= (1.0 - math.exp(-5.0))
        elif i < na + nd:
            x = (i - na) / nd
            v = s + (1.0 - s) * math.exp(-4.0 * x)
        else:
            v = s + (1.0 - s) * math.exp(-4.0)
        if i >= rel_start:
            x = (i - rel_start) / max(1, n - rel_start)
            # relâche en cosinus (très douce), tend vers 0 exactement
            v *= 0.5 * (1.0 + math.cos(math.pi * min(1.0, x)))
        env[i] = v
    return env


def tone(freq, dur, env=(0.008, 0.08, 0.6, 0.12), ratio=2.0, index=0.9,
         fm_decay=0.15, glide_to=None, glide_time=None, vibrato=(0.0, 0.0),
         sub=0.18, amp=1.0, curve="exp"):
    """Une note FM douce.

    freq       : fréquence de départ (Hz)
    dur        : durée totale (s), relâche comprise
    env        : (attack, decay, sustain, release)
    ratio      : rapport fréquence modulateur / porteuse (2 = octave, timbre creux
                 et rond ; 1 = plus plein ; 3 = un peu de nasillard, pour « annoyed »)
    index      : indice de modulation initial (0.3 très pur, 1.5 bien « bloop »)
    fm_decay   : constante de temps (s) de la décroissance de l'indice —
                 la brillance s'estompe vite, signature des bloops doux
    glide_to   : fréquence d'arrivée si la note glisse ; glide_time : durée du glissando
    vibrato    : (fréquence Hz, profondeur en demi-tons)
    sub        : niveau de la sous-octave sinus (chaleur)
    amp        : gain relatif dans le mix
    """
    n = int(dur * SR)
    e = adsr(n, *env)
    out = [0.0] * n
    ph_c = 0.0
    ph_m = 0.0
    ph_s = 0.0
    gt = glide_time if glide_time is not None else dur
    vib_rate, vib_depth = vibrato
    for i in range(n):
        t = i / SR
        f = freq
        if glide_to is not None:
            x = min(1.0, t / gt)
            if curve == "exp":
                x = 1.0 - math.exp(-4.0 * x) if gt > 0 else 1.0
                x /= (1.0 - math.exp(-4.0))
            f = freq * (glide_to / freq) ** x
        if vib_depth:
            f *= 2.0 ** (vib_depth * math.sin(TWO_PI * vib_rate * t) / 12.0)
        idx = index * math.exp(-t / fm_decay) if fm_decay > 0 else index
        ph_m += TWO_PI * f * ratio / SR
        ph_c += TWO_PI * f / SR
        ph_s += TWO_PI * f * 0.5 / SR
        v = math.sin(ph_c + idx * math.sin(ph_m))
        if sub:
            v += sub * math.sin(ph_s)
        out[i] = v * e[i] * amp
    return out


def noise(dur, env=(0.002, 0.03, 0.0, 0.05), cutoff=3000.0, amp=1.0, seed=7):
    """Bruit blanc filtré passe-bas (1 pôle) avec enveloppe — pour un souffle,
    un petit claquement. Déterministe via `seed`."""
    n = int(dur * SR)
    e = adsr(n, *env)
    rng = random.Random(seed)
    k = 1.0 - math.exp(-TWO_PI * cutoff / SR)
    y = 0.0
    out = [0.0] * n
    for i in range(n):
        y += k * (rng.uniform(-1.0, 1.0) - y)
        out[i] = y * e[i] * amp
    return out


def mix(dur, parts):
    """Superpose des (start_s, buffer) dans un tampon de `dur` secondes."""
    n = int(dur * SR)
    out = [0.0] * n
    for start, buf in parts:
        o = int(start * SR)
        for i, v in enumerate(buf):
            j = o + i
            if 0 <= j < n:
                out[j] += v
    return out


def delay(buf, time=0.075, feedback=0.3, wet=0.22, damp=0.35):
    """Delay court avec filtre passe-bas dans la boucle : donne un peu
    d'espace sans brouiller les notes courtes."""
    n = len(buf)
    d = int(time * SR)
    out = list(buf)
    line = [0.0] * n
    lp = 0.0
    for i in range(n):
        back = line[i - d] if i - d >= 0 else 0.0
        lp += damp * (back - lp)
        line[i] = buf[i] + lp * feedback
        out[i] += lp * wet
    return out


def fade_tail(buf, dur=0.01):
    """Petit fondu de sortie absolu pour garantir zéro clic en fin de fichier."""
    n = len(buf)
    k = min(n, int(dur * SR))
    for i in range(k):
        buf[n - 1 - i] *= i / k
    return buf


def normalize(buf, target_dbfs):
    """Normalisation en crête vers target_dbfs, puis garde-fou soft-clip (jamais
    atteint en pratique, la cible étant ≤ -6 dBFS)."""
    peak = max(1e-9, max(abs(v) for v in buf))
    g = (10.0 ** (target_dbfs / 20.0)) / peak
    return [max(-0.999, min(0.999, v * g)) for v in buf]


def write_wav(path, buf):
    frames = struct.pack("<%dh" % len(buf), *[int(round(v * 32767.0)) for v in buf])
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)


# --------------------------------------------------------------------------
# Familles et niveaux (crête cible en dBFS)
# --------------------------------------------------------------------------

LEVELS = {
    "micro":     -14.0,   # tick hover blip pop
    "ui":        -9.0,    # open close peek send attach gulp wink
    "status":    -9.0,    # work think search approval question sleep yawn
    "signature": -6.0,    # greet greeting finish proud approve
    "alert":     -6.5,    # error rate
    "emote":     -8.0,    # love annoyed slap dizzy
}

# raccourcis d'enveloppe
SHORT = (0.004, 0.05, 0.3, 0.06)     # bloop bref
MED = (0.008, 0.10, 0.5, 0.15)       # note tenue courte
LONG = (0.015, 0.20, 0.6, 0.30)      # note posée


# --------------------------------------------------------------------------
# Les 29 sons
# Chaque fonction renvoie (famille, tampon flottant).
# --------------------------------------------------------------------------

def s_tick():
    # Micro-impulsion : une note très courte, index un peu plus haut pour le « tk »
    b = tone(note(C6), 0.05, env=(0.001, 0.02, 0.0, 0.025), ratio=3.0, index=0.6,
             fm_decay=0.01, sub=0.0)
    return "micro", b


def s_hover():
    b = tone(note(A5), 0.08, env=(0.003, 0.04, 0.1, 0.035), ratio=2.0, index=0.5,
             fm_decay=0.03, sub=0.1)
    return "micro", b


def s_blip():
    # Petit « blip » montant d'un ton
    b = tone(note(E5), 0.12, env=(0.003, 0.05, 0.3, 0.05), ratio=2.0, index=0.8,
             fm_decay=0.05, glide_to=note(E5 + 2), glide_time=0.06)
    return "micro", b


def s_pop():
    # Bulle qui éclate : départ aigu, chute rapide d'une octave
    b = tone(note(E6), 0.14, env=(0.002, 0.06, 0.2, 0.06), ratio=1.0, index=1.2,
             fm_decay=0.04, glide_to=note(E5), glide_time=0.08, sub=0.25)
    return "micro", b


def s_open():
    # Deux notes rapides montantes (do → mi) : l'îlot se déploie
    b = mix(0.35, [
        (0.00, tone(note(C5), 0.18, env=SHORT, index=0.9, fm_decay=0.08)),
        (0.10, tone(note(E5), 0.25, env=(0.006, 0.08, 0.4, 0.12), index=0.8, fm_decay=0.10)),
    ])
    return "ui", b


def s_close():
    # Miroir d'open (mi → do), plus feutré
    b = mix(0.33, [
        (0.00, tone(note(E5), 0.16, env=SHORT, index=0.7, fm_decay=0.07)),
        (0.09, tone(note(C5), 0.24, env=(0.006, 0.08, 0.35, 0.12), index=0.6, fm_decay=0.09, sub=0.25)),
    ])
    return "ui", b


def s_peek():
    # Oli sort la tête : un « boop » qui glisse vers le haut d'une quarte
    b = tone(note(G5), 0.40, env=(0.010, 0.12, 0.45, 0.18), index=1.0, fm_decay=0.12,
             glide_to=note(C6), glide_time=0.14)
    return "ui", b


def s_send():
    # Envoi : glissando ascendant long + léger souffle (whoosh)
    b = mix(0.35, [
        (0.00, tone(note(E5), 0.33, env=(0.008, 0.10, 0.5, 0.14), index=1.0, fm_decay=0.15,
                    glide_to=note(E6), glide_time=0.26, sub=0.1)),
        (0.02, noise(0.28, env=(0.05, 0.10, 0.4, 0.12), cutoff=2500.0, amp=0.25, seed=3)),
    ])
    return "ui", b


def s_attach():
    # Fenêtre attachée : petit clic + deux notes qui « s'emboîtent » (sol → do)
    b = mix(0.50, [
        (0.00, noise(0.05, env=(0.001, 0.02, 0.0, 0.025), cutoff=4000.0, amp=0.6, seed=11)),
        (0.02, tone(note(G5), 0.20, env=SHORT, index=0.8, fm_decay=0.08)),
        (0.16, tone(note(C6), 0.32, env=(0.006, 0.10, 0.4, 0.16), index=0.7, fm_decay=0.12)),
    ])
    return "ui", b


def s_gulp():
    # Fichier avalé : « glup », glissando descendant d'une octave avec rondeur grave
    b = mix(0.50, [
        (0.00, tone(note(A5), 0.40, env=(0.010, 0.10, 0.5, 0.18), ratio=1.0, index=1.3,
                    fm_decay=0.12, glide_to=note(A4_), glide_time=0.22, sub=0.35)),
        (0.26, tone(note(C4), 0.22, env=(0.008, 0.08, 0.3, 0.10), ratio=1.0, index=0.4,
                    fm_decay=0.05, sub=0.4, amp=0.7)),
    ])
    return "ui", b


def s_wink():
    # Clin d'œil : un chirp bref et brillant qui monte d'une tierce
    b = tone(note(A5), 0.22, env=(0.004, 0.08, 0.3, 0.10), ratio=2.0, index=1.1, fm_decay=0.06,
             glide_to=note(C6 + 1), glide_time=0.09)
    return "emote", b


def s_work():
    # Claude Code travaille : deux bulles courtes, discrètes (do, sol)
    b = mix(0.30, [
        (0.00, tone(note(C5), 0.14, env=SHORT, index=0.7, fm_decay=0.05, amp=0.9)),
        (0.12, tone(note(G5), 0.17, env=SHORT, index=0.7, fm_decay=0.05)),
    ])
    return "status", b


def s_think():
    # Réfléchit : trois petites bulles qui montent doucement (ré, mi, sol), espacées
    b = mix(0.45, [
        (0.00, tone(note(D5), 0.14, env=SHORT, index=0.6, fm_decay=0.05, amp=0.8)),
        (0.14, tone(note(E5), 0.14, env=SHORT, index=0.6, fm_decay=0.05, amp=0.9)),
        (0.28, tone(note(G5), 0.16, env=SHORT, index=0.6, fm_decay=0.05)),
    ])
    return "status", b


def s_search():
    # Cherche : un « ping » aller-retour (monte puis redescend), comme un sonar doux
    b = mix(0.45, [
        (0.00, tone(note(E5), 0.22, env=(0.006, 0.08, 0.4, 0.10), index=0.9, fm_decay=0.10,
                    glide_to=note(A5), glide_time=0.16)),
        (0.20, tone(note(A5), 0.24, env=(0.006, 0.08, 0.4, 0.12), index=0.9, fm_decay=0.10,
                    glide_to=note(E5), glide_time=0.18, amp=0.85)),
    ])
    return "status", b


def s_question():
    # Attend une réponse : intonation interrogative, une note qui monte en fin (la → do ?)
    b = mix(0.50, [
        (0.00, tone(note(A4_), 0.20, env=(0.008, 0.08, 0.5, 0.08), index=0.8, fm_decay=0.10)),
        (0.17, tone(note(A4_), 0.33, env=(0.008, 0.10, 0.6, 0.14), index=0.8, fm_decay=0.14,
                    glide_to=note(D5), glide_time=0.20)),
    ])
    return "status", b


def s_approval():
    # Demande d'autorisation : question posée deux fois, poliment (do…mi ? do…mi ?)
    pair = [
        (0.00, tone(note(C5), 0.18, env=MED, index=0.8, fm_decay=0.10, amp=0.9)),
        (0.15, tone(note(E5), 0.28, env=(0.008, 0.10, 0.5, 0.14), index=0.8, fm_decay=0.12,
                    glide_to=note(F5), glide_time=0.20)),
    ]
    b = mix(0.90, pair + [(s + 0.46, buf) for s, buf in pair])
    b = delay(b, time=0.09, feedback=0.25, wet=0.18)
    return "status", b


def s_sleep():
    # S'endort : deux notes graves descendantes très rondes, index minimal
    b = mix(0.50, [
        (0.00, tone(note(E4), 0.28, env=(0.020, 0.12, 0.5, 0.14), index=0.4, fm_decay=0.15, sub=0.35)),
        (0.22, tone(note(C4), 0.28, env=(0.020, 0.12, 0.4, 0.16), index=0.3, fm_decay=0.15, sub=0.4, amp=0.85)),
    ])
    return "status", b


def s_yawn():
    # Bâille : longue note qui monte puis retombe, avec un vibrato lent
    b = mix(0.70, [
        (0.00, tone(note(G4), 0.36, env=(0.040, 0.15, 0.7, 0.12), ratio=1.0, index=0.7, fm_decay=0.25,
                    glide_to=note(D5), glide_time=0.30, vibrato=(5.0, 0.25), sub=0.3)),
        (0.30, tone(note(D5), 0.40, env=(0.030, 0.15, 0.6, 0.20), ratio=1.0, index=0.6, fm_decay=0.25,
                    glide_to=note(E4), glide_time=0.36, vibrato=(5.0, 0.3), sub=0.35)),
    ])
    return "status", b


def s_error():
    # Erreur : deux notes descendantes d'une quarte (mi → si), tenues, timbre plein
    # (ratio 1) et sans agressivité — un « uh-oh » plus qu'une alarme
    b = mix(0.65, [
        (0.00, tone(note(E5), 0.30, env=(0.010, 0.12, 0.5, 0.14), ratio=1.0, index=0.9, fm_decay=0.14, sub=0.3)),
        (0.24, tone(note(B4), 0.40, env=(0.010, 0.14, 0.5, 0.20), ratio=1.0, index=0.8, fm_decay=0.16, sub=0.35)),
    ])
    b = delay(b, time=0.07, feedback=0.2, wet=0.15)
    return "alert", b


def s_rate():
    # Quota atteint : trois notes qui descendent par paliers (sol, mi, do) — « on s'arrête là »
    b = mix(0.60, [
        (0.00, tone(note(G5), 0.20, env=MED, index=0.8, fm_decay=0.10, sub=0.25)),
        (0.17, tone(note(E5), 0.20, env=MED, index=0.8, fm_decay=0.10, sub=0.25)),
        (0.34, tone(note(C5), 0.26, env=(0.008, 0.10, 0.5, 0.14), index=0.7, fm_decay=0.12, sub=0.3)),
    ])
    return "alert", b


def s_annoyed():
    # On le pique : « hmph », note qui chute vite, timbre un peu nasal (ratio 3)
    b = tone(note(A5), 0.42, env=(0.006, 0.12, 0.45, 0.20), ratio=3.0, index=1.0, fm_decay=0.10,
             glide_to=note(E4), glide_time=0.16, vibrato=(9.0, 0.15), sub=0.3)
    return "emote", b


def s_slap():
    # Tape : claquement feutré (bruit filtré) + court « ouh » grave
    b = mix(0.20, [
        (0.00, noise(0.07, env=(0.001, 0.03, 0.0, 0.03), cutoff=1800.0, amp=0.9, seed=5)),
        (0.01, tone(note(C5), 0.18, env=(0.002, 0.06, 0.2, 0.09), ratio=1.0, index=1.4, fm_decay=0.03,
                    glide_to=note(E4), glide_time=0.09, sub=0.4, amp=0.8)),
    ])
    return "emote", b


def s_dizzy():
    # Étourdi : note qui tourne (vibrato large qui ralentit) et descend en spirale
    n = int(0.95 * SR)
    out = [0.0] * n
    e = adsr(n, 0.02, 0.2, 0.6, 0.3)
    ph_c = ph_m = ph_s = 0.0
    for i in range(n):
        t = i / SR
        # vibrato qui ralentit (10 Hz → 4 Hz) et s'élargit
        rate = 10.0 - 6.0 * (t / 0.95)
        depth = 0.6 + 1.2 * (t / 0.95)
        f = note(A5) * (2.0 ** (-7.0 * (t / 0.95) / 12.0))      # descend d'une quinte
        f *= 2.0 ** (depth * math.sin(TWO_PI * rate * t) / 12.0)
        idx = 0.9 * math.exp(-t / 0.3)
        ph_m += TWO_PI * f * 2.0 / SR
        ph_c += TWO_PI * f / SR
        ph_s += TWO_PI * f * 0.5 / SR
        out[i] = (math.sin(ph_c + idx * math.sin(ph_m)) + 0.25 * math.sin(ph_s)) * e[i]
    return "emote", out


def s_love():
    # Cœur : deux notes sucrées (mi → la, sixte) avec vibrato léger et un peu d'écho
    b = mix(0.70, [
        (0.00, tone(note(E5), 0.26, env=(0.012, 0.10, 0.6, 0.12), index=0.8, fm_decay=0.12, vibrato=(6.0, 0.10))),
        (0.18, tone(note(A5), 0.48, env=(0.012, 0.16, 0.6, 0.24), index=0.8, fm_decay=0.16, vibrato=(6.0, 0.15))),
        (0.18, tone(note(C6 + 1), 0.44, env=(0.015, 0.16, 0.5, 0.22), index=0.5, fm_decay=0.16, amp=0.35)),  # tierce douce
    ])
    b = delay(b, time=0.10, feedback=0.3, wet=0.2)
    return "emote", b


# --- Famille signature : do – mi – la ---------------------------------------

def s_approve():
    # Autorisé : la signature raccourcie à ses 2 premières notes (do → mi), vive, aiguë
    r = C6
    b = mix(0.47, [
        (0.00, tone(note(sig(r)[0]), 0.18, env=SHORT, index=0.9, fm_decay=0.07)),
        (0.11, tone(note(sig(r)[1]), 0.34, env=(0.006, 0.10, 0.45, 0.16), index=0.8, fm_decay=0.10)),
    ])
    return "signature", b


def s_greet():
    # Salut : la signature complète au registre médian, rythme serré
    r = C5
    d = sig(r)
    b = mix(0.60, [
        (0.00, tone(note(d[0]), 0.20, env=MED, index=0.9, fm_decay=0.10)),
        (0.13, tone(note(d[1]), 0.20, env=MED, index=0.9, fm_decay=0.10)),
        (0.26, tone(note(d[2]), 0.32, env=(0.008, 0.12, 0.5, 0.16), index=0.8, fm_decay=0.14)),
    ])
    b = delay(b, time=0.08, feedback=0.22, wet=0.15)
    return "signature", b


def s_finish():
    # Terminé : signature plus aiguë, dernière note doublée à l'octave grave pour l'assise
    r = C6
    d = sig(r)
    b = mix(1.10, [
        (0.00, tone(note(d[0]), 0.22, env=MED, index=0.9, fm_decay=0.10)),
        (0.15, tone(note(d[1]), 0.22, env=MED, index=0.9, fm_decay=0.10)),
        (0.30, tone(note(d[2]), 0.70, env=(0.010, 0.20, 0.55, 0.35), index=0.6, fm_decay=0.18)),
        (0.30, tone(note(d[2] - 12), 0.70, env=(0.012, 0.20, 0.5, 0.35), index=0.4, fm_decay=0.18, sub=0.35, amp=0.6)),
    ])
    b = delay(b, time=0.11, feedback=0.3, wet=0.2)
    return "signature", b


def s_proud():
    # Fier : signature plus grave et plus lente, avec une petite « bosse » de rebond sur la fin
    r = G4  # variante transposée une quarte plus bas : grave et posée
    d = sig(r)
    b = mix(0.85, [
        (0.00, tone(note(d[0]), 0.26, env=MED, index=0.8, fm_decay=0.12, sub=0.3)),
        (0.18, tone(note(d[1]), 0.26, env=MED, index=0.8, fm_decay=0.12, sub=0.3)),
        (0.36, tone(note(d[2]), 0.46, env=(0.010, 0.16, 0.55, 0.22), index=0.8, fm_decay=0.16, sub=0.3,
                    vibrato=(5.5, 0.08))),
        (0.60, tone(note(d[2] + 12), 0.22, env=SHORT, index=0.7, fm_decay=0.06, amp=0.35)),  # petit éclat
    ])
    b = delay(b, time=0.09, feedback=0.25, wet=0.18)
    return "signature", b


def s_greeting():
    # Salut au lancement (≈ 2,2 s) : la signature exposée lentement, répondue à
    # l'octave supérieure en « écho », puis une résolution douce (la → do aigu)
    # avec une petite étincelle. Le son est coupé en fondu par l'app si on l'interrompt.
    r = C5
    d = sig(r)
    parts = [
        # exposition
        (0.00, tone(note(d[0]), 0.40, env=LONG, index=0.9, fm_decay=0.18)),
        (0.28, tone(note(d[1]), 0.40, env=LONG, index=0.9, fm_decay=0.18)),
        (0.56, tone(note(d[2]), 0.60, env=(0.015, 0.20, 0.6, 0.30), index=0.8, fm_decay=0.20)),
        # réponse à l'octave, plus légère
        (0.90, tone(note(d[0] + 12), 0.26, env=MED, index=0.7, fm_decay=0.10, amp=0.55)),
        (1.08, tone(note(d[1] + 12), 0.26, env=MED, index=0.7, fm_decay=0.10, amp=0.55)),
        (1.26, tone(note(d[2] + 12), 0.50, env=(0.012, 0.18, 0.5, 0.26), index=0.6, fm_decay=0.16, amp=0.5)),
        # résolution : do aigu tenu, avec assise grave
        (1.60, tone(note(C6), 0.60, env=(0.020, 0.22, 0.55, 0.30), index=0.6, fm_decay=0.22, vibrato=(5.0, 0.06))),
        (1.60, tone(note(C5), 0.60, env=(0.025, 0.22, 0.5, 0.30), index=0.4, fm_decay=0.22, sub=0.4, amp=0.6)),
        # étincelle (le satellite passe)
        (1.78, tone(note(E6), 0.16, env=(0.003, 0.06, 0.2, 0.08), index=0.9, fm_decay=0.04, sub=0.0, amp=0.28)),
        (1.90, tone(note(A6), 0.16, env=(0.003, 0.06, 0.2, 0.08), index=0.9, fm_decay=0.04, sub=0.0, amp=0.22)),
    ]
    b = mix(2.20, parts)
    b = delay(b, time=0.12, feedback=0.32, wet=0.22)
    return "signature", b


SOUNDS = {
    "tick": s_tick, "hover": s_hover, "blip": s_blip, "pop": s_pop,
    "open": s_open, "close": s_close, "peek": s_peek, "send": s_send,
    "attach": s_attach, "gulp": s_gulp, "wink": s_wink,
    "work": s_work, "think": s_think, "search": s_search,
    "question": s_question, "approval": s_approval, "sleep": s_sleep, "yawn": s_yawn,
    "error": s_error, "rate": s_rate,
    "annoyed": s_annoyed, "slap": s_slap, "dizzy": s_dizzy, "love": s_love,
    "approve": s_approve, "greet": s_greet, "finish": s_finish, "proud": s_proud,
    "greeting": s_greeting,
}

EXPECTED = sorted("""annoyed approval approve attach blip close dizzy error finish greet
greeting gulp hover love open peek pop proud question rate search send sleep slap think
tick wink work yawn""".split())


def render(name):
    family, buf = SOUNDS[name]()
    buf = fade_tail(buf)
    buf = normalize(buf, LEVELS[family])
    return family, buf


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.normpath(os.path.join(here, "..", "Oli", "Resources", "sounds"))
    if "--out" in argv:
        out_dir = argv[argv.index("--out") + 1]
    list_only = "--list" in argv

    assert sorted(SOUNDS) == EXPECTED, "la liste des sons ne correspond pas au contrat"
    if not list_only:
        os.makedirs(out_dir, exist_ok=True)

    print("%-10s %-10s %7s %9s" % ("son", "famille", "durée", "crête"))
    for name in EXPECTED:
        family, buf = render(name)
        peak = max(abs(v) for v in buf)
        peak_db = 20.0 * math.log10(max(peak, 1e-9))
        print("%-10s %-10s %6.2fs %7.1f dB" % (name, family, len(buf) / SR, peak_db))
        if not list_only:
            write_wav(os.path.join(out_dir, name + ".wav"), buf)
    if not list_only:
        print("→ %d fichiers écrits dans %s" % (len(EXPECTED), out_dir))


if __name__ == "__main__":
    main(sys.argv[1:])
