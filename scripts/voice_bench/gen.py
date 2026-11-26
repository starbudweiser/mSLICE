#!/usr/bin/env python3
"""Corpus de test des voix : un dialogue synthétique (voix « say » de macOS) avec des tours de parole, des pauses et des CHEVAUCHEMENTS connus à l'échantillon près.
Sortie : <dossier>/bench.mp4 (image noire + son) et <dossier>/truth.json (énoncés : début, fin, locuteur ; plages de chevauchement).
Usage : gen.py <dossier> [graine] [nombre d'énoncés]"""
import json, os, random, subprocess, sys, tempfile
import numpy as np
import soundfile as sf

out = sys.argv[1]; seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1; n = int(sys.argv[3]) if len(sys.argv) > 3 else 28
os.makedirs(out, exist_ok=True)
VOICES = ["Amélie", "Jacques", "Grandma (Français (France))", "Rocko (Français (Canada))"]
TEXTS = ["Tu as vu l'heure qu'il est, on devrait déjà être partis.", "Je ne pense pas que ce soit une bonne idée de continuer comme ça.",
         "Attends, laisse-moi t'expliquer ce qui s'est vraiment passé hier soir.", "Moi je trouve que le plan est parfait, on n'a plus qu'à l'exécuter.",
         "Écoute, je n'ai jamais dit que je voulais te faire du mal.", "Il faudra qu'on en parle avec tout le monde avant de décider.",
         "Tu me dis ça maintenant, alors que tout est déjà réservé depuis des semaines.", "C'est la dernière fois que je te prête ma voiture, c'est promis.",
         "Regarde cette lettre, elle était cachée derrière le tableau depuis le début.", "On pourrait aussi simplement lui demander directement, non ?",
         "Je suis fatigué de toujours tout expliquer à tout le monde.", "Personne ne m'a prévenu que la réunion avait été déplacée à ce matin."]
rng = random.Random(seed)
SR = 22050
def tts(voice, text):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f: p = f.name
    subprocess.run(["say", "-v", voice, "-o", p, "--data-format=LEF32@%d" % SR, text], check=True)
    x, _ = sf.read(p, dtype="float32"); os.unlink(p)
    if x.ndim > 1: x = x.mean(1)
    # coupe le silence de début et de fin pour que les bornes de vérité soient celles de la parole
    e = np.abs(x) > 0.01; i = np.argmax(e); j = len(e) - np.argmax(e[::-1])
    x = x[i:j]; return x / (np.abs(x).max() + 1e-9) * 0.5
utt, spk_prev, t_end_prev, overlaps = [], None, 0.0, []
mix = np.zeros(int(SR * (n * 5.5)), dtype=np.float32)
for k in range(n):
    spk = rng.choice([s for s in range(len(VOICES)) if s != spk_prev]); text = rng.choice(TEXTS)
    x = tts(VOICES[spk], text); d = len(x) / SR
    if k > 0 and k % 4 == 0:   # chevauchement : celui-ci commence avant la fin du précédent
        ov = min(rng.uniform(0.5, 1.1), d * 0.4, utt[-1]["end"] - utt[-1]["start"] - 0.3); start = t_end_prev - ov; overlaps.append([start, t_end_prev])
    else:
        start = t_end_prev + rng.uniform(0.25, 0.9)
    i = int(start * SR); mix[i:i + len(x)] += x
    utt.append({"start": round(start, 3), "end": round(start + d, 3), "speaker": spk, "voice": VOICES[spk]})
    spk_prev, t_end_prev = spk, start + d
mix = mix[:int((t_end_prev + 0.5) * SR)]
mix = mix / max(np.abs(mix).max(), 1e-6) * 0.7
wav = os.path.join(out, "bench.wav"); sf.write(wav, mix, SR)
json.dump({"seed": seed, "duration": len(mix) / SR, "utterances": utt, "overlaps": overlaps}, open(os.path.join(out, "truth.json"), "w"), indent=1)
ff = os.environ.get("FFMPEG", "ffmpeg")
subprocess.run([ff, "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=black:s=320x180:r=25", "-i", wav, "-shortest", "-c:v", "libx264" if False else "mpeg4", "-c:a", "aac", os.path.join(out, "bench.mp4")], check=True)
print("%d énoncés, %d chevauchements, %.1f s" % (len(utt), len(overlaps), len(mix) / SR))
