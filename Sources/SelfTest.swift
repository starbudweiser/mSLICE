// mSLICE — essais sans fenêtre : `mSLICE --selftest <fichier>` sonde, coupe, fusionne, recompresse, puis vérifie les durées avec ffprobe.
import AppKit
import AVFoundation
import CoreMedia
import Darwin
import Foundation

@MainActor
enum SelfTest {
    static func run(path: String) async -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ msg: String) { print((ok ? "OK     " : "ÉCHEC  ") + msg); if !ok { failures += 1 } }
        let src = URL(fileURLWithPath: path)
        guard let info = Probe.read(src) else { print("ÉCHEC  sonde de \(path)"); return 1 }
        print("Fichier : \(info.summary)")
        let t0 = Date()
        let kf = Probe.keyframes(info)
        check(!kf.isEmpty, "images clés : \(kf.count) en \(String(format: "%.1f", Date().timeIntervalSince(t0))) s (première \(kf.first ?? -1))")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-selftest-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = src.deletingPathExtension().lastPathComponent

        func export(_ segs: [Segment], _ opts: ExportOptions) async -> (ExportRun, [OutputItem], Double) {
            var o = opts; o.folder = dir.path
            let outs = Planner.outputs(info: info, segments: segs, opts: o, keyframes: kf)
            let run = await MainActor.run { ExportRun() }
            let t = Date()
            await MainActor.run { run.start(info: info, outputs: outs, opts: o, keyframes: kf) }
            while !(await MainActor.run { run.finished }) { try? await Task.sleep(nanoseconds: 50_000_000) }
            return (run, outs, Date().timeIntervalSince(t))
        }
        func dur(_ u: URL) -> Double? { Probe.read(u)?.duration }
        func seg(_ a: Double, _ b: Double) -> Segment { Segment(start: a, end: b) }
        let d = info.duration
        let segs = [seg(15, 60), seg(min(120, d - 50), min(150, d - 20)), seg(min(300, d - 40), min(330, d - 10))]

        // 1. copie directe, un fichier par morceau
        var o = ExportOptions(); o.passthrough = true; o.merge = false
        var (run, outs, secs) = await export(segs, o)
        check(run.error == nil, "copie directe séparée : \(outs.count) fichiers en \(String(format: "%.1f", secs)) s \(run.error ?? "")")
        for (i, it) in outs.enumerated() {
            let want = it.segments[0].end - it.segments[0].start
            let got = dur(it.url) ?? -1
            check(abs(got - want) < 0.35, "  \(it.url.lastPathComponent) : \(String(format: "%.2f", got)) s (attendu \(String(format: "%.2f", want)), début réel \(Fmt.time(it.segments[0].start)) pour une entrée à \(Fmt.time(segs[i].start)))")
        }
        check(outs.map { $0.url.lastPathComponent } == (1 ... 3).map { "\(base)_0\($0).\(info.ext)" }, "  numérotation _01 à _03")

        // 2. nouvel export : la numérotation continue, rien n'est écrasé
        (run, outs, secs) = await export(segs, o)
        check(outs.map { $0.url.lastPathComponent } == (4 ... 6).map { "\(base)_0\($0).\(info.ext)" } && run.error == nil, "numérotation continue : \(outs.first?.url.lastPathComponent ?? "?") …")

        // 3. fusion en copie directe
        o.merge = true
        (run, outs, secs) = await export(segs, o)
        let want = outs[0].expected, got = dur(outs[0].url) ?? -1
        check(run.error == nil && abs(got - want) < 0.6, "fusion copie directe : \(outs[0].url.lastPathComponent) \(String(format: "%.2f", got)) s (attendu \(String(format: "%.2f", want))) en \(String(format: "%.1f", secs)) s \(run.error ?? "")")

        // 4. audio : mp3 (LAME), wav, m4a en copie directe
        let a = [seg(15, 30)]
        for (f, pass) in [(OutFormat.mp3, false), (.wav, false), (.opus, false), (.m4a, true)] {
            var oa = ExportOptions(); oa.passthrough = pass; oa.format = f
            if pass && !Planner.canCopy(info: info, to: f) { print("INFO   \(f.rawValue) en copie directe ignoré (codec audio \(info.audio?.codec ?? "?"))"); continue }
            let (r, os, s) = await export(a, oa)
            let g = dur(os[0].url) ?? -1
            check(r.error == nil && abs(g - 15) < 0.25, "audio \(f.rawValue)\(pass ? " (copie directe)" : "") : \(String(format: "%.2f", g)) s en \(String(format: "%.1f", s)) s \(r.error ?? "")")
        }

        // 4b. fusion audio en copie directe (m4a) de deux morceaux pris dans la vidéo
        if Planner.canCopy(info: info, to: .m4a) && !info.isAudioOnly {
            var ob = ExportOptions(); ob.passthrough = true; ob.format = .m4a; ob.merge = true
            let (r, os, s) = await export([seg(15, 25), seg(60, 70)], ob)
            let g = dur(os[0].url) ?? -1
            check(r.error == nil && abs(g - 20) < 0.3, "fusion audio m4a (copie directe) : \(String(format: "%.2f", g)) s en \(String(format: "%.1f", s)) s \(r.error ?? "")")
        }

        // 4c. « voix seules » : piste nettoyée fabriquée, puis exports (image copiée + son nettoyé, audio seul, fusion)
        if info.audio != nil, CleanVoice.available {
            setenv("MSLICE_CLEAN_DIR", dir.appendingPathComponent("clean").path, 1)
            let tc = Date()
            let built = await CleanVoice.build(info, job: AnalysisJob(), slot: false) { _ in }
            check(built && CleanVoice.exists(info), "piste « voix seules » : fabriquée en \(String(format: "%.1f", Date().timeIntervalSince(tc))) s pour \(Fmt.time(d, decimals: false))")
            if built {
                // lecteur : la piste nettoyée remplace le son, la position et la lecture sont conservées, retour au son d'origine possible
                let pm = PlayerModel()
                await pm.load(info)
                pm.seek(3)
                await pm.setVoiceOnly(true, info: info)
                let comp = pm.player.currentItem?.asset as? AVMutableComposition
                let aTracks = (try? await comp?.loadTracks(withMediaType: .audio))?.count ?? 0, vTracks = (try? await comp?.loadTracks(withMediaType: .video))?.count ?? 0
                check(pm.voiceOnly && aTracks == 1 && vTracks == (info.isAudioOnly ? 0 : 1) && abs(pm.player.currentTime().seconds - 3) < 0.2, "lecteur « voix seules » : \(aTracks) piste audio, \(vTracks) image, position \(String(format: "%.2f", pm.player.currentTime().seconds)) s")
                pm.play(); try? await Task.sleep(nanoseconds: 1_200_000_000)
                let moved = pm.player.currentTime().seconds
                pm.pause()
                check(moved > 3.5, "lecteur « voix seules » : la lecture avance (\(String(format: "%.2f", moved)) s)")
                await pm.setVoiceOnly(false, info: info)
                check(!pm.voiceOnly && !(pm.player.currentItem?.asset is AVMutableComposition), "lecteur : retour au son d'origine")
                let vseg = [seg(5, min(15, d - 1))], vlen = vseg[0].end - vseg[0].start
                var ov = ExportOptions(); ov.voiceOnly = true; ov.passthrough = true
                let (r1, o1, _) = await export(vseg, ov)
                if let u = o1.first?.url, let oi = Probe.read(u) {
                    let sameV = oi.isAudioOnly == info.isAudioOnly && oi.video?.codec == info.video?.codec
                    check(r1.error == nil && abs(oi.duration - (o1.first?.expected ?? vlen)) < 0.5 && oi.audio?.channels == 1 && sameV, "voix seules, copie directe : \(String(format: "%.2f", oi.duration)) s, audio \(oi.audio?.codec ?? "?") \(oi.audio?.channels ?? 0) canal, image \(oi.video?.codec ?? "aucune") \(r1.error ?? "")")
                } else { check(false, "voix seules, copie directe : fichier absent \(r1.error ?? "")") }
                var oa = ExportOptions(); oa.voiceOnly = true; oa.passthrough = false; oa.format = .mp3
                let (r2, o2, _) = await export(vseg, oa)
                let g2 = o2.first.flatMap { Probe.read($0.url) }?.duration ?? -1
                check(r2.error == nil && abs(g2 - vlen) < 0.3, "voix seules, mp3 : \(String(format: "%.2f", g2)) s \(r2.error ?? "")")
                var om = ExportOptions(); om.voiceOnly = true; om.passthrough = true; om.merge = true
                let mseg = [seg(2, 8), seg(min(20, d - 10), min(26, d - 4))]
                let (r3, o3, _) = await export(mseg, om)
                let g3 = o3.first.flatMap { Probe.read($0.url) }
                let want3 = o3.first?.expected ?? 0
                check(r3.error == nil && abs((g3?.duration ?? -1) - want3) < 0.8 && g3?.audio?.channels == 1, "voix seules, fusion : \(String(format: "%.2f", g3?.duration ?? -1)) s (attendu \(String(format: "%.2f", want3))) \(r3.error ?? "")")
            }
        }

        // 5. recompression H.264 / H.265 (VideoToolbox) sur 10 s, puis fusion recompressée
        if !info.isAudioOnly {
            for c in [VideoCodec.h264, .hevc] {
                var oc = ExportOptions(); oc.passthrough = false; oc.format = .mp4; oc.codec = c; oc.quality = .medium
                let (r, os, s) = await export([seg(20, 30)], oc)
                let g = dur(os[0].url) ?? -1
                check(r.error == nil && abs(g - 10) < 0.3, "recompression \(c.title) : \(String(format: "%.2f", g)) s en \(String(format: "%.1f", s)) s \(r.error ?? "")")
            }
            var om = ExportOptions(); om.passthrough = false; om.merge = true; om.format = .mp4
            let (r, os, s) = await export([seg(20, 25), seg(60, 65)], om)
            let g = dur(os[0].url) ?? -1
            check(r.error == nil && abs(g - 10) < 0.4, "fusion recompressée : \(String(format: "%.2f", g)) s en \(String(format: "%.1f", s)) s \(r.error ?? "")")
            let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.filter { $0.hasPrefix(".mslice-") } ?? []
            check(leftovers.isEmpty, "aucun fichier temporaire restant")
        }

        // 6. annulation : rien ne reste
        var oc = ExportOptions(); oc.passthrough = false; oc.format = .mp4
        var cancelOpts = oc; cancelOpts.folder = dir.path
        let outsC = Planner.outputs(info: info, segments: [seg(0, min(600, d))], opts: cancelOpts, keyframes: kf)
        let runC = await MainActor.run { ExportRun() }
        await MainActor.run { runC.start(info: info, outputs: outsC, opts: cancelOpts, keyframes: kf) }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        runC.cancel.cancel()
        while !(await MainActor.run { runC.finished }) { try? await Task.sleep(nanoseconds: 50_000_000) }
        check(await MainActor.run { runC.cancelled } && !FileManager.default.fileExists(atPath: outsC[0].url.path), "annulation : export interrompu, fichier partiel effacé")

        print(failures == 0 ? "TOUT EST OK" : "\(failures) échec(s)")
        return failures == 0 ? 0 : 1
    }
}

