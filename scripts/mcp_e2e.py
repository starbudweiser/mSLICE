#!/usr/bin/env python3
"""Essai de bout en bout de mslice-mcp, SANS l'appli ouverte (mode autonome) : protocole MCP, garde-fous, découpe, fusion, silences.
Usage : scripts/mcp_e2e.py [chemin/mslice-mcp]   (défaut : « mSLICE DEV.app »). Active puis rétablit le réglage « Autoriser un agent » de l'édition DEV."""
import json, os, subprocess, sys, tempfile, shutil, time

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, "..", "mSLICE DEV.app")
MCP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(APP, "Contents/MacOS/mslice-mcp")
FFMPEG = os.path.join(APP, "Contents/Helpers/ffmpeg")
DOMAIN = "fr.stephan.mslice.dev"
fails = 0
def check(ok, msg):
    global fails
    print(("OK     " if ok else "ÉCHEC  ") + msg)
    if not ok: fails += 1

def defaults(*a): return subprocess.run(["defaults", *a], capture_output=True, text=True)
prev = defaults("read", DOMAIN, "agent.enabled")
prev_val = prev.stdout.strip() if prev.returncode == 0 else None

work = tempfile.mkdtemp(prefix="mslice-e2e-")
env = dict(os.environ, MSLICE_SESSION_DIR=os.path.join(work, "sessions"), MSLICE_AGENT_SOCKET=os.path.join(work, "none.sock"))
proc = None
try:
    # fixtures : 30 s de vidéo avec son (bip toutes les 5 s dans un silence), et un fichier audio « 4 s de silence, 4 s de son, 4 s de silence »
    vid = os.path.join(work, "essai.mp4")
    subprocess.run([FFMPEG, "-nostdin", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=320x180:rate=25:duration=30", "-f", "lavfi", "-i", "sine=frequency=440:duration=30",
                    "-c:v", "h264_videotoolbox", "-g", "50", "-b:v", "500k", "-c:a", "aac_at", "-shortest", vid], check=True)
    aud = os.path.join(work, "voix.wav")
    subprocess.run([FFMPEG, "-nostdin", "-v", "error", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono:d=4", "-f", "lavfi", "-i", "sine=frequency=500:duration=4:sample_rate=44100",
                    "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono:d=4", "-filter_complex", "[0][1][2]concat=n=3:v=0:a=1", aud], check=True)

    proc = subprocess.Popen([MCP], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=env)
    n = [0]
    def rpc(method, params=None, notify=False):
        n[0] += 1
        msg = {"jsonrpc": "2.0", "method": method, **({"params": params} if params is not None else {})}
        if not notify: msg["id"] = n[0]
        proc.stdin.write(json.dumps(msg) + "\n"); proc.stdin.flush()
        return None if notify else json.loads(proc.stdout.readline())
    def call(tool, **args):
        r = rpc("tools/call", {"name": tool, "arguments": args})["result"]
        text = "\n".join(c["text"] for c in r["content"] if c["type"] == "text")
        try: return r["isError"], json.loads(text), r
        except Exception: return r["isError"], text, r

    defaults("delete", DOMAIN, "agent.enabled")
    r = rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "essai", "version": "1"}})["result"]
    check(r["serverInfo"]["name"] == "mslice" and "tools" in r["capabilities"], "initialize : serveur « mslice »")
    rpc("notifications/initialized", notify=True)
    tools = [t["name"] for t in rpc("tools/list")["result"]["tools"]]
    check(len(tools) >= 15 and "export" in tools and "get_frame" in tools, f"tools/list : {len(tools)} outils")

    err, txt, _ = call("get_state")
    check(err and "off" in str(txt), "désactivé par défaut : l'agent est refusé avec une explication")
    defaults("write", DOMAIN, "agent.enabled", "-bool", "true")

    err, st, _ = call("get_state")
    check(not err and st["app_open"] is False, "get_state : appli fermée")
    err, p, _ = call("probe_media", path=vid, keyframes=True)
    check(not err and abs(p["duration"] - 30) < 0.5 and p["keyframes"]["count"] >= 10, f"probe_media : {p['summary'] if not err else p}, {p.get('keyframes')}")
    err, s, _ = call("set_segments", path=vid, segments=[{"start": "0:05", "end": "0:10"}, {"start": 20, "end": 28.5, "name": "fin"}, {"start": 8, "end": 12}])
    check(not err and s["count"] == 2 and s["segments"][0]["end"] == 12, f"set_segments : chevauchements fusionnés ({s['count']} morceaux)")
    err, s, _ = call("add_segment", path=vid, start="0:15", end="0:17")
    check(not err and s["count"] == 3, "add_segment")
    err, s, _ = call("remove_segment", path=vid, index=3)
    check(not err and s["count"] == 2, "remove_segment")
    err, g, _ = call("get_segments", path=vid)
    check(not err and g["count"] == 2 and g["live_in_app"] is False, "get_segments : lus depuis la session enregistrée")

    err, pv, _ = call("preview_export", path=vid)
    check(not err and pv["dry_run"] and len(pv["will_create"]) == 2 and not os.path.exists(pv["will_create"][0]["path"]), "preview_export : ne crée rien")
    err, ex, _ = call("export", path=vid)
    check(not err and len(ex["created"]) == 2 and all(os.path.getsize(c["path"]) > 1000 for c in ex["created"]), f"export copie directe : {[os.path.basename(c['path']) for c in ex['created']] if not err else ex}")
    err, ex2, _ = call("export", path=vid)
    names = {os.path.basename(c["path"]) for c in ex["created"]} | {os.path.basename(c["path"]) for c in ex2["created"]}
    check(not err and len(names) == 4, "second export : aucun fichier écrasé (4 fichiers distincts)")
    err, ex3, _ = call("export", path=vid, merge=True, merge_name="fusion")
    check(not err and len(ex3["created"]) == 1, "export fusionné")
    if not err:
        d = subprocess.run([os.path.join(APP, "Contents/Helpers/ffprobe"), "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", ex3["created"][0]["path"]], capture_output=True, text=True).stdout.strip()
        check(abs(float(d) - 11) < 1.5, f"durée fusionnée ≈ 11 s (9 s demandées, début calé sur l'image clé) : {float(d):.1f} s")
    err, ex4, _ = call("export", path=vid, passthrough=False, format="mp3", merge=True, merge_name="son")
    check(not err and ex4["created"][0]["path"].endswith(".mp3"), "export audio recompressé (mp3)")

    # garde-fous
    err, t, _ = call("export", path=vid, folder="/tmp/ailleurs")
    check(err and "not allowed" in str(t), "dossier hors du fichier source refusé")
    err, t, _ = call("export", path=vid, folder="../")
    check(err and "not allowed" in str(t), "« ../ » refusé")
    err, t, _ = call("export", path=vid, folder="sous-dossier")
    check(not err and os.path.isdir(os.path.join(work, "sous-dossier")) and ex4 is not None, "sous-dossier du fichier source accepté (créé)")
    err, t, _ = call("export", path=vid, format="flac")
    check(err and "not possible" in str(t), "copie directe impossible : message clair")
    err, t, _ = call("probe_media", path=os.path.join(work, "inconnu.mp4"))
    check(err and "not found" in str(t).lower(), "fichier absent : erreur claire")
    check(all(f.endswith((".mp4", ".mp3", ".wav")) for f in os.listdir(work) if os.path.isfile(os.path.join(work, f))), "aucun fichier hors export dans le dossier")
    check(os.path.exists(vid) and os.path.exists(aud), "originaux intacts")

    # élagage
    err, e, _ = call("trim_edges", path=vid, head=3, tail=2)
    check(not err and e["segments"][0]["start"] == 3 and abs(e["segments"][0]["end"] - 28) < 0.6, "trim_edges")
    err, sl, _ = call("find_silences", path=aud)
    check(not err and abs(sl["leading_silence_until"] - 4) < 0.3 and abs(sl["trailing_silence_from"] - 8) < 0.3, f"find_silences : début jusqu'à {sl.get('leading_silence_until')}, fin dès {sl.get('trailing_silence_from')}")
    err, ts, _ = call("trim_silences", path=aud)
    check(not err and ts["changed"] and 3.5 < ts["segments"][0]["start"] < 4.0 and 8.0 < ts["segments"][0]["end"] < 8.5, f"trim_silences : garde {ts['segments'][0]['start_text']} → {ts['segments'][0]['end_text']}")
    err, sp, _ = call("split_on_silence", path=aud, min_silence=1.0)
    check(not err and sp["count"] == 1, "split_on_silence")
    err, b, _ = call("batch_trim", paths=[vid, aud], head=1, tail=1)
    check(not err and b["trimmed"] == 2, f"batch_trim : {b['trimmed']}/2")
    err, fr, raw = call("get_frame", path=vid, time="0:07", width=320)
    check(not err and any(c["type"] == "image" and len(c["data"]) > 500 for c in raw["content"]), "get_frame : image PNG renvoyée")
    err, t, _ = call("seek", time=3)
    check(err and "not open" in str(t), "seek sans appli : refus explicite")
finally:
    if proc:
        proc.stdin.close(); proc.wait(timeout=5)
    if prev_val is None: defaults("delete", DOMAIN, "agent.enabled")
    else: defaults("write", DOMAIN, "agent.enabled", "-bool", "true" if prev_val in ("1", "true") else "false")
    shutil.rmtree(work, ignore_errors=True)
print("RÉSULTAT :", "tout passe" if fails == 0 else f"{fails} échec(s)")
sys.exit(1 if fails else 0)
