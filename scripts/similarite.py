#!/usr/bin/env python3
"""Mesure la part du code d'Oli identique à une base de référence.

Usage : scripts/similarite.py <dossier de référence> [--detail]
Compare chaque ligne significative (≥ 25 caractères, hors commentaires) des fichiers Swift
d'OliAssistant/Sources avec l'ensemble des lignes de la référence.
"""
import pathlib, re, sys

def lines(path):
    for l in path.read_text(errors="ignore").splitlines():
        n = re.sub(r"\s+", " ", l.strip())
        if len(n) >= 25 and not n.startswith(("//", "#")):
            yield n

if len(sys.argv) < 2:
    sys.exit(__doc__)
ref = {l for f in pathlib.Path(sys.argv[1]).rglob("*.swift") for l in lines(f)}
root = pathlib.Path(__file__).resolve().parent.parent / "OliAssistant/Sources"
total = same = 0
per = {}
for f in sorted(root.rglob("*.swift")):
    t = s = 0
    for l in lines(f):
        t += 1
        if l in ref:
            s += 1
    total += t; same += s
    per[f.relative_to(root).as_posix()] = (s, t)
print(f"{same}/{total} lignes identiques ({same * 100 / max(total, 1):.1f} %)")
if "--detail" in sys.argv:
    for name, (s, t) in sorted(per.items(), key=lambda x: -x[1][0]):
        if s:
            print(f"  {s:5d}/{t:<5d} {s * 100 / max(t, 1):5.1f} %  {name}")
