#!/usr/bin/env python3
"""Compare, sur un corpus de gen.py, les moments des voix calculés par le nouveau chemin (--voice-moments : regroupement adaptatif, fenêtres ambiguës rejetées, moments précis, bords calés
dans les pauses) à ceux de l'ancien (plages brutes, ou plages lissées par la grille de 0,5 s + comblement de 1,5 s + marge de 0,3 s).
Usage : bench2.py <dossier du corpus>"""
import json, os, subprocess, sys, tempfile
import numpy as np
work = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__)); APP = os.path.join(HERE, "..", "..", "mSLICE DEV.app")
T = json.load(open(os.path.join(work, "truth.json"))); D = T["duration"]; G = 100; N = int(D * G) + 1
spk = np.zeros((8, N), bool)
for u in T["utterances"]: spk[u["speaker"]][int(u["start"] * G):int(u["end"] * G)] = True
cnt = spk.sum(0); solo = [spk[k] & (cnt == 1) for k in range(8)]; ov = cnt >= 2; sil = cnt == 0
env = dict(os.environ, MSLICE_MODEL_DIR=os.path.expanduser("~/Library/Application Support/mSLICE DEV/models"), MSLICE_SESSION_DIR=tempfile.mkdtemp(), MSLICE_INDEX_DIR=tempfile.mkdtemp(), MSLICE_CLEAN_DIR=tempfile.mkdtemp())
out = os.path.join(work, "moments.json")
r = subprocess.run([os.path.join(APP, "Contents/MacOS/mSLICE"), "--voice-moments", os.path.join(work, "bench.mp4"), out], capture_output=True, text=True, env=env)
print(r.stdout.strip() or r.stderr.strip()[-200:])
M = json.load(open(out))
def mask(iv, smooth=False):
    m = np.zeros(N, bool)
    if smooth:   # ancien chemin : grille 0,5 s, comblement 1,5 s, durée minimale 1 s, marge 0,3 s
        cells = np.zeros(int(D / 0.5) + 2, bool)
        for a, b in iv: cells[int(a / 0.5):int(np.ceil(b / 0.5))] = True
        runs = []; i = 0
        while i < len(cells):
            if cells[i]:
                j = i
                while j < len(cells) and cells[j]: j += 1
                runs.append([i, j]); i = j
            else: i += 1
        merged = []
        for a, b in runs:
            if merged and a - merged[-1][1] <= 3: merged[-1][1] = b
            else: merged.append([a, b])
        iv = [(a * 0.5, b * 0.5) for a, b in merged if (b - a) * 0.5 >= 1.0]
        iv = [(max(a - 0.3, 0), min(b + 0.3, D)) for a, b in iv]
    for a, b in iv: m[int(a * G):int(b * G)] = True
    return m
def report(name, key, smooth=False):
    rows = []
    for v in M["voices"]:
        m = mask(v[key], smooth)
        if not m.any(): continue
        best = max(range(8), key=lambda k: (m & solo[k]).sum()); mt = m.sum()
        rows.append(((m & solo[best]).sum() / max(solo[best].sum(), 1), sum((m & solo[k]).sum() for k in range(8) if k != best) / mt, (m & ov).sum() / mt, (m & sil).sum() / mt, mt / G, best))
    if not rows: print("%-34s aucune voix" % name); return
    w = np.array([x[4] for x in rows]); avg = [np.average([x[i] for x in rows], weights=w) for i in range(4)]
    print("%-34s %d voix | rappel %3.0f %% | intrus %3.0f %% | chevauchement %3.0f %% | silence %3.0f %%" % (name, len(rows), *(100 * a for a in avg)))
print("fenêtres ambiguës : %d sur %d" % (M["ambiguous"], M["windows"]))
report("plages brutes (sans lissage)", "raw")
report("lissé comme avant (grille+1,5 s)", "raw", smooth=True)
report("NOUVEAU : moments précis", "moments")
