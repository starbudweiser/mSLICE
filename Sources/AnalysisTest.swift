// mSLICE — essai `--selftest-analysis <fichier>` : analyse native sans fenêtre (vocabulaires, index, requêtes, précision des plans, temps, mémoire, annulation, pause).
import AppKit
import CryptoKit
import Foundation
import SoundAnalysis
import Vision

@MainActor
enum AnalysisTest {
    static func run(path: String) async -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ msg: String) { print((ok ? "OK     " : "ÉCHEC  ") + msg); if !ok { failures += 1 } }
        func f1(_ x: Double) -> String { String(format: "%.1f", x) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-analysis-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        setenv("MSLICE_INDEX_DIR", tmp.path, 1)
        defer { try? FileManager.default.removeItem(at: tmp); unsetenv("MSLICE_INDEX_DIR") }

        // 1. vocabulaires : chaque étiquette citée par une famille existe dans macOS ; chaque famille est traduite ; chaque pictogramme existe
        let visionVocab = Set((try? VNClassifyImageRequest().supportedIdentifiers()) ?? [])
        let soundVocab = Set((try? SNClassifySoundRequest(classifierIdentifier: .version1))?.knownClassifications ?? [])
        let badScene = SceneFamilies.all.flatMap { f in f.labels.filter { !visionVocab.contains($0) }.map { "\(f.id):\($0)" } }
        let badSound = SoundFamilies.all.flatMap { f in f.labels.filter { !soundVocab.contains($0) }.map { "\(f.id):\($0)" } }
        check(!visionVocab.isEmpty && badScene.isEmpty, "familles de scènes : \(SceneFamilies.all.count) familles, \(Set(SceneFamilies.all.flatMap(\.labels)).count)/\(visionVocab.count) étiquettes Vision utilisées, \(badScene.count) inconnue(s) \(badScene.prefix(5))")
        check(!soundVocab.isEmpty && badSound.isEmpty, "familles de sons : \(SoundFamilies.all.count) familles, \(Set(SoundFamilies.all.flatMap(\.labels)).count)/\(soundVocab.count) types de sons utilisés, \(badSound.count) inconnu(s) \(badSound.prefix(5))")
        let missingSound = soundVocab.subtracting(Set(SoundFamilies.all.flatMap(\.labels)))
        print("INFO   sons sans famille (cherchables par « sound_label: ») : \(missingSound.count) — \(missingSound.sorted().prefix(12).joined(separator: ", "))…")
        check(L.problems().isEmpty, "textes : quatre langues complètes (\(L.table.count) textes) \(L.problems().prefix(4))")
        let ids = SceneFamilies.all.map(\.id), sids = SoundFamilies.all.map(\.id)
        check(Set(ids).count == ids.count && Set(sids).count == sids.count, "identifiants de familles uniques")
        let symbols = (SceneFamilies.all + SoundFamilies.all).map(\.symbol)
        let noSymbol = Set(symbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil })
        check(noSymbol.isEmpty, "pictogrammes SF Symbols présents sur ce système : \(noSymbol.sorted())")

        // 2. index : aller-retour, et refus d'un index tronqué ou trafiqué
        var idx = AnalysisIndex(duration: 60)
        idx.hasVideo = true; idx.hasAudio = true
        idx.cuts = [10, 20, 40]
        idx.sceneLabels = ["fire", "people"]
        idx.sceneOffsets = [0]; idx.sceneLabelIdx = []; idx.sceneConf = []
        for s in 0 ..< 120 {                                        // 0,5 s par échantillon : feu de 12 s à 18 s, personnes de 5 s à 35 s sauf 22–23 s
            let t = Double(s) * 0.5
            if t >= 12 && t < 18 { idx.sceneLabelIdx.append(0); idx.sceneConf.append(230) }
            if t >= 5 && t < 35 && !(t >= 22 && t < 23) { idx.sceneLabelIdx.append(1); idx.sceneConf.append(200) }
            idx.sceneOffsets.append(Int32(idx.sceneLabelIdx.count))
        }
        idx.soundLabels = ["music", "laughter"]
        idx.soundStarts = []; idx.soundOffsets = [0]; idx.soundLabelIdx = []; idx.soundConf = []
        for k in 0 ..< 118 {                                        // fenêtre de 1,5 s toutes les 0,5 s ; musique de 30 s à 50 s, rire vers 14 s
            let start = Double(k) * 0.5, centre = start + 0.75
            idx.soundStarts.append(Float(start))
            if centre >= 30 && centre < 50 { idx.soundLabelIdx.append(0); idx.soundConf.append(220) }
            if centre >= 14 && centre < 15.5 { idx.soundLabelIdx.append(1); idx.soundConf.append(200) }
            idx.soundOffsets.append(Int32(idx.soundLabelIdx.count))
        }
        if let d = idx.serialized(), let back = AnalysisIndex(serialized: d) {
            check(back.cuts == idx.cuts && back.sceneLabelIdx == idx.sceneLabelIdx && back.soundStarts == idx.soundStarts && back.soundConf == idx.soundConf && back.sceneLabels == idx.sceneLabels, "index : aller-retour sans perte (\(d.count) octets)")
            var bad = d; bad.removeLast(40)
            check(AnalysisIndex(serialized: bad) == nil && AnalysisIndex(serialized: Data("pas un index".utf8)) == nil, "index tronqué ou illisible : refusé")
            var tampered = idx; tampered.sceneLabelIdx[0] = 99
            check(tampered.serialized().flatMap { AnalysisIndex(serialized: $0) } == nil, "index incohérent (étiquette hors table) : refusé")
        } else { check(false, "index : sérialisation") }
        check(idx.shot(at: 5).start == 0 && idx.shot(at: 5).end == 10 && idx.shot(at: 10).start == 10 && idx.shot(at: 59).end == 60, "plans : recherche du plan d'un instant")

        // 3. requêtes ET / SAUF, plans entiers, lissage, marges
        let finder = Finder(idx)
        func terms(_ a: [String], _ except: [String] = []) -> [FindTerm] { a.compactMap { FindTerm.parse($0) } + except.compactMap { FindTerm.parse($0, exclude: true) } }
        var q = FindQuery(terms: terms(["scene:fire"]), wholeShots: false)
        var r = finder.run(q)
        check(r.passages.count == 1 && abs(r.passages[0].start - 11.7) < 0.01 && abs(r.passages[0].end - 18.3) < 0.01, "feu seul, marge de 0,3 s : \(r.passages.map { "\(f1($0.start))→\(f1($0.end))" })")
        q.wholeShots = true; r = finder.run(q)
        check(r.passages.count == 1 && r.passages[0].start == 10 && r.passages[0].end == 20, "feu, plans entiers : calé sur les coupures 10 → 20 (\(r.passages.map { "\($0.start)→\($0.end)" }))")
        q = FindQuery(terms: terms(["scene:people"]), wholeShots: false); r = finder.run(q)
        check(r.passages.count == 1 && r.segments.count == 1 && r.segments[0].start < 5 && r.segments[0].end > 35, "personnes : le trou de 1 s (22–23 s) est comblé, un seul passage (\(r.passages.map { "\(f1($0.start))→\(f1($0.end))" }))")
        q = FindQuery(terms: terms(["scene:people", "scene:fire"]), wholeShots: false); r = finder.run(q)
        check(r.passages.count == 1 && abs(r.passages[0].start - 11.7) < 0.01, "personnes ET feu : intersection 12–18 s")
        q = FindQuery(terms: terms(["scene:people"], ["scene:fire"]), wholeShots: true); r = finder.run(q)
        check(r.passages.count == 1 && r.passages[0].excludedBy == SceneFamilies.byID["fire"]!.name && r.segments.isEmpty, "personnes SAUF feu, plans entiers : passage écarté et gardé dans la liste (\(r.passages.map { $0.excludedBy ?? "ok" }))")
        q = FindQuery(terms: terms(["sound:music"]), wholeShots: false); r = finder.run(q)
        check(r.passages.count == 1 && abs(r.passages[0].start - 29.7) < 0.35 && abs(r.passages[0].end - 50.3) < 0.35, "musique : 30 → 50 s (\(r.passages.map { "\(f1($0.start))→\(f1($0.end))" }))")
        q = FindQuery(terms: terms(["sound:laugh"]), wholeShots: false); r = finder.run(q)
        check(r.passages.count == 1 && r.passages[0].duration < 4.5, "rire de 1,5 s gardé (≥ 1 s) : \(r.passages.map { "\(f1($0.start))→\(f1($0.end))" })")
        q = FindQuery(terms: terms(["sound:music", "scene:fire"]), wholeShots: false); r = finder.run(q)
        check(r.passages.isEmpty, "musique ET feu : jamais en même temps → aucun passage")
        q = FindQuery(terms: [], wholeShots: true); check(finder.run(q).passages.isEmpty, "aucun critère : aucun passage")
        q = FindQuery(terms: terms([], ["scene:fire"])); check(finder.run(q).passages.isEmpty, "critère SAUF seul : aucun passage")
        q = FindQuery(terms: terms(["label:fire"]), wholeShots: false); check(finder.run(q).passages.count == 1 && finder.knows(FindTerm.parse("label:fire")!) && !finder.knows(FindTerm.parse("label:dragon")!), "étiquette brute « label:fire »")
        q = FindQuery(terms: terms(["scene:inconnu"])); check(finder.run(q).passages.isEmpty && FindTerm.parse("n'importe quoi") == nil && FindTerm.parse("scene:") == nil, "critère inconnu ou mal formé : sans effet")
        let sm = finder.summary()
        check(sm.scenes.first?.term.key == "people" && sm.scenes.contains { $0.term.key == "fire" && abs($0.seconds - 6) < 0.6 } && sm.sounds.first?.term.key == "music", "résumé : \(sm.scenes.map { "\($0.term.key) \(f1($0.seconds)) s" }), \(sm.sounds.map { "\($0.term.key) \(f1($0.seconds)) s" })")
        var two = idx; two.cuts = []                                   // sans coupure : « plans entiers » donne tout le fichier
        r = Finder(two).run(FindQuery(terms: terms(["scene:fire"]), wholeShots: true))
        check(r.passages.count == 1 && r.passages[0].start == 0 && r.passages[0].end == 60, "sans coupure détectée : plan unique = fichier entier")

        // 4. analyse réelle
        guard let info = Probe.read(URL(fileURLWithPath: path)) else { print("ÉCHEC  sonde de \(path)"); return 1 }
        print("INFO   fichier : \(info.url.lastPathComponent), \(Fmt.time(info.duration, decimals: false))")
        let before = Perf.footprintMB()
        Perf.mark("avant l'analyse")
        let job = AnalysisJob()
        let box = PeakBox()
        let t0 = Date()
        let separate = AnalysisRunner.helper() != nil
        // le lanceur utilise le processus séparé (mslice-mcp --analyze) quand il existe : c'est ce que fait l'appli
        let index = await AnalysisRunner.run(info, job: job) { p in box.note(p.memoryMB, p) }
        let secs = Date().timeIntervalSince(t0)
        Perf.mark("après l'analyse")
        guard let index else { print("ÉCHEC  analyse"); return 1 }
        check(separate, "l'analyse tourne dans un processus séparé (mslice-mcp --analyze)")
        check(Perf.footprintMB() < before + 8, "appli : \(Int(Perf.footprintMB())) Mo après l'analyse, contre \(Int(before)) Mo avant (rien de gardé en mémoire)")
        let budget = max(90 * info.duration / 1680, 4) + 4
        check(secs <= budget, "temps : \(f1(secs)) s pour \(Fmt.time(info.duration, decimals: false)) (limite \(f1(budget)) s ; 90 s pour 28 min)")
        check(box.peak > 0 && box.peak < 250, "mémoire : pic de \(Int(box.peak)) Mo dans le processus d'analyse (limite 250 Mo)")
        check(index.hasVideo == !info.isAudioOnly && index.hasAudio == (info.audio != nil), "pistes analysées : images \(index.hasVideo), sons \(index.hasAudio)")
        check(index.sceneSamples >= Int(info.duration / 0.5) - 1 && index.soundWindows > Int(info.duration / 0.5) - 6 || !index.hasAudio, "échantillons : \(index.sceneSamples) images, \(index.soundWindows) fenêtres de son")
        check(box.sawImages && (box.sawSounds || !index.hasAudio), "progression : images \(box.sawImages), sons \(box.sawSounds)")
        let sm2 = Finder(index).summary()
        print("INFO   plans : \(index.shotCount) ; scènes : \(sm2.scenes.prefix(6).map { "\($0.term.key) \(Int($0.seconds)) s" }) ; sons : \(sm2.sounds.prefix(6).map { "\($0.term.key) \(Int($0.seconds)) s" })")
        check(AnalysisStore.load(info) != nil, "index enregistré et relu (\(AnalysisStore.url(info).lastPathComponent), \((AnalysisStore.url(info).fileSize ?? 0) / 1024) Ko)")
        check(index.sceneLabels.count > 5 || info.isAudioOnly, "étiquettes de scène : \(index.sceneLabels.count) différentes ; sons : \(index.soundLabels.count)")
        check(index.cuts.allSatisfy { $0 > 0 && $0 < info.duration } && zip(index.cuts, index.cuts.dropFirst()).allSatisfy { $0 < $1 }, "coupures triées et dans le fichier")

        // 5. précision des coupures : comparaison avec ffmpeg (détection de scène, seuil 0,3) sur les 4 premières minutes
        if index.hasVideo, let ffmpeg = Tools.ffmpeg {
            let span = min(info.duration, 240.0)
            let out = await Task.detached { () -> String in
                let p = Process(); p.executableURL = ffmpeg
                p.arguments = ["-nostdin", "-hide_banner", "-v", "info", "-t", "\(span)", "-i", info.url.path, "-an", "-vf", "scale=480:-2,select='gt(scene,0.3)',showinfo", "-f", "null", "-"]
                let e = Pipe(); p.standardError = e; p.standardOutput = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { return "" }
                let d = e.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                return String(decoding: d, as: UTF8.self)
            }.value
            var ref: [Double] = []
            for line in out.split(separator: "\n") { if let r = line.range(of: "pts_time:"), let v = Double(line[r.upperBound...].prefix { $0.isNumber || $0 == "." }) { ref.append(v) } }
            let fd = 1 / max(info.video?.fps ?? 25, 1)
            let mine = index.cuts.filter { $0 <= span }
            let found = ref.filter { r in mine.contains { abs($0 - r) <= fd * 1.5 } }
            let exact = ref.filter { r in mine.contains { abs($0 - r) <= fd * 0.6 } }
            print("INFO   coupures de référence (ffmpeg) : \(ref.count) ; les nôtres sur la même durée : \(mine.count)")
            if ref.count >= 5 {
                check(Double(found.count) >= Double(ref.count) * 0.9, "coupures : \(found.count)/\(ref.count) de la référence retrouvées à ± 1 image")
                check(Double(exact.count) >= Double(ref.count) * 0.85, "coupures : \(exact.count)/\(ref.count) exactement à la même image")
            } else { print("INFO   pas assez de coupures de référence sur cet extrait pour juger la précision") }
        }

        // 6. repos : rien ne tourne après l'analyse (processeur, mémoire)
        let cpu0 = Perf.cpuSeconds()
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        let idleCPU = Perf.cpuSeconds() - cpu0
        check(idleCPU < 0.25, "repos : \(String(format: "%.2f", idleCPU)) s de processeur en 4 s après l'analyse")
        Perf.mark("repos 4 s")
        print("INFO   mémoire au repos après l'analyse : \(Int(Perf.footprintMB())) Mo (avant : \(Int(before)) Mo)")

        // 7. annulation : rend la main vite, n'enregistre rien
        AnalysisStore.remove(info)
        let job2 = AnalysisJob()
        let started = Date()
        Task { try? await Task.sleep(nanoseconds: 1_200_000_000); job2.cancel() }
        let cancelled = await AnalysisRunner.run(info, job: job2) { _ in }
        let took = Date().timeIntervalSince(started)
        check(cancelled == nil && took < 6 && AnalysisStore.load(info) == nil, "annulation : rendue en \(f1(took)) s, aucun index enregistré")

        // 8. pause pendant la lecture ou l'export : la progression s'arrête, puis reprend
        let job3 = AnalysisJob()
        let box3 = PeakBox()
        AnalysisGate.shared.paused = true
        let run3 = Task { await AnalysisRunner.run(info, job: job3) { p in box3.note(0, p) } }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let a = box3.last.fraction
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let b = box3.last.fraction
        check(abs(b - a) < 0.005, "pause : la progression ne bouge plus (\(f1(a * 100)) % → \(f1(b * 100)) %)")
        AnalysisGate.shared.paused = false
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        check(box3.last.fraction > b + 0.005 || box3.last.fraction >= 0.99, "reprise : la progression repart (\(f1(box3.last.fraction * 100)) %)")
        job3.cancel(); _ = await run3.value
        AnalysisStore.remove(info)

        // 5 bis. le moteur en processus donne le même résultat que le processus séparé
        if separate {
            let inproc = await Analyzer.run(info, job: AnalysisJob(), progress: { _ in })
            check(inproc?.cuts == index.cuts && inproc?.sceneLabelIdx == index.sceneLabelIdx, "moteur en processus : mêmes plans (\(inproc?.shotCount ?? 0)) et mêmes étiquettes que le processus séparé")
        }

        AnalysisStore.remove(info)

        // 9. modèle optionnel : téléchargement vérifié, refus d'une empreinte ou d'une taille fausse, adresses non sûres refusées, suppression
        do {
            let serve = tmp.appendingPathComponent("serve"); try? FileManager.default.createDirectory(at: serve, withIntermediateDirectories: true)
            var payload = Data(count: 700_000); payload.withUnsafeMutableBytes { raw in for i in 0 ..< raw.count { raw[i] = UInt8(truncatingIfNeeded: i &* 31 &+ (i >> 8)) } }
            try? payload.write(to: serve.appendingPathComponent("model.bin"))
            let sha = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            let port = 47_500 + Int.random(in: 0 ..< 400)
            let py = Process(); py.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            py.arguments = ["-m", "http.server", "\(port)", "--bind", "127.0.0.1", "--directory", serve.path]
            py.standardOutput = FileHandle.nullDevice; py.standardError = FileHandle.nullDevice
            if (try? py.run()) != nil {
                defer { py.terminate() }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                let url = URL(string: "http://127.0.0.1:\(port)/model.bin")!
                let store = ModelStore.shared
                func wait(_ spec: ModelSpec) async -> ModelStore.State { for _ in 0 ..< 100 { if case .downloading = store.state(spec) { try? await Task.sleep(nanoseconds: 100_000_000) } else { break } }; return store.state(spec) }
                let ok = ModelSpec(id: "test-ok-\(UUID().uuidString.prefix(5))", sizeMB: 1, url: url, sha256: sha, license: "test")
                check(!ModelStore.isInstalled(ok) && store.state(ok) == .notInstalled, "modèle optionnel : absent au départ")
                store.install(ok)
                let st = await wait(ok)
                check(st == .installed && (try? Data(contentsOf: ModelStore.file(ok))) == payload && ModelStore.isInstalled(ok), "modèle optionnel : téléchargé, empreinte vérifiée, installé (\(st))")
                let bad = ModelSpec(id: "test-bad-\(UUID().uuidString.prefix(5))", sizeMB: 1, url: url, sha256: String(repeating: "0", count: 64), license: "test")
                store.install(bad)
                let stBad = await wait(bad)
                check({ if case .failed = stBad { return true }; return false }() && !FileManager.default.fileExists(atPath: ModelStore.folder(bad).path), "modèle optionnel : mauvaise empreinte refusée, rien d'installé (\(stBad))")
                let big = ModelSpec(id: "test-big-\(UUID().uuidString.prefix(5))", sizeMB: 0, url: url, sha256: sha, license: "test")
                store.install(big)
                let stBig = await wait(big)
                check({ if case .failed = stBig { return true }; return false }() && !FileManager.default.fileExists(atPath: ModelStore.folder(big).path), "modèle optionnel : fichier plus gros que annoncé refusé (\(stBig))")
                check(ModelStore.verified(ok), "modèle optionnel : empreinte recalculée conforme avant usage")
                var tamper = (try? Data(contentsOf: ModelStore.file(ok))) ?? Data(); if !tamper.isEmpty { tamper[0] ^= 0xff }
                try? tamper.write(to: ModelStore.file(ok))
                check(ModelStore.isInstalled(ok) && !ModelStore.verified(ok), "modèle optionnel : fichier modifié après installation (même taille) détecté par l'empreinte")
                try? Data("tronqué".utf8).write(to: ModelStore.file(ok))
                check(!ModelStore.isInstalled(ok), "modèle optionnel : fichier tronqué : non installé")
                store.remove(ok)
                check(!FileManager.default.fileExists(atPath: ModelStore.folder(ok).path) && store.state(ok) == .notInstalled, "modèle optionnel : supprimé")
                for s in [bad, big] { store.remove(s) }
            } else { check(false, "serveur local de l'essai (python3)") }
            check(ModelStore.allowed(URL(string: "https://example.com/m.bin")!) && ModelStore.allowed(URL(string: "http://127.0.0.1:1/m")!) && !ModelStore.allowed(URL(string: "http://example.com/m.bin")!) && !ModelStore.allowed(URL(string: "ftp://example.com/m")!) && !ModelStore.allowed(URL(string: "file:///etc/passwd")!), "modèle optionnel : HTTPS seulement (HTTP uniquement vers ce Mac)")
            check(!ModelCatalog.characters.available && ModelStore.shared.state(ModelCatalog.characters) == .notInstalled, "modèle des personnages : pas encore retenu, aucun téléchargement proposé")
        }

        print(failures == 0 ? "TOUT EST OK" : "\(failures) échec(s)")
        return failures == 0 ? 0 : 1
    }
}

/// Mesures partagées entre le fil d'analyse et l'essai.
private final class PeakBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _peak = 0.0, _last = AnalysisProgress(), _images = false, _sounds = false
    func note(_ mb: Double, _ p: AnalysisProgress) { lock.lock(); _peak = max(_peak, mb); _last = p; if p.images > 0.02 { _images = true }; if p.sounds > 0.02 { _sounds = true }; lock.unlock() }
    var peak: Double { lock.lock(); defer { lock.unlock() }; return _peak }
    var last: AnalysisProgress { lock.lock(); defer { lock.unlock() }; return _last }
    var sawImages: Bool { lock.lock(); defer { lock.unlock() }; return _images }
    var sawSounds: Bool { lock.lock(); defer { lock.unlock() }; return _sounds }
}

private extension URL { var fileSize: Int? { (try? resourceValues(forKeys: [.fileSizeKey]))?.fileSize } }