/// Essais de la logique I / O et des morceaux (sans fenêtre ni lecture).
@MainActor
enum EditorTest {
    static func run(path: String) -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ msg: String) { print((ok ? "OK     " : "ÉCHEC  ") + msg); if !ok { failures += 1 } }
        guard let info = Probe.read(URL(fileURLWithPath: path)) else { print("ÉCHEC  sonde"); return 1 }
        let d = Doc(info: info); d.segments = []; d.keyframes = Probe.keyframes(info)
        let tmp = SessionStore.key(info)
        defer { try? FileManager.default.removeItem(at: SessionStore.dir.appendingPathComponent(tmp + ".json")) }
        // I puis O : crée un morceau ; l'entrée se cale sur l'image clé précédente (copie directe)
        d.markIn(at: 15, snap: true)
        check(d.pendingIn != nil && abs(d.pendingIn! - Planner.effectiveStart(15, keyframes: d.keyframes, passthrough: true, hasVideo: true)) < 0.001, "I : entrée posée sur l'image clé \(Fmt.time(d.pendingIn ?? -1)) (pour 15 s)")
        d.markOut(at: 60)
        check(d.segments.count == 1 && abs(d.segments[0].end - 60) < 0.001 && d.pendingIn == nil, "O : morceau 1 créé \(Fmt.time(d.segments.first?.start ?? -1)) → \(Fmt.time(d.segments.first?.end ?? -1))")
        // deuxième morceau
        d.markIn(at: 120, snap: false); d.markOut(at: 150)
        check(d.segments.count == 2 && d.segments[1].start == 120, "deuxième morceau 2:00.0 → 2:30.0")
        // I dans un morceau : déplace son début
        d.markIn(at: 130, snap: false)
        check(d.segments[1].start == 130 && d.segments.count == 2, "I dans le morceau 2 : début déplacé à 2:10.0")
        // O dans un morceau : déplace sa fin
        d.markOut(at: 145)
        check(d.segments[1].end == 145, "O dans le morceau 2 : fin déplacée à 2:25.0")
        // chevauchement : le nouveau morceau absorbe ceux qu'il touche, et « annuler » rend les deux
        d.snapshot(); d.addSegment(55, 135)
        check(d.segments.count == 1 && d.segments[0].start == 50 && d.segments[0].end == 145 || (d.segments.count == 1 && d.segments[0].end >= 135), "chevauchement fusionné : \(d.segments.map { "\(Fmt.time($0.start))-\(Fmt.time($0.end))" })")
        d.undo()
        check(d.segments.count == 2, "annuler : retour à \(d.segments.count) morceaux")
        // O seul : de la fin du morceau précédent jusqu'ici
        d.segments = []; d.markOut(at: 30)
        check(d.segments.count == 1 && d.segments[0].start == 0 && d.segments[0].end == 30, "O seul : morceau 0:00.0 → 0:30.0")
        // noms personnalisés : un nom propre prime, la numérotation ne compte que les morceaux automatiques, un doublon reçoit _2
        let tdir = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-nametest-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: tdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tdir) }
        var no = ExportOptions(); no.folder = tdir.path
        let named = [Segment(start: 1, end: 2, name: "Intro"), Segment(start: 3, end: 4), Segment(start: 5, end: 6, name: "Intro"), Segment(start: 7, end: 8), Segment(start: 9, end: 10, name: "a/b:c ")]
        let names = Planner.outputs(info: info, segments: named, opts: no, keyframes: [], base: "Rush").map { $0.url.lastPathComponent }
        check(names == ["Intro.\(info.ext)", "Rush_01.\(info.ext)", "Intro_2.\(info.ext)", "Rush_02.\(info.ext)", "a-b-c.\(info.ext)"], "noms : \(names)")
        no.merge = true
        let merged = Planner.outputs(info: info, segments: named, opts: no, keyframes: [], base: "Rush", mergeName: "Montage final").first?.url.lastPathComponent
        check(merged == "Montage final.\(info.ext)", "fichier fusionné nommé : \(merged ?? "?")")
        let autoMerged = Planner.outputs(info: info, segments: named, opts: no, keyframes: [], base: "Rush").first?.url.lastPathComponent
        check(autoMerged == "Rush_extrait.\(info.ext)", "fichier fusionné automatique : \(autoMerged ?? "?")")
        try? Data().write(to: tdir.appendingPathComponent("Rush_extrait.\(info.ext)"))
        let again = Planner.outputs(info: info, segments: named, opts: no, keyframes: [], base: "Rush").first?.url.lastPathComponent
        check(again == "Rush_extrait_2.\(info.ext)", "nom déjà pris : \(again ?? "?") (rien n'est écrasé)")

        // suppression
        d.deleteSelected()
        check(d.segments.isEmpty, "suppression du morceau sélectionné")
        // poignées : le début ne dépasse pas la fin
        d.addSegment(10, 20)
        d.moveEdge(d.segments[0].id, start: true, to: 25, snap: false)
        check(d.segments[0].start < d.segments[0].end, "poignée d'entrée bornée par la sortie")
        print(failures == 0 ? "TOUT EST OK" : "\(failures) échec(s)")
        return failures == 0 ? 0 : 1
    }
}

