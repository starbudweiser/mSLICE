#!/usr/bin/env python3
"""Essai de bout en bout de mslice-mcp, SANS l'appli ouverte (mode autonome) : protocole MCP, garde-fous, découpe, fusion, silences.
Usage : scripts/mcp_e2e.py [chemin/mslice-mcp]   (défaut : « mSLICE DEV.app »). Active puis rétablit le réglage « Autoriser un agent » de l'édition DEV."""
import json, os, plistlib, struct, subprocess, sys, tempfile, shutil, time, datetime

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
idxdir = os.path.join(work, "index")
env = dict(os.environ, MSLICE_SESSION_DIR=os.path.join(work, "sessions"), MSLICE_AGENT_SOCKET=os.path.join(work, "none.sock"), MSLICE_INDEX_DIR=idxdir, MSLICE_MODEL_DIR=os.path.join(work, "models"))
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
    check(len(tools) >= 21 and "list_subjects" in tools and "name_subject" in tools and "export" in tools and "get_frame" in tools and "analyze_media" in tools and "find_scenes" in tools and "list_dialogue" in tools and "send_dialogue" in tools, f"tools/list : {len(tools)} outils")

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

    # entrées hostiles
    os.symlink("/tmp", os.path.join(work, "evasion"))
    err, t, _ = call("export", path=vid, folder="evasion")
    check(err and "not allowed" in str(t), "lien symbolique vers /tmp : dossier refusé")
    err, t, _ = call("export", path=vid, folder="evasion/nouveau")
    check(err and "not allowed" in str(t), "sous-dossier d'un lien symbolique : refusé")
    check(not os.path.exists("/tmp/nouveau"), "rien n'a été créé hors du dossier autorisé")
    err, t, _ = call("probe_media", path=vid + "\nfile '/etc/passwd'")
    check(err and ("control" in str(t) or "not found" in str(t).lower()), "chemin avec saut de ligne refusé")
    err, t, _ = call("remove_segment", path=vid, index=1e30)
    check(err and "between" in str(t), "index géant : erreur propre (pas de plantage)")
    err, t, _ = call("set_segments", path=vid, segments=[{"start": "nan", "end": 5}, {"start": "inf", "end": "-inf"}])
    check(err, "NaN / infini : refusés proprement")
    err, t, _ = call("set_segments", path=vid, segments=[{"start": 1, "end": 4, "name": "../../evil\n/x"}])
    err2, ex5, _ = call("export", path=vid)
    check(not err and not err2 and all(os.path.dirname(c["path"]) == work for c in ex5["created"]), "nom de morceau malveillant : le fichier reste dans le dossier source")
    check(proc.poll() is None, "le serveur MCP a survécu aux entrées hostiles")

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

    # ---- analyse et recherche de scènes (analyze_media, find_scenes) ----
    cuts = os.path.join(work, "plans.mp4")        # trois plans de 4 s, coupures franches à 4 s et 8 s
    subprocess.run([FFMPEG, "-nostdin", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=25:duration=4", "-f", "lavfi", "-i", "color=c=navy:s=320x180:r=25:d=4",
                    "-f", "lavfi", "-i", "testsrc=size=320x180:rate=25:duration=4", "-f", "lavfi", "-i", "sine=frequency=440:duration=12",
                    "-filter_complex", "[0:v][1:v][2:v]concat=n=3:v=1:a=0[v]", "-map", "[v]", "-map", "3:a", "-c:v", "h264_videotoolbox", "-b:v", "400k", "-c:a", "aac_at", "-shortest", cuts], check=True)
    err, an, _ = call("analyze_media", path=cuts)
    check(not err and an.get("shots") == 3 and an["has_video"] and an["has_audio"] and an["analyzed_now"] is True and isinstance(an["scenes"], list) and isinstance(an["sounds"], list), f"analyze_media : {an.get('shots')} plans (3 attendus), {an.get('analysis_seconds')} s" if not err else f"analyze_media : {an}")
    err, an2, _ = call("analyze_media", path=cuts)
    check(not err and an2["analyzed_now"] is False and an2["shots"] == 3, "analyze_media : résultat gardé, relu sans recalcul")
    err, t, _ = call("analyze_media", path=os.path.join(work, "inconnu.mp4"))
    check(err and "not found" in str(t).lower(), "analyze_media : fichier absent, erreur claire")
    err, t, _ = call("analyze_media", path=vid + "\nx")
    check(err, "analyze_media : chemin avec saut de ligne refusé")
    err, an3, _ = call("analyze_media", path=aud)
    check(not err and an3["has_audio"] and not an3["has_video"] and "shots" not in an3, "analyze_media : fichier audio seul (sons seulement)")
    # index synthétique : résultats déterministes pour les combinaisons ET / SAUF (feu 10-16 s, personnes 3-27 s sauf 20-21 s, musique 22-30 s, rire 18-21 s ; coupures à 8, 15 et 24 s)
    err, pm, _ = call("probe_media", path=vid)
    files = [f for f in os.listdir(idxdir) if f.endswith(".msidx")]
    base_key = None
    err, _a, _ = call("analyze_media", path=vid)
    files2 = [f for f in os.listdir(idxdir) if f.endswith(".msidx")]
    vid_idx = [f for f in files2 if f not in files][0]
    dur = pm["duration"]
    sc_off, sc_lab, sc_conf = [0], [], []
    for k in range(int(dur / 0.5)):
        t0 = k * 0.5
        if 10 <= t0 < 16: sc_lab.append(0); sc_conf.append(230)
        if 3 <= t0 < 27 and not (20 <= t0 < 21): sc_lab.append(1); sc_conf.append(200)
        sc_off.append(len(sc_lab))
    so_off, so_lab, so_conf, so_start = [0], [], [], []
    for k in range(int(dur / 0.5) - 2):
        start = k * 0.5; centre = start + 0.75
        so_start.append(start)
        if 22 <= centre < 30: so_lab.append(0); so_conf.append(220)
        if 18 <= centre < 21: so_lab.append(1); so_conf.append(200)
        so_off.append(len(so_lab))
    stored = {"version": 1, "duration": dur, "created": datetime.datetime.now(), "seconds": 1.0, "hasVideo": True, "hasAudio": True,
              "cuts": struct.pack("<3d", 8.0, 15.0, 24.0), "sceneStep": 0.5, "sceneLabels": ["fire", "people"],
              "sceneOffsets": struct.pack("<%di" % len(sc_off), *sc_off), "sceneLabelIdx": struct.pack("<%dH" % len(sc_lab), *sc_lab), "sceneConf": bytes(sc_conf),
              "soundWindow": 1.5, "soundHop": 0.5, "soundLabels": ["music", "laughter"], "soundStarts": struct.pack("<%df" % len(so_start), *so_start),
              "soundOffsets": struct.pack("<%di" % len(so_off), *so_off), "soundLabelIdx": struct.pack("<%dH" % len(so_lab), *so_lab), "soundConf": bytes(so_conf)}
    with open(os.path.join(idxdir, vid_idx), "wb") as fh: plistlib.dump(stored, fh, fmt=plistlib.FMT_BINARY)
    err, an4, _ = call("analyze_media", path=vid)
    ids = {r["id"]: r for r in an4["scenes"] + an4["sounds"]} if not err else {}
    check(not err and an4["analyzed_now"] is False and an4["shots"] == 4 and "scene:fire" in ids and "sound:music" in ids and "sound:laugh" in ids, f"analyze_media : index synthétique relu ({sorted(ids)})")
    err, fs, _ = call("find_scenes", path=vid, include=["scene:fire"], whole_shots=False)
    check(not err and fs["passages_kept"] == 1 and abs(fs["passages"][0]["start"] - 9.7) < 0.05 and abs(fs["passages"][0]["end"] - 16.3) < 0.05 and fs.get("applied") is None, f"find_scenes feu, marge 0,3 s : {[(p['start'], p['end']) for p in fs['passages']]}" if not err else f"find_scenes : {fs}")
    err, fs, _ = call("find_scenes", path=vid, include=["scene:fire"])
    check(not err and fs["passages"][0]["start"] == 8 and fs["passages"][0]["end"] == 24, f"find_scenes feu, plans entiers : calé sur les coupures {fs['passages'][0]['start']} → {fs['passages'][0]['end']}")
    err, fs, _ = call("find_scenes", path=vid, include=["scene:people", "scene:fire"], whole_shots=False)
    check(not err and fs["passages_kept"] == 1 and abs(fs["passages"][0]["start"] - 9.7) < 0.05, "find_scenes personnes ET feu : intersection")
    err, fs, _ = call("find_scenes", path=vid, include=["scene:people"], exclude=["sound:music"])
    check(not err and fs["passages"][0].get("excluded_by") and fs["passages_kept"] == 0 and fs["kept_seconds"] == 0, f"find_scenes personnes SAUF musique : passage écarté ({fs['passages'][0].get('excluded_by') if not err else fs})")
    err, fs, _ = call("find_scenes", path=vid, include=["scene:people"], exclude=["scene:fire"], whole_shots=False)
    check(not err and fs["passages_kept"] == 0 and fs["passages"][0].get("excluded_by"), "find_scenes SAUF feu : le passage des personnes qui contient le feu est écarté")
    err, fs, _ = call("find_scenes", path=vid, include=["scene:fire"], whole_shots=False, apply="set")
    err2, g, _ = call("get_segments", path=vid)
    check(not err and fs["applied"] == "set" and not err2 and g["count"] == 1 and abs(g["segments"][0]["start"] - 9.7) < 0.05, "find_scenes apply=set : les morceaux sont posés")
    err, fs, _ = call("find_scenes", path=vid, include=["sound:laugh"], whole_shots=False, apply="add")
    err2, g, _ = call("get_segments", path=vid)
    check(not err and fs["applied"] == "add" and not err2 and g["count"] == 2 and g["segments"][0]["start"] < g["segments"][1]["start"], f"find_scenes apply=add : ajouté aux morceaux existants ({g['count']} morceaux)")
    err, fs, _ = call("find_scenes", path=vid, include=["sound:music"], exclude=["scene:fire"], whole_shots=False, apply="add")
    err2, g, _ = call("get_segments", path=vid)
    check(not err and g["count"] >= 2, "find_scenes : aucun morceau supprimé par un ajout (jamais de suppression de morceau existant)")
    err, fs, _ = call("find_scenes", path=vid, include=["label:dragon"])
    check(not err and fs["passages_found"] == 0 and fs.get("notes"), "find_scenes label inconnu : aucun passage, avec une note")
    err, t, _ = call("find_scenes", path=vid, include=["scene:dragon"])
    check(err and "Unknown scene family" in str(t) and "fire" in str(t), "find_scenes famille inconnue : erreur avec la liste des familles")
    err, t, _ = call("find_scenes", path=vid, include=["n'importe quoi"])
    check(err and "Bad criterion" in str(t), "find_scenes critère mal formé : erreur claire")
    err, t, _ = call("find_scenes", path=vid, include=[])
    check(err and "include" in str(t), "find_scenes sans critère : refusé")
    err, t, _ = call("find_scenes", path=vid, include=["scene:fire"], apply="delete")
    check(err and "apply" in str(t), "find_scenes apply invalide : refusé")
    err, t, _ = call("find_scenes", path=vid, include=["scene:" + "x" * 5000])
    check(err and proc.poll() is None, "find_scenes critère géant : erreur propre, serveur vivant")
    err, t, _ = call("find_scenes", path=aud, include=["scene:fire"])
    check(err and "no video" in str(t), "find_scenes critère d'image sur un fichier audio : refusé clairement")
    err, t, _ = call("find_scenes", path=vid, include=["sound:laugh"], min_sound_score="nan")
    check(proc.poll() is None, "find_scenes : seuil NaN sans plantage")
    err, t, _ = call("find_scenes", path=vid, include=["scene:fire"], min_length=1e30, whole_shots=False)
    check(not err and proc.poll() is None and t["passages_found"] == 0, "find_scenes : durée minimale géante bornée (aucun passage, pas de plantage)")
    # ---- personnages : index de visages synthétique ; dossier de modèles vide, donc le modèle optionnel n'est pas installé ----
    err, t, _ = call("list_subjects", path=vid)
    check(err and "analyze_media" in str(t), "list_subjects sans reconnaissance : erreur qui dit quoi faire")
    err, an5, _ = call("analyze_media", path=vid, characters=True)
    check(not err and an5.get("characters", {}).get("status") == "model_not_installed" and an5["analyzed_now"] is False, "analyze_media characters=true sans modèle : indiqué clairement, aucun téléchargement, l'analyse reste valable")
    err, t, _ = call("find_scenes", path=vid, include=["person:0"])
    check(err and "recognis" in str(t).lower(), "find_scenes person: sans reconnaissance : erreur claire")
    faces_file = os.path.join(idxdir, vid_idx.replace(".msidx", ".msfaces"))
    def make_faces(names=None):
        # groupe 0 : visages aux secondes 4-7 (suivi 0) et 9-12 (suivi 1) ; groupe 1 : secondes 16-19 (suivi 2)
        rows = [(float(s), 0, 0 if s < 8 else 1) for s in (4, 5, 6, 7, 9, 10, 11, 12)] + [(float(s), 1, 2) for s in (16, 17, 18, 19)]
        n = len(rows); names = names or {}
        emb = b"".join(bytes([100 if k == g else 0 for k in range(512)]) for _, g, _ in rows)
        keys = sorted(names)
        return {"version": 1, "duration": dur, "created": datetime.datetime.now(), "seconds": 1.0, "modelSHA": "2c1d331d88b4b7544a5835b810e6ca7203fcfc7d04b0be614787b4012331277b", "step": 1.0,
                "t": struct.pack("<%df" % n, *[r[0] for r in rows]), "box": struct.pack("<%df" % (4 * n), *([0.4, 0.3, 0.2, 0.3] * n)), "px": struct.pack("<%df" % n, *([120.0] * n)),
                "track": struct.pack("<%di" % n, *[r[2] for r in rows]), "group": struct.pack("<%di" % n, *[r[1] for r in rows]), "emb": emb, "embScale": struct.pack("<%df" % n, *([0.01] * n)),
                "nameKeys": struct.pack("<%di" % len(keys), *keys), "nameValues": [names[k] for k in keys], "hidden": b"", "nextGroup": 2}
    def write_faces(d):
        with open(faces_file, "wb") as fh: plistlib.dump(d, fh, fmt=plistlib.FMT_BINARY)
    def read_faces():
        with open(faces_file, "rb") as fh: return plistlib.load(fh)
    write_faces(make_faces())
    err, ls, _ = call("list_subjects", path=vid)
    s0 = ls["subjects"][0] if not err and ls.get("subjects") else {}
    check(not err and len(ls["subjects"]) == 2 and s0.get("id") == "person:0" and s0.get("named") is False and abs(s0.get("seconds", 0) - 8) < 0.1 and s0.get("appearances") == 1 and abs(ls["subjects"][1]["seconds"] - 4) < 0.1, f"list_subjects : deux personnages, le plus présent d'abord ({s0})")
    err, fs, _ = call("find_scenes", path=vid, include=["person:0"], whole_shots=False)
    check(not err and fs["passages_kept"] == 1 and abs(fs["passages"][0]["start"] - 3.2) < 0.05 and abs(fs["passages"][0]["end"] - 12.8) < 0.05, f"find_scenes person:0 : visages réunis (trou de 1 s comblé) {fs['passages'][0] if not err else fs}")
    err, fs, _ = call("find_scenes", path=vid, include=["person:0"])
    check(not err and fs["passages"][0]["start"] == 0 and fs["passages"][0]["end"] == 15, "find_scenes person:0 en plans entiers : calé sur les coupures")
    err, fs, _ = call("find_scenes", path=vid, include=["person:0", "scene:fire"], whole_shots=False)
    check(not err and fs["passages_kept"] == 1 and abs(fs["passages"][0]["start"] - 9.7) < 0.05 and abs(fs["passages"][0]["end"] - 12.8) < 0.05, "find_scenes personnage ET feu : intersection")
    err, fs, _ = call("find_scenes", path=vid, include=["scene:people"], exclude=["person:1"], whole_shots=False)
    check(not err and fs["passages"][0].get("excluded_by") and fs["passages_kept"] == 0, f"find_scenes personnes SAUF un personnage : le passage qui le contient est écarté et signalé ({fs['passages'][0] if not err else fs})")
    err, nm, _ = call("name_subject", path=vid, subject="person:0", name="Hero")
    check(not err and nm.get("id") == "person:0" and nm.get("name") == "Hero" and "Hero" in read_faces()["nameValues"], "name_subject : nom enregistré dans le fichier des visages")
    err, ls, _ = call("list_subjects", path=vid)
    check(not err and ls["subjects"][0]["name"] == "Hero" and ls["subjects"][0]["named"] is True, "list_subjects : le nom est repris")
    err, fs, _ = call("find_scenes", path=vid, include=["person:hero"], whole_shots=False)
    check(not err and fs["include"] == ["person:0"] and fs["passages_kept"] == 1, "find_scenes : un personnage se désigne aussi par son nom (sans tenir compte des majuscules)")
    err, nm, _ = call("name_subject", path=vid, subject="Hero", name="Hé\nro\u0007" + "x" * 80)
    check(not err and "\n" not in nm["name"] and "\u0007" not in nm["name"] and len(nm["name"]) <= 40, "name_subject : caractères de contrôle retirés, 40 caractères au plus")
    err, t, _ = call("name_subject", path=vid, subject="person:9", name="Fantôme")
    check(err and "person:" in str(t), "name_subject : personnage inconnu, erreur qui liste ceux qui existent")
    err, nm, _ = call("name_subject", path=vid, subject="person:0", name="")
    check(not err and nm.get("named") is False and not read_faces()["nameValues"], "name_subject : nom vide, le personnage redevient anonyme")
    call("name_subject", path=vid, subject="person:0", name="Twin"); call("name_subject", path=vid, subject="person:1", name="Twin")
    err, t, _ = call("find_scenes", path=vid, include=["person:twin"])
    check(err and "ambiguous" in str(t).lower(), "find_scenes : deux personnages de même nom, ambiguïté signalée")
    err, t, _ = call("find_scenes", path=vid, include=["person:" + "x" * 5000])
    check(err and proc.poll() is None, "find_scenes : nom de personnage géant, erreur propre")
    err, t, _ = call("find_scenes", path=aud, include=["person:0"])
    check(err and proc.poll() is None, "find_scenes : critère personnage sur un fichier audio refusé")
    raw = open(faces_file, "rb").read()
    with open(faces_file, "wb") as fh: fh.write(raw[:len(raw) // 2])
    err, t, _ = call("list_subjects", path=vid)
    check(err and proc.poll() is None, "fichier des visages tronqué : traité comme absent, serveur vivant")
    bad = make_faces(); bad["group"] = struct.pack("<12i", *([99] * 12))
    write_faces(bad)
    err, t, _ = call("list_subjects", path=vid)
    check(err and proc.poll() is None, "fichier des visages incohérent (groupe hors table) : refusé")
    os.remove(faces_file)
    check(all(f.endswith((".mp4", ".mp3", ".wav")) for f in os.listdir(work) if os.path.isfile(os.path.join(work, f))), "analyse : aucun fichier ajouté hors dossier d'index")
    check(os.path.exists(cuts) and os.path.exists(vid), "analyse : originaux intacts")
finally:
    if proc:
        proc.stdin.close(); proc.wait(timeout=5)
    if prev_val is None: defaults("delete", DOMAIN, "agent.enabled")
    else: defaults("write", DOMAIN, "agent.enabled", "-bool", "true" if prev_val in ("1", "true") else "false")
    shutil.rmtree(work, ignore_errors=True)
print("RÉSULTAT :", "tout passe" if fails == 0 else f"{fails} échec(s)")
sys.exit(1 if fails else 0)
