// mSLICE — essais sans fenêtre : `mSLICE --selftest <fichier>` sonde, coupe, fusionne, recompresse, puis vérifie les durées avec ffprobe.
import AppKit
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
        for _ in 0 ..< 150 { if !d.keyframes.isEmpty, !d.peaks.isEmpty, model.player.player.currentItem?.status == .readyToPlay { break }; await wait(0.2) }
        check(!d.keyframes.isEmpty, "images clés chargées : \(d.keyframes.count)")
        check(!d.peaks.isEmpty, "forme d'onde calculée : \(Fmt.time(d.peaks.duration)) déjà")
        check(model.player.player.currentItem?.status == .readyToPlay, "lecteur prêt (\(model.player.preparing ?? "fichier d'origine"))")
        for _ in 0 ..< 100 { if (0 ..< d.strip.count).contains(where: { d.strip.image($0) != nil }) { break }; await wait(0.2) }
        check((0 ..< d.strip.count).filter { d.strip.image($0) != nil }.count > 3, "vignettes : \((0 ..< d.strip.count).filter { d.strip.image($0) != nil }.count)/\(d.strip.count)")

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
        _ = key(" ", 49)
        var samples: [Double] = []
        for _ in 0 ..< 6 { await wait(0.5); samples.append(model.player.time - 100) }
        let rate = (samples[5] - samples[2]) / 1.5          // vitesse régulière après le démarrage
        check(model.player.isPlaying && abs(rate - 1) < 0.2, "espace : lecture à vitesse normale (×\(String(format: "%.2f", rate)) ; positions \(samples.map { String(format: "%.2f", $0) }))")
        _ = key("k", 40); await wait(0.3)
        check(!model.player.isPlaying, "K : pause")
        _ = key("l", 37); await wait(0.2); _ = key("l", 37); await wait(1.0)
        check(model.player.rate == 2, "L L : vitesse ×2")
        _ = key("k", 40)
        if shots == "1" { delegate.snapshot(to: "build/ui-editor.png") }

        // export complet : un fichier par morceau, dans le dossier de test
        var o = model.opts; o.folder = out.path; o.passthrough = true; o.merge = false; o.format = .same; model.opts = o
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