/// Mesures de ressources du processus (MSLICE_PERF=1) : empreinte mémoire (phys_footprint) et temps processeur cumulé.
enum Perf {
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
    static func cpuSeconds() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
    }
    nonisolated(unsafe) static var lastCPU = 0.0, lastT = Date()
    static func mark(_ label: String) {
        guard ProcessInfo.processInfo.environment["MSLICE_PERF"] == "1" else { return }
        let c = cpuSeconds(), now = Date()
        let dt = now.timeIntervalSince(lastT)
        // `footprint` (outil système) compte aussi la mémoire graphique (IOSurface) que phys_footprint ne montre pas
        var fp = "?"
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/footprint"); p.arguments = ["\(getpid())"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); p.waitUntilExit()
            if let l = out.split(separator: "\n").first(where: { $0.contains("Footprint:") }) { fp = l.replacingOccurrences(of: "Footprint:", with: "").trimmingCharacters(in: .whitespaces) }
        }
        print(String(format: "PERF   %-34@ mémoire %6.0f Mo (footprint %@)   processeur %5.1f s  (%+.1f s en %.1f s = %.0f %%)", label as NSString, footprintMB(), fp as NSString, c, c - lastCPU, dt, dt > 0 ? (c - lastCPU) / dt * 100 : 0))
        lastCPU = c; lastT = now
    }
}

