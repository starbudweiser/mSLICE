#!/usr/bin/env python3
"""Mesure la qualité des moments d'une voix sur un corpus de gen.py : ce que voit l'utilisateur dans l'onglet Personnes (passages par voix).
Usage : bench.py <dossier du corpus> [mslice-mcp]
Pour chaque voix reconnue (associée au locuteur réel qui parle le plus dans ses passages) :
  rappel      = part de la parole SOLO du locuteur qui est dans les passages ;
  intrus      = part des passages occupée par la parole SOLO d'un AUTRE locuteur (« bouts de dialogue d'autres personnages ») ;
  chevauche   = part des passages en chevauchement ; silence = part des passages sans parole."""
import json, os, subprocess, sys, tempfile, shutil
import numpy as np

work = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__)); APP = os.path.join(HERE, "..", "..", "mSLICE DEV.app")
MCP = sys.argv[2] if len(sys.argv) > 2 else os.path.join(APP, "Contents/MacOS/mslice-mcp")
DOMAIN = "fr.stephan.mslice.dev"
truth = json.load(open(os.path.join(work, "truth.json"))); dur = truth["duration"]
tmp = tempfile.mkdtemp(prefix="vbench-")
env = dict(os.environ, MSLICE_SESSION_DIR=os.path.join(tmp, "s"), MSLICE_AGENT_SOCKET=os.path.join(tmp, "none.sock"), MSLICE_INDEX_DIR=os.path.join(tmp, "i"),
           MSLICE_MODEL_DIR=os.path.expanduser("~/Library/Application Support/mSLICE DEV/models"))
prev = subprocess.run(["defaults", "read", DOMAIN, "agent.enabled"], capture_output=True, text=True)
subprocess.run(["defaults", "write", DOMAIN, "agent.enabled", "-bool", "true"])
proc = subprocess.Popen([MCP], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=env)
n = [0]
def rpc(method, params=None, notify=False):
    n[0] += 1; msg = {"jsonrpc": "2.0", "method": method, **({"params": params} if params is not None else {})}
    if not notify: msg["id"] = n[0]
    proc.stdin.write(json.dumps(msg) + "\n"); proc.stdin.flush()
    return None if notify else json.loads(proc.stdout.readline())
def call(tool, **a):
    r = rpc("tools/call", {"name": tool, "arguments": a})["result"]; t = "\n".join(c["text"] for c in r["content"] if c["type"] == "text")
    try: return json.loads(t)
    except Exception: return t
try:
    rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "vbench", "version": "1"}}); rpc("notifications/initialized", notify=True)
    path = os.path.join(work, "bench.mp4")
    r = call("analyze_media", path=path, voices=True)
    subs = call("list_subjects", path=path)
    voices = [v["id"] for v in subs.get("voices", [])] if isinstance(subs, dict) else []
    G = 100   # grille de 10 ms
    N = int(dur * G) + 1
    spk = [np.zeros(N, bool) for _ in range(8)]
    for u in truth["utterances"]: spk[u["speaker"]][int(u["start"] * G):int(u["end"] * G)] = True
    nsp = sum(1 for s in spk if s.any())
    count = np.sum([s for s in spk], axis=0)
    solo = [s & (count == 1) for s in spk]; ov = count >= 2; sil = count == 0
    print("voix reconnues : %d (vérité : %d locuteurs, %d chevauchements)" % (len(voices), nsp, len(truth["overlaps"])))
    rows = []
    for v in voices:
        res = call("find_scenes", path=path, include=[v], whole_shots=False, min_length=0.1)
        m = np.zeros(N, bool)
        for p in res.get("passages", []) if isinstance(res, dict) else []: m[int(p["start"] * G):int(p["end"] * G)] = True
        if not m.any(): continue
        best = max(range(8), key=lambda k: (m & solo[k]).sum())
        mt = m.sum()
        rows.append((v, best, (m & solo[best]).sum() / max(solo[best].sum(), 1), sum((m & solo[k]).sum() for k in range(8) if k != best) / mt, (m & ov).sum() / mt, (m & sil).sum() / mt, mt / G))
        print("  %-8s ↔ locuteur %d : rappel %3.0f %%, intrus %3.0f %%, chevauchement %3.0f %%, silence %3.0f %% (%.1f s)" % (v, best, 100 * rows[-1][2], 100 * rows[-1][3], 100 * rows[-1][4], 100 * rows[-1][5], rows[-1][6]))
    if rows:
        w = np.array([r[6] for r in rows])
        print("MOYENNE : rappel %.0f %%, intrus %.0f %%, chevauchement %.0f %%, silence %.0f %%" % tuple(100 * np.average([r[i] for r in rows], weights=w) for i in (2, 3, 4, 5)))
finally:
    proc.kill()
    if prev.returncode == 0: subprocess.run(["defaults", "write", DOMAIN, "agent.enabled", "-bool", "true" if prev.stdout.strip() in ("1", "true") else "false"])
    else: subprocess.run(["defaults", "delete", DOMAIN, "agent.enabled"])
    shutil.rmtree(tmp, ignore_errors=True)
