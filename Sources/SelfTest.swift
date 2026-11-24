// mSLICE — essais sans fenêtre : `mSLICE --selftest <fichier>` sonde, coupe, fusionne, recompresse, puis vérifie les durées avec ffprobe.
import AppKit
import AVFoundation
import CoreMedia
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
        let tFilm = Date()
        for _ in 0 ..< 400 { if (0 ..< d.strip.count).allSatisfy({ d.strip.image($0) != nil }) { break }; await wait(0.1) }
        let tiles = (0 ..< d.strip.count).filter { d.strip.image($0) != nil }.count
        check(tiles == d.strip.count, "vignettes : \(tiles)/\(d.strip.count) en \(String(format: "%.1f", Date().timeIntervalSince(tFilm))) s (si le cache existe : instantané)")

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
                check(sc.mismatches == 0, "images clés : début de groupe cohérent (\(sc.mismatches) écart) ; mémoire : \(sc.cacheSummary)")
                sc.hide()
            }
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