/// Client MCP minimal pour les essais : lance `mslice-mcp` et dialogue en JSON-RPC par ses tubes.
final class MCPProc: @unchecked Sendable {
    private let p = Process(), inp = Pipe(), outp = Pipe()
    private var buf = Data(), nextID = 0
    init?(env: [String: String]) {
        p.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mslice-mcp")
        guard FileManager.default.isExecutableFile(atPath: p.executableURL!.path) else { return nil }
        p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        p.standardInput = inp; p.standardOutput = outp; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
    }
    func stop() { try? inp.fileHandleForWriting.close(); p.terminate() }
    func rpc(_ method: String, _ params: [String: Any]? = nil) async -> [String: Any]? {
        nextID += 1; let id = nextID
        var m: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]; if let params { m["params"] = params }
        guard var d = try? JSONSerialization.data(withJSONObject: m) else { return nil }
        d.append(10); inp.fileHandleForWriting.write(d)
        return await Task.detached { [self] in
            while true {
                if let i = buf.firstIndex(of: 10) {
                    let line = buf[buf.startIndex ..< i]; buf.removeSubrange(buf.startIndex ... i)
                    if let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], (o["id"] as? Int) == id { return o }
                    continue
                }
                let more = outp.fileHandleForReading.availableData
                if more.isEmpty { return nil }
                buf.append(more)
            }
        }.value
    }
    /// Appelle un outil ; renvoie (erreur, texte JSON décodé ou brut).
    func tool(_ name: String, _ args: [String: Any]) async -> (error: Bool, json: [String: Any]?, text: String) {
        guard let r = await rpc("tools/call", ["name": name, "arguments": args]), let res = r["result"] as? [String: Any] else { return (true, nil, "pas de réponse") }
        let text = ((res["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        return ((res["isError"] as? Bool) ?? false, AgentJSON.parse(text), text)
    }
}

/// Essais de l'interface sans fenêtre visible : chargement, lecture, touches I / O / ← → ↑ ↓ / espace simulées, export complet, captures.
@MainActor
enum UITest {
    static func run(path: String, delegate: AppDelegate) async -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ msg: String) { print((ok ? "OK     " : "ÉCHEC  ") + msg); if !ok { failures += 1 } }
        func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
        let model = AppModel.shared
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-uitest-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: out) }
        let shots = ProcessInfo.processInfo.environment["MSLICE_SHOTS"] ?? ""

        func key(_ chars: String, _ code: UInt16, shift: Bool = false) -> Bool {
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: delegate.window?.windowNumber ?? 0, context: nil,
                                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)
            return e.map { model.handleKey($0) } ?? false
        }

        model.open([URL(fileURLWithPath: path)])
        for _ in 0 ..< 100 { if model.current != nil { break }; await wait(0.2) }
        guard let d = model.current else { print("ÉCHEC  ouverture"); return 1 }
        check(true, "ouverture : \(d.name) \(Fmt.time(d.duration))")
        Perf.mark("après ouverture")
        for _ in 0 ..< 150 { if !d.keyframes.isEmpty, !d.peaks.isEmpty, model.player.player.currentItem?.status == .readyToPlay { break }; await wait(0.2) }
        check(!d.keyframes.isEmpty, "images clés chargées : \(d.keyframes.count)")
        check(!d.peaks.isEmpty, "forme d'onde calculée : \(Fmt.time(d.peaks.duration)) déjà")
        check(model.player.player.currentItem?.status == .readyToPlay, "lecteur prêt (\(model.player.preparing ?? "fichier d'origine"))")
        let tFilm = Date()
        for _ in 0 ..< 400 { if (0 ..< d.strip.count).allSatisfy({ d.strip.image($0) != nil }) { break }; await wait(0.1) }
        let tiles = (0 ..< d.strip.count).filter { d.strip.image($0) != nil }.count
        check(tiles == d.strip.count, "vignettes : \(tiles)/\(d.strip.count) en \(String(format: "%.1f", Date().timeIntervalSince(tFilm))) s (si le cache existe : instantané)")
        Perf.mark("vignettes et forme d'onde prêtes")

        // redimensionnement : la timeline suit la largeur de la fenêtre et reste dans sa carte
        if let w = delegate.window {
            func timelineView() -> TimelineView? {
                func find(_ v: NSView) -> TimelineView? { if let t = v as? TimelineView { return t }; for c in v.subviews { if let t = find(c) { return t } }; return nil }
                return w.contentView.flatMap(find)
            }
            for size in [NSSize(width: 1500, height: 820), NSSize(width: 1180, height: 720), NSSize(width: 1300, height: 760)] {
                w.setFrame(NSRect(origin: .zero, size: size), display: true); w.contentView?.layoutSubtreeIfNeeded(); await wait(0.5)
                if let t = timelineView() {
                    let inWindow = t.convert(t.bounds, to: nil)
                    check(inWindow.maxX <= size.width - Theme.rightWidth + 1 && abs(t.bounds.width - (size.width - Theme.sidebarWidth - Theme.rightWidth - 28 - 24)) < 4,
                          "fenêtre \(Int(size.width))×\(Int(size.height)) : timeline \(Int(t.bounds.width)) px (attendu \(Int(size.width - Theme.sidebarWidth - Theme.rightWidth - 52))), bord droit à \(Int(inWindow.maxX))")
                    if shots == "1" { delegate.snapshot(to: "build/ui-resize-\(Int(size.width)).png") }
                } else { check(false, "timeline introuvable") }
            }
            // bouton de la molette enfoncé + glissement : la timeline zoomée suit la souris (vue qui recule quand on glisse vers la droite)
            if let t = timelineView() {
                func ev(_ type: CGEventType, _ x: CGFloat) -> NSEvent? { CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: 400), mouseButton: .center).flatMap { NSEvent(cgEvent: $0) } }
                let (oldSpan, oldStart) = (d.viewSpan, d.viewStart)
                d.viewSpan = d.duration / 20; d.viewStart = d.duration / 2; d.clampView()
                let s0 = d.viewStart
                if let down = ev(.otherMouseDown, 500), let drag = ev(.otherMouseDragged, 500 + t.bounds.width / 4), let up = ev(.otherMouseUp, 500 + t.bounds.width / 4) {
                    t.otherMouseDown(with: down); t.otherMouseDragged(with: drag)
                    check(abs((s0 - d.viewStart) - d.viewSpan / 4) < 0.01, "bouton molette + glissement vers la droite : vue reculée de \(String(format: "%.2f", s0 - d.viewStart)) s (attendu \(String(format: "%.2f", d.viewSpan / 4)))")
                    t.otherMouseUp(with: up)
                    let s1 = d.viewStart
                    t.otherMouseDragged(with: drag)
                    check(d.viewStart == s1, "bouton relâché : la vue ne bouge plus")
                } else { check(false, "événements souris synthétiques") }
                d.viewSpan = oldSpan; d.viewStart = oldStart; d.clampView()
            }
            w.setFrame(NSRect(origin: .zero, size: NSSize(width: 1200, height: 800)), display: true)
        }

        // défilement instantané : latence, régularité et exactitude des images affichées pendant le glissement
        do {
            let sc = model.player.scrubber
            for _ in 0 ..< 50 { if sc.ready { break }; await wait(0.1) }
            Perf.mark("repos (aperçu seul)"); await wait(10); Perf.mark("repos 10 s")
            check(sc.ready, "décodeur de défilement prêt")
            if sc.ready {
                let fd = model.player.frameDuration
                func now() -> Double { Date().timeIntervalSinceReferenceDate * 1000 }
                func median(_ a: [Double]) -> Double { a.sorted()[a.count / 2] }
                func f0(_ x: Double) -> String { String(format: "%.0f", x) }
                func jump(_ t: Double) async -> (first: Double, exact: Double, pts: Double)? {
                    let n0 = sc.presentCount, t0 = now(); var first = -1.0
                    sc.show(t)
                    let tc = min(max(t, 0), d.duration)
                    while now() - t0 < 6000 {
                        if first < 0, sc.presentCount > n0 { first = now() - t0 }
                        if sc.presentCount > n0, let e = sc.lastExact, abs(e.target - tc) < 1e-9 { return (first < 0 ? now() - t0 : first, now() - t0, e.pts) }
                        try? await Task.sleep(nanoseconds: 300_000)
                    }
                    return nil
                }
                let targets: [Double] = [37.1, 410.6, 733.2, 1000.5, 660.9, 1320.4, 85.7, 1650.0, 1326.5, 522.3, 14.2, 1221.9]
                // référence : AVPlayer avec saut vers l'image clé voisine (l'ancienne méthode)
                var base: [Double] = []
                for t in targets {
                    let t0 = now()
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                        model.player.player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity) { _ in c.resume() }
                    }
                    base.append(now() - t0)
                }
                check(true, "référence AVPlayer (saut tolérant) : médiane \(f0(median(base))) ms, max \(f0(base.max() ?? 0)) ms par déplacement")
                // sauts à froid (groupe d'images pas encore décodé)
                var firsts: [Double] = [], exacts: [Double] = [], bad = 0, lost = 0
                for t in targets {
                    guard let r = await jump(t) else { lost += 1; continue }
                    firsts.append(r.first); exacts.append(r.exact)
                    if !(r.pts <= t + 1e-3 && t - r.pts < fd * 1.6) { bad += 1; print("        image hors cible : demandé \(t), obtenu \(r.pts)") }
                }
                Perf.mark("12 sauts à froid")
                check(lost == 0 && !firsts.isEmpty, "sauts à froid : \(targets.count - lost)/\(targets.count) réponses")
                if !firsts.isEmpty {
                    check(median(firsts) < 60, "sauts à froid : 1re image (clé) en \(f0(median(firsts))) ms (médiane), \(f0(firsts.max() ?? 0)) ms (max)")
                    check(true, "sauts à froid : image exacte en \(f0(median(exacts))) ms (médiane), \(f0(exacts.max() ?? 0)) ms (max)")
                }
                check(bad == 0, "images exactes à la bonne position (\(bad) hors cible)")
                // retour vers un groupe déjà décodé : depuis la mémoire
                _ = await jump(1000.5); _ = await jump(400.2)
                if let r = await jump(1000.5) { check(r.exact < 15, "retour dans un groupe déjà décodé : \(f0(r.exact)) ms") } else { check(false, "retour dans un groupe déjà décodé") }
                if let r = await jump(1000.5 + fd) { check(r.exact < 15, "image suivante dans un groupe décodé : \(f0(r.exact)) ms") } else { check(false, "image suivante") }
                // glissement : 400 mouvements à 60 Hz, 15 s de vidéo par seconde
                var t = 100.0, last = sc.presentCount, run = 0, maxRun = 0
                let n0 = sc.presentCount, d0 = now()
                for _ in 0 ..< 400 {
                    t += 0.25; sc.show(t)
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    let c = sc.presentCount
                    if c == last { run += 1; maxRun = max(maxRun, run) } else { run = 0 }
                    last = c
                }
                Perf.mark("glissement rapide (400 mouvements)")
                let shown = sc.presentCount - n0
                check(maxRun <= 6, "glissement rapide : \(shown) images affichées en \(f0(now() - d0)) ms, plus longue pause \(maxRun * 16) ms")
                if let r = await jump(t) { check(r.pts <= t + 1e-3 && t - r.pts < fd * 1.6, "glissement : image exacte \(f0(r.exact)) ms après l'arrêt") } else { check(false, "glissement : image exacte") }
                // même image que le décodeur d'Apple (contenu, couleurs, orientation)
                if let url = d.info.url as URL? {
                    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                    gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
                    gen.maximumSize = CGSize(width: 1280, height: 720); gen.appliesPreferredTrackTransform = true
                    func tiny(_ img: CGImage) -> [UInt8] {
                        var px = [UInt8](repeating: 0, count: 48 * 27 * 4)
                        let ctx = CGContext(data: &px, width: 48, height: 27, bitsPerComponent: 8, bytesPerRow: 48 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                        ctx.interpolationQuality = .medium; ctx.draw(img, in: CGRect(x: 0, y: 0, width: 48, height: 27)); return px
                    }
                    for tt in [37.1, 733.2, 1650.0] {
                        guard let r = await jump(tt), let pb = sc.lastPixelBuffer, let mine = Scrubber.cgImage(pb),
                              let ref = try? await gen.image(at: CMTime(seconds: r.pts, preferredTimescale: 6000)).image else { check(false, "comparaison d'image à \(tt) s"); continue }
                        let a = tiny(mine), b = tiny(ref)
                        var sum = 0.0
                        for i in 0 ..< min(a.count, b.count) { sum += abs(Double(a[i]) - Double(b[i])) }
                        let diff = sum / Double(a.count)
                        check(diff < 6, "image à \(Fmt.time(r.pts)) identique à celle d'Apple (écart moyen \(String(format: "%.1f", diff))/255)")
                    }
                }
                Perf.mark("fin des essais de défilement")
                let held = sc.cacheBytes
                check(held <= 520 * 1_048_576, "réserve d'images plafonnée : \(held / 1_048_576) Mo après le défilement (plafond 400 Mo + groupe en cours)")
                check(sc.mismatches == 0, "images clés : début de groupe cohérent (\(sc.mismatches) écart) ; mémoire : \(sc.cacheSummary)")
                sc.hide()
                await wait(16); Perf.mark("16 s après le défilement")
                check(sc.cacheBytes == 0, "réserve libérée au repos : \(sc.cacheBytes / 1_048_576) Mo après 16 s")
            }
        }

        // agent : `mslice-mcp` transmet les appels à l'appli ouverte par la prise locale (la timeline se met à jour en direct)
        do {
            let sock = FileManager.default.temporaryDirectory.appendingPathComponent("ms-\(UUID().uuidString.prefix(6)).sock").path
            AgentServer.shared.stop(); setenv("MSLICE_AGENT_SOCKET", sock, 1); AgentServer.shared.start()
            let prevEnabled = UserDefaults.standard.object(forKey: "agent.enabled"), prevFolder = model.opts.folder
            defer { AgentServer.shared.stop(); unsetenv("MSLICE_AGENT_SOCKET"); if let p = prevEnabled { UserDefaults.standard.set(p, forKey: "agent.enabled") } else { UserDefaults.standard.removeObject(forKey: "agent.enabled") }; model.opts.folder = prevFolder }
            model.opts.folder = out.path
            UserDefaults.standard.set(false, forKey: "agent.enabled")
            if let mcp = MCPProc(env: ["MSLICE_AGENT_SOCKET": sock]) {
                _ = await mcp.rpc("initialize", ["protocolVersion": "2025-03-26", "capabilities": [String: Any](), "clientInfo": ["name": "essai-ui", "version": "1"]])
                let off = await mcp.tool("get_state", [:])
                check(off.error && off.text.contains("off"), "agent désactivé dans les préférences : appel refusé par l'appli")
                UserDefaults.standard.set(true, forKey: "agent.enabled")
                let st = await mcp.tool("get_state", [:])
                check(!st.error && st.json?["app_open"] as? Bool == true && (st.json?["current_file"] as? String) == d.url.path, "pont : get_state voit l'appli ouverte et son fichier courant")
                let set = await mcp.tool("set_segments", ["path": d.url.path, "segments": [["start": 100, "end": 130], ["start": "5:00", "end": "5:20", "name": "agent"]]])
                check(!set.error && set.json?["live_in_app"] as? Bool == true && d.segments.count == 2 && d.segments.last?.name == "agent", "set_segments : la timeline de l'appli est mise à jour en direct (\(d.segments.count) morceaux)")
                _ = await mcp.tool("seek", ["time": "2:30"])
                await wait(0.3)
                check(abs(model.player.time - 150) < 0.1, "seek : tête de lecture à \(Fmt.time(model.player.time))")
                let seg = await mcp.tool("get_segments", ["path": d.url.path])
                check(seg.json?["live_in_app"] as? Bool == true && seg.json?["count"] as? Int == 2, "get_segments : lus en direct")
                let ex = await mcp.tool("export", ["path": d.url.path, "folder": out.path])
                let created = (ex.json?["created"] as? [[String: Any]]) ?? []
                check(!ex.error && created.count == 2 && created.allSatisfy { FileManager.default.fileExists(atPath: ($0["path"] as? String) ?? "") }, "export par l'agent : \(created.count) fichiers créés (copie directe)")
                check(created.contains { ($0["path"] as? String)?.hasSuffix("/agent.mp4") == true }, "nom de morceau choisi par l'agent respecté (agent.mp4)")
                let bad = await mcp.tool("export", ["path": d.url.path, "folder": "/tmp"])
                check(bad.error && bad.text.contains("not allowed"), "dossier hors source refusé par l'appli")
                check(model.toast?.contains("Agent") == true, "l'appli signale l'export de l'agent (\(model.toast ?? "—"))")
                d.segments = []
                mcp.stop()
                for c in created { if let f = c["path"] as? String { try? FileManager.default.removeItem(atPath: f) } }      // le dossier d'essai ne garde que les exports de la suite
            } else { check(false, "mslice-mcp introuvable dans le paquet") }
        }

        // onglet Trouver : analyse par le modèle de l'onglet (annulable), critères ET / SAUF, piste de résultats, ajout aux morceaux (⌘Z), outils d'agent en direct
        do {
            let idxDir = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-uiindex-\(UUID().uuidString.prefix(6))")      // hors du dossier d'export de l'essai
            setenv("MSLICE_INDEX_DIR", idxDir.path, 1)
            defer { unsetenv("MSLICE_INDEX_DIR"); try? FileManager.default.removeItem(at: idxDir) }
            AnalysisStore.remove(d.info)
            d.segments = []; d.selected = nil
            let find = d.find
            check(!find.hasIndex || find.index != nil, "Trouver : modèle de l'onglet créé")
            find.start()
            await wait(1.5)
            check(find.running && find.progress.fraction > 0, "Trouver : analyse en cours (\(Int(find.progress.fraction * 100)) %, mémoire du processus d'analyse \(Int(find.progress.memoryMB)) Mo)")
            Perf.mark("analyse en cours (appli)")
            find.cancel()
            for _ in 0 ..< 60 { if !find.running { break }; await wait(0.2) }
            check(!find.running && !find.hasIndex && !find.failed, "Trouver : annulation (aucun résultat, pas d'erreur affichée)")
            let t0 = Date()
            let idx = await find.analyzeAndWait(force: false)
            Perf.mark("analyse terminée (appli)")
            check(idx != nil && find.hasIndex && !find.summary.scenes.isEmpty && !find.summary.sounds.isEmpty, "Trouver : analyse de \(Fmt.time(d.duration, decimals: false)) en \(String(format: "%.0f", Date().timeIntervalSince(t0))) s (\(find.summary.scenes.count) familles de scènes, \(find.summary.sounds.count) de sons, \(idx?.shotCount ?? 0) plans)")
            if let row = find.summary.scenes.first(where: { $0.term.key == "clothing" }) ?? find.summary.scenes.first {
                find.add(row.term)
                let n = find.result.passages.count
                check(n > 0 && find.lane.count == n && !find.terms.isEmpty, "Trouver : critère « \(row.term.name) » → \(n) passages, piste de résultats \(find.lane.count) traits")
                let wholeTotal = find.result.passages.reduce(0.0) { $0 + $1.duration }
                find.wholeShots = false
                let marginTotal = find.result.passages.reduce(0.0) { $0 + $1.duration }
                check(find.result.passages.count >= n && marginTotal <= wholeTotal + 1, "Trouver : sans « plans entiers » les passages sont plus justes (\(Int(wholeTotal)) s → \(Int(marginTotal)) s)")
                find.wholeShots = true
                if let music = find.summary.sounds.first(where: { $0.term.key == "music" }) {
                    var neg = music.term; neg.exclude = true; find.add(neg)
                    check(find.result.passages.contains { $0.excludedBy != nil } && find.pieces.count < find.result.passages.count, "Trouver : SAUF musique écarte des passages (\(find.keptCount)/\(find.result.passages.count) gardés)")
                    find.remove(neg)
                }
                if let first = find.result.passages.first(where: { $0.excludedBy == nil }) {
                    find.toggle(first)
                    check(!find.isChecked(first), "Trouver : un passage décoché sort des morceaux")
                    find.toggle(first)
                }
                let expected = find.pieces
                find.addToPieces()
                check(d.segments.count == expected.count && find.added?.count == expected.count && find.terms.isEmpty && find.lane.isEmpty, "Trouver : \(expected.count) morceaux ajoutés à la timeline, sélection vidée")
                check(d.segments.first.map { abs($0.start - (expected.first?.start ?? -1)) < 0.001 } ?? false, "Trouver : les morceaux ajoutés sont ceux de la liste")
                d.undo()
                check(d.segments.isEmpty, "Trouver : ⌘Z retire d'un coup tous les morceaux ajoutés")
            } else { check(false, "Trouver : aucune famille de scène reconnue") }

            // outils d'agent en direct : find_scenes pose les morceaux dans la timeline ouverte, analyze_media relit le résultat sans recalcul
            let sock = FileManager.default.temporaryDirectory.appendingPathComponent("ms-\(UUID().uuidString.prefix(6)).sock").path
            AgentServer.shared.stop(); setenv("MSLICE_AGENT_SOCKET", sock, 1); AgentServer.shared.start()
            let prevEnabled = UserDefaults.standard.object(forKey: "agent.enabled")
            defer { AgentServer.shared.stop(); unsetenv("MSLICE_AGENT_SOCKET"); if let p = prevEnabled { UserDefaults.standard.set(p, forKey: "agent.enabled") } else { UserDefaults.standard.removeObject(forKey: "agent.enabled") } }
            UserDefaults.standard.set(true, forKey: "agent.enabled")
            if let mcp = MCPProc(env: ["MSLICE_AGENT_SOCKET": sock, "MSLICE_INDEX_DIR": idxDir.path]) {
                _ = await mcp.rpc("initialize", ["protocolVersion": "2025-03-26", "capabilities": [String: Any](), "clientInfo": ["name": "essai-trouver", "version": "1"]])
                let an = await mcp.tool("analyze_media", ["path": d.url.path])
                check(!an.error && an.json?["analyzed_now"] as? Bool == false && (an.json?["shots"] as? Int ?? 0) > 100, "agent : analyze_media relit l'analyse de l'appli sans recalcul (\(an.json?["shots"] ?? "?") plans)")
                let fs = await mcp.tool("find_scenes", ["path": d.url.path, "include": ["scene:clothing"], "exclude": ["sound:music"], "apply": "set"])
                check(!fs.error && fs.json?["live_in_app"] as? Bool == true && d.segments.count > 0 && d.segments.count == fs.json?["count"] as? Int, "agent : find_scenes pose \(d.segments.count) morceaux en direct dans la timeline")
                let again = await mcp.tool("find_scenes", ["path": d.url.path, "include": ["scene:clothing"], "exclude": ["sound:music"]])
                check(!again.error && again.json?["applied"] == nil && d.segments.count == fs.json?["count"] as? Int, "agent : find_scenes sans apply ne touche pas aux morceaux")
                mcp.stop()
            } else { check(false, "mslice-mcp introuvable dans le paquet") }
            d.segments = []; d.selected = nil
            find.clear()
        }

        // panneau de discussion : boucle d'outils des moteurs API, contre un faux service local (MSLICE_TEST_LLM=http://127.0.0.1:port)
        if let llm = ProcessInfo.processInfo.environment["MSLICE_TEST_LLM"] {
            let ud = UserDefaults.standard
            let saved = ["agent.enabled", "agent.backend", "agent.anthropic.base", "agent.openai.base", "agent.openai.model"].map { ($0, ud.object(forKey: $0)) }
            let keyAn = AgentKeychain.get("anthropic"), keyOa = AgentKeychain.get("openai")
            defer {
                for (k, v) in saved { if let v { ud.set(v, forKey: k) } else { ud.removeObject(forKey: k) } }
                AgentKeychain.set("anthropic", keyAn ?? ""); AgentKeychain.set("openai", keyOa ?? "")
            }
            ud.set(true, forKey: "agent.enabled")
            AgentKeychain.set("anthropic", "test-key"); AgentKeychain.set("openai", "test-key")
            ud.set(llm, forKey: "agent.anthropic.base"); ud.set(llm + "/v1", forKey: "agent.openai.base"); ud.set("test-model", forKey: "agent.openai.model")
            let chat = AgentChat.shared
            for backend in [AgentBackend.anthropic, .openai] {
                ud.set(backend.rawValue, forKey: "agent.backend")
                let t = await chat.test()
                check(t.ok, "\(backend.title) : test de connexion (\(t.text))")
                chat.reset(); chat.send("Où en est l'appli ?")
                for _ in 0 ..< 150 { if !chat.busy, chat.messages.count >= 3 { break }; await wait(0.1) }
                let tool = chat.messages.first { $0.role == .tool }
                check(tool?.tool == "get_state" && tool?.done == true && tool?.failed == false, "\(backend.title) : l'agent appelle get_state, l'appli exécute l'outil")
                check(chat.messages.last { $0.role == .assistant }?.text.hasPrefix("Terminé") == true, "\(backend.title) : réponse finale affichée (\(chat.messages.last?.text.prefix(40) ?? "—"))")
                // tour suivant : l'historique reste cohérent
                chat.send("Encore une fois."); for _ in 0 ..< 150 { if !chat.busy { break }; await wait(0.1) }
                check(chat.messages.filter { $0.role == .assistant && $0.text.hasPrefix("Terminé") }.count == 2, "\(backend.title) : deuxième tour avec historique")
            }
            ud.set(false, forKey: "agent.enabled")
            chat.reset(); chat.send("test")
            check(chat.messages.last?.role == .note && chat.messages.last?.failed == true && !chat.busy, "agent désactivé : le panneau refuse avec un message")
            chat.reset()
        }

        // panneau de discussion avec la vraie CLI Claude Code (MSLICE_TEST_CLAUDE=1 : un appel court, utilise l'abonnement de l'utilisateur)
        if ProcessInfo.processInfo.environment["MSLICE_TEST_CLAUDE"] == "1" {
            let ud = UserDefaults.standard
            let saved = ["agent.enabled", "agent.backend"].map { ($0, ud.object(forKey: $0)) }
            defer { for (k, v) in saved { if let v { ud.set(v, forKey: k) } else { ud.removeObject(forKey: k) } }; AgentServer.shared.stop() }
            ud.set(true, forKey: "agent.enabled"); ud.set(AgentBackend.claudeCode.rawValue, forKey: "agent.backend")
            AgentServer.shared.stop(); AgentServer.shared.start()
            let chat = AgentChat.shared
            let t = await chat.test()
            check(t.ok, "Claude Code : détecté (\(t.text))")
            chat.reset(); chat.send("Appelle l'outil get_state, puis réponds uniquement par le mot OK suivi du nombre de fichiers ouverts.")
            for _ in 0 ..< 1200 { if !chat.busy, chat.messages.contains(where: { $0.role == .assistant }) { break }; if !chat.busy, chat.messages.contains(where: { $0.role == .note }) { break }; await wait(0.1) }
            for m in chat.messages { print("        [\(m.role)] \(m.text.prefix(120))") }
            let tool = chat.messages.first { $0.role == .tool }
            check(tool?.tool == "get_state" && tool?.done == true && tool?.failed == false, "Claude Code : appelle get_state par mslice-mcp → l'appli")
            check(chat.messages.last { $0.role == .assistant }?.text.contains("OK") == true, "Claude Code : réponse affichée")
            chat.reset()
        }

        // positionnement précis
        model.player.seek(15); await wait(0.6)
        let real = model.player.player.currentTime().seconds
        check(abs(real - 15) < 0.05, "seek 15 s : lecteur à \(String(format: "%.3f", real)) s")
        // navigation par image clé (↑ ↓) et par image (← →)
        let next = Planner.keyframe(after: model.player.time, in: d.keyframes) ?? 0
        _ = key("\u{F700}", 126); await wait(0.5)
        check(abs(model.player.time - next) < 0.05, "↑ : image clé suivante \(Fmt.time(model.player.time)) (attendu \(Fmt.time(next)))")
        _ = key("\u{F701}", 125); await wait(0.5)
        check(model.player.time < next - 0.01, "↓ : image clé précédente \(Fmt.time(model.player.time))")
        let t0 = model.player.time
        _ = key("\u{F703}", 124); await wait(0.5)
        check(abs(model.player.time - (t0 + model.player.frameDuration)) < 0.005, "→ : une image (\(String(format: "%.4f", model.player.time - t0)) s)")
        _ = key("\u{F702}", 123, shift: true); await wait(0.5)
        check(abs(model.player.time - (t0 + model.player.frameDuration - 1)) < 0.05, "⇧← : une seconde en arrière")

        // bistouri
        d.segments = []; d.selected = nil
        model.player.seek(30); await wait(0.5); _ = key("i", 34)
        model.player.seek(95); await wait(0.5); _ = key("o", 31)
        model.player.seek(300); await wait(0.5); _ = key("i", 34)
        model.player.seek(380); await wait(0.5); _ = key("o", 31)
        check(d.segments.count == 2, "I O I O : \(d.segments.count) morceaux \(d.segments.map { Fmt.time($0.start) + "→" + Fmt.time($0.end) })")
        check(d.segments.first.map { abs($0.start - 27.0) < 3.5 } ?? false, "entrée calée sur l'image clé précédente (\(Fmt.time(d.segments.first?.start ?? -1)) pour 0:30.0)")

        // lecture : espace, L, K
        model.player.seek(100); await wait(0.6)
        Perf.mark("avant lecture")
        _ = key(" ", 49)
        var samples: [Double] = []
        for _ in 0 ..< 6 { await wait(0.5); samples.append(model.player.time - 100) }
        Perf.mark("lecture 3 s (vidéo 1080p + timeline)")
        let rate = (samples[5] - samples[2]) / 1.5          // vitesse régulière après le démarrage
        check(model.player.isPlaying && abs(rate - 1) < 0.2, "espace : lecture à vitesse normale (×\(String(format: "%.2f", rate)) ; positions \(samples.map { String(format: "%.2f", $0) }))")
        _ = key("k", 40); await wait(0.3)
        check(!model.player.isPlaying, "K : pause")
        _ = key("l", 37); await wait(0.2); _ = key("l", 37); await wait(1.0)
        check(model.player.rate == 2, "L L : vitesse ×2")
        _ = key("k", 40)
        if shots == "1" { delegate.snapshot(to: "build/ui-editor.png") }

        // feuille d'options (bouton réglages de la barre d'export) : s'ouvre avec le bon nombre de fichiers, Échap / Annuler la ferment sans exporter
        var o = model.opts; o.folder = out.path; o.passthrough = true; o.merge = false; o.format = .same; o.voiceOnly = false; model.opts = o
        model.requestPiecesExport()
        check(model.sheet == .options && model.request?.count == d.segments.count, "feuille d'options : ouverte pour \(model.request?.count ?? -1) fichiers")
        model.requestPiecesExport()
        check(model.sheet == .options, "feuille d'options : une seconde demande ne l'empile pas")
        model.cancelOptions()
        check(model.sheet == .none && model.request == nil && model.run == nil, "feuille d'options : Annuler ferme sans exporter")
        check(((try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []).isEmpty, "feuille d'options : aucun fichier écrit par Annuler")
        model.requestPiecesExport()
        model.confirmExport()
        check(model.sheet == .export || model.sheet == .done, "feuille d'options : Exporter lance l'export")
        for _ in 0 ..< 200 { if model.sheet == .done { break }; await wait(0.1) }
        check(model.sheet == .done && model.run?.error == nil, "feuille d'options : export terminé (\(model.run?.items.count ?? 0) fichiers)")
        model.closeSheet()
        for f in (try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? [] { try? FileManager.default.removeItem(at: out.appendingPathComponent(f)) }

        // export complet : un fichier par morceau, dans le dossier de test (bouton « Exporter N morceaux » : export direct)
        model.exportNow()
        for _ in 0 ..< 200 { if model.sheet == .done { break }; await wait(0.1) }
        check(model.sheet == .done && model.run?.error == nil, "export : fenêtre « terminé » (\(model.run?.items.count ?? 0) fichiers)")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []
        check(files.count == 2, "fichiers créés : \(files.sorted())")
        check(d.exported, "fichier marqué « Extrait »")
        if shots == "1" { await wait(0.5); delegate.snapshot(to: "build/ui-done.png") }
        model.closeSheet()

        // schéma mslice:// (envoyé par l'extension Finder) : ouvre le fichier sans doublon ; trim ouvre l'élagage en lot
        let enc = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))) ?? path
        let docsBefore = model.docs.count
        delegate.handle([URL(string: "mslice://open?f=\(enc)")!])
        await wait(0.5)
        check(model.docs.count == docsBefore && model.current === d, "mslice://open : fichier déjà ouvert, pas de doublon")
        delegate.handle([URL(string: "mslice://trim?f=\(enc)")!])
        await wait(0.5)
        check(delegate.batchWindow != nil, "mslice://trim : fenêtre d'élagage en lot ouverte")
        delegate.batchWindow?.close()

        // mémoire de la taille de la fenêtre : enregistrée à la fermeture, bornée à l'ouverture, position non mémorisée (centrée)
        if let w = delegate.window {
            UserDefaults.standard.removeObject(forKey: WindowMemory.key)
            w.setFrame(NSRect(origin: .zero, size: NSSize(width: 1337, height: 777)), display: true)
            delegate.saveWindowSize()
            check(WindowMemory.load() == NSSize(width: 1337, height: 777), "taille mémorisée : \(WindowMemory.load().map { "\(Int($0.width))×\(Int($0.height))" } ?? "aucune")")
            let screen = NSRect(x: 0, y: 0, width: 1512, height: 900)
            check(WindowMemory.fitted(NSSize(width: 1337, height: 777), in: screen) == NSSize(width: 1337, height: 777), "taille retrouvée à l'ouverture")
            check(WindowMemory.fitted(nil, in: screen) == WindowMemory.defaultSize, "sans mémoire : taille par défaut")
            check(WindowMemory.fitted(NSSize(width: 5000, height: 4000), in: screen) == NSSize(width: 1512, height: 900), "trop grande : ramenée à l'écran")
            check(WindowMemory.fitted(NSSize(width: 300, height: 200), in: screen) == WindowMemory.minSize, "trop petite : ramenée au minimum")
            delegate.centerHigh(w)
            if let v = (w.screen ?? NSScreen.main)?.visibleFrame { check(abs(w.frame.midX - v.midX) < 1.5, "position : fenêtre centrée à l'ouverture (écart \(String(format: "%.1f", w.frame.midX - v.midX)) pt)") }
            UserDefaults.standard.removeObject(forKey: WindowMemory.key)
            w.setFrame(NSRect(origin: .zero, size: NSSize(width: 1200, height: 800)), display: true)
        }

        // fenêtre des réglages : ouverture sans plantage, avec la vue réellement affichée un moment
        delegate.openSettings()
        await wait(1.5)
        check(delegate.settingsWindow?.isVisible == true || delegate.settingsWindow != nil, "réglages : fenêtre ouverte sans plantage")
        delegate.settingsWindow?.close()
        delegate.showAbout()
        await wait(0.5)
        delegate.openSettings(); await wait(0.5); delegate.settingsWindow?.close()
        check(true, "réglages : réouverture sans plantage")

        // suppression et annulation
        _ = key("\u{7F}", 51)
        check(d.segments.count == 1, "⌫ : morceau supprimé")
        d.undo()
        check(d.segments.count == 2, "annuler : morceau rétabli")

        print(failures == 0 ? "TOUT EST OK" : "\(failures) échec(s)")
        return failures == 0 ? 0 : 1
    }
}

/// Élagage en lot : copie légère de la vidéo dans un dossier temporaire, puis retrait de X s au début et Y s à la fin.
@MainActor
enum BatchTest {
    static func run(path: String) async -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ msg: String) { print((ok ? "OK     " : "ÉCHEC  ") + msg); if !ok { failures += 1 } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-batchtest-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("rush.mp4")
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: src)       // clone APFS : instantané
        guard let info = Probe.read(src) else { print("ÉCHEC  sonde"); return 1 }
        let m = BatchModel(urls: [src]); m.startSec = 15; m.endSec = 20; m.passthrough = true; m.detect = false
        let t = Date(); await m.start()
        let out = dir.appendingPathComponent("rush_elague.mp4")
        let got = Probe.read(out)?.duration ?? -1
        let want = info.duration - 35
        check(FileManager.default.fileExists(atPath: out.path) && abs(got - want) < 6, "élagage 15 s / 20 s : \(Fmt.time(got)) (attendu ≈ \(Fmt.time(want))) en \(String(format: "%.1f", Date().timeIntervalSince(t))) s ; \(m.notes)")
        // détection des silences (le fichier de test peut n'en avoir aucun)
        if let r = await Silence.detect(info) { print("INFO   silences : garder \(Fmt.time(r.start)) → \(Fmt.time(r.end))") } else { print("INFO   aucun silence d'ouverture ni de fin détecté") }
        // fichier trop court
        let m2 = BatchModel(urls: [src]); m2.startSec = 900; m2.endSec = 900; await m2.start()
        check(m2.results.isEmpty && !m2.notes.isEmpty, "fichier trop court ignoré avec un message")
        // relance : le nom ne s'écrase pas
        let m3 = BatchModel(urls: [src]); m3.startSec = 5; m3.endSec = 5; await m3.start()
        check(FileManager.default.fileExists(atPath: dir.appendingPathComponent("rush_elague_2.mp4").path), "deuxième passage : rush_elague_2.mp4 (rien n'est écrasé)")
        print(failures == 0 ? "TOUT EST OK" : "\(failures) échec(s)")
        return failures == 0 ? 0 : 1
    }
}
