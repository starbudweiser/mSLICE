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
        setenv("MSLICE_MODEL_DIR", tmp.appendingPathComponent("models").path, 1)
        defer { try? FileManager.default.removeItem(at: tmp); unsetenv("MSLICE_INDEX_DIR"); unsetenv("MSLICE_MODEL_DIR") }

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
            let realZip = ProcessInfo.processInfo.environment["MSLICE_TEST_MODEL_ZIP"].flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            if let realZip { try? FileManager.default.copyItem(atPath: realZip, toPath: serve.appendingPathComponent("real.zip").path) }
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
                check(!ModelFiles.isInstalled(ok) && store.state(ok) == .notInstalled, "modèle optionnel : absent au départ")
                store.install(ok)
                let st = await wait(ok)
                check(st == .installed && (try? Data(contentsOf: ModelFiles.file(ok))) == payload && ModelFiles.isInstalled(ok), "modèle optionnel : téléchargé, empreinte vérifiée, installé (\(st))")
                let bad = ModelSpec(id: "test-bad-\(UUID().uuidString.prefix(5))", sizeMB: 1, url: url, sha256: String(repeating: "0", count: 64), license: "test")
                store.install(bad)
                let stBad = await wait(bad)
                check({ if case .failed = stBad { return true }; return false }() && !FileManager.default.fileExists(atPath: ModelFiles.folder(bad).path), "modèle optionnel : mauvaise empreinte refusée, rien d'installé (\(stBad))")
                let big = ModelSpec(id: "test-big-\(UUID().uuidString.prefix(5))", sizeMB: 0, url: url, sha256: sha, license: "test")
                store.install(big)
                let stBig = await wait(big)
                check({ if case .failed = stBig { return true }; return false }() && !FileManager.default.fileExists(atPath: ModelFiles.folder(big).path), "modèle optionnel : fichier plus gros que annoncé refusé (\(stBig))")
                check(ModelFiles.verified(ok), "modèle optionnel : empreinte recalculée conforme avant usage")
                var tamper = (try? Data(contentsOf: ModelFiles.file(ok))) ?? Data(); if !tamper.isEmpty { tamper[0] ^= 0xff }
                try? tamper.write(to: ModelFiles.file(ok))
                check(ModelFiles.isInstalled(ok) && !ModelFiles.verified(ok), "modèle optionnel : fichier modifié après installation (même taille) détecté par l'empreinte")
                try? Data("tronqué".utf8).write(to: ModelFiles.file(ok))
                check(!ModelFiles.isInstalled(ok), "modèle optionnel : fichier tronqué : non installé")
                store.remove(ok)
                check(!FileManager.default.fileExists(atPath: ModelFiles.folder(ok).path) && store.state(ok) == .notInstalled, "modèle optionnel : supprimé")
                for s in [bad, big] { store.remove(s) }

                // archive Core ML : le vrai modèle des personnages (si MSLICE_TEST_MODEL_ZIP donne le zip) est installé puis vérifié
                if realZip != nil, let zsha = try? ModelFiles.hash(of: serve.appendingPathComponent("real.zip")) {
                    let real = ModelSpec(id: "test-real-\(UUID().uuidString.prefix(5))", sizeMB: 60, url: URL(string: "http://127.0.0.1:\(port)/real.zip")!, sha256: zsha, license: "test", kind: .coreMLArchive)
                    let t0 = Date()
                    store.install(real)
                    for _ in 0 ..< 1200 { if case .downloading = store.state(real) { try? await Task.sleep(nanoseconds: 100_000_000) } else { break } }
                    let sr = store.state(real)
                    check(sr == .installed && ModelFiles.isInstalled(real) && ModelFiles.verified(real), "archive Core ML : téléchargée, décompressée, compilée, installée en \(f1(Date().timeIntervalSince(t0))) s (\(sr))")
                    let fm = FileManager.default
                    check(fm.fileExists(atPath: ModelFiles.compiled(real).path) && fm.fileExists(atPath: ModelFiles.folder(real).appendingPathComponent("LICENSE.txt").path) && fm.fileExists(atPath: ModelFiles.folder(real).appendingPathComponent("NOTICE.txt").path) && !fm.fileExists(atPath: ModelFiles.folder(real).appendingPathComponent("payload").path), "archive Core ML : modèle compilé, licence et notice gardés, rien d'autre")
                    let weights = ModelFiles.compiled(real).appendingPathComponent("weights/weight.bin")
                    if var w = try? Data(contentsOf: weights), !w.isEmpty {
                        w[w.count / 2] ^= 0xff; try? w.write(to: weights)
                        check(ModelFiles.isInstalled(real) && !ModelFiles.verified(real), "archive Core ML : poids modifiés après installation détectés avant usage")
                    } else { check(false, "archive Core ML : fichier de poids introuvable") }
                    store.remove(real)
                    check(!fm.fileExists(atPath: ModelFiles.folder(real).path), "archive Core ML : supprimée")
                } else { print("INFO   archive Core ML réelle non essayée (MSLICE_TEST_MODEL_ZIP absent)") }
            } else { check(false, "serveur local de l'essai (python3)") }

            // archives hostiles : refusées avant toute extraction, rien n'est écrit hors du dossier de travail
            let hostile = tmp.appendingPathComponent("hostile"); try? FileManager.default.createDirectory(at: hostile, withIntermediateDirectories: true)
            let absName = "/tmp/mslice-evil-\(UUID().uuidString.prefix(8)).txt"
            let mk = Process(); mk.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            mk.arguments = ["-I", "-c", """
import sys, zipfile
d, a = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(d + '/evil-path.zip', 'w') as z: z.writestr('../mslice-evil-parent.txt', 'x')
with zipfile.ZipFile(d + '/abs-path.zip', 'w') as z: z.writestr(a, 'x')
with zipfile.ZipFile(d + '/link.zip', 'w') as z:
    i = zipfile.ZipInfo('link'); i.external_attr = 0o120777 << 16; z.writestr(i, '/etc/passwd')
with zipfile.ZipFile(d + '/ok.zip', 'w') as z: z.writestr('a.txt', 'x')
""", hostile.path, absName]
            mk.standardOutput = FileHandle.nullDevice; mk.standardError = FileHandle.nullDevice
            if (try? mk.run()) != nil {
                mk.waitUntilExit()
                for (name, label) in [("evil-path.zip", "chemin avec « .. »"), ("abs-path.zip", "chemin absolu"), ("link.zip", "lien symbolique")] {
                    var threw = false
                    do { try ModelStore.extract(zip: hostile.appendingPathComponent(name), into: hostile.appendingPathComponent("out-" + name)) } catch { threw = true }
                    check(threw, "archive de modèle : \(label) refusé")
                }
                check(!FileManager.default.fileExists(atPath: absName) && !FileManager.default.fileExists(atPath: tmp.appendingPathComponent("mslice-evil-parent.txt").path), "archive de modèle : rien écrit hors du dossier de travail")
                var fine = false
                do { try ModelStore.extract(zip: hostile.appendingPathComponent("ok.zip"), into: hostile.appendingPathComponent("out-ok")); fine = FileManager.default.fileExists(atPath: hostile.appendingPathComponent("out-ok/a.txt").path) } catch {}
                check(fine, "archive de modèle : archive saine décompressée (contrôle)")
            } else { check(false, "fabrication des archives hostiles (python3)") }
            check(ModelFiles.allowed(URL(string: "https://example.com/m.bin")!) && ModelFiles.allowed(URL(string: "http://127.0.0.1:1/m")!) && !ModelFiles.allowed(URL(string: "http://example.com/m.bin")!) && !ModelFiles.allowed(URL(string: "ftp://example.com/m")!) && !ModelFiles.allowed(URL(string: "file:///etc/passwd")!), "modèle optionnel : HTTPS seulement (HTTP uniquement vers ce Mac)")
            let cat = ModelCatalog.characters
            check(cat.available && cat.kind == .coreMLArchive && cat.url.map(ModelFiles.allowed) == true && cat.url?.scheme == "https" && cat.sha256?.count == 64 && cat.sha256 == cat.sha256?.lowercased() && cat.sizeMB > 0, "modèle des personnages : catalogue renseigné (HTTPS, SHA-256, archive Core ML, \(cat.sizeMB) Mo)")
        }

        // 10. personnages : index des visages, suivis, regroupement, corrections, requêtes (données synthétiques à vérité connue)
        do {
            struct Rng: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }
            var rng = Rng(s: 42)
            func gauss() -> Float { let u1 = Float.random(in: 1e-6 ..< 1, using: &rng), u2 = Float.random(in: 0 ..< 1, using: &rng); return (-2 * logf(u1)).squareRoot() * cosf(2 * .pi * u2) }
            func unit(_ v: [Float]) -> [Float] { let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot(); return v.map { $0 / n } }
            func noise() -> [Float] { unit((0 ..< FaceIndex.dim).map { _ in gauss() }) }
            let centers = (0 ..< 3).map { _ in noise() }
            let twinCenter = unit(zip(centers[0], noise()).map { $0 + 0.25 * $1 })        // presque la même personne que la 0, mais dans les mêmes images
            // (instant, vérité) : 0 et son sosie aux secondes 2-7 et 32-36 ; 1 aux secondes 12-17 et 42-46 ; 2 aux secondes 22-27 et 52-56
            var rows: [(Double, Int)] = []
            for s in [2, 3, 4, 5, 6, 7, 32, 33, 34, 35, 36] { rows.append((Double(s), 0)); rows.append((Double(s), 3)) }
            for s in [12, 13, 14, 15, 16, 17, 42, 43, 44, 45, 46] { rows.append((Double(s), 1)) }
            for s in [22, 23, 24, 25, 26, 27, 52, 53, 54, 55, 56] { rows.append((Double(s), 2)) }
            rows.sort { ($0.0, $0.1) < ($1.0, $1.1) }
            rows.append((60, 4))                                                      // un visage isolé
            var f = FaceIndex(duration: 70)
            f.modelSHA = ModelCatalog.characters.sha256 ?? ""
            for (k, r) in rows.enumerated() {
                let c = r.1 < 3 ? centers[r.1] : (r.1 == 3 ? twinCenter : noise())
                let v = unit(zip(c, noise()).map { $0 + 0.5 * $1 })
                let q = FaceIndex.quantize(v)
                f.t.append(Float(r.0)); f.px.append(120); f.emb += q.q; f.embScale.append(q.scale)
                let x: Float = r.1 == 3 ? 0.65 : 0.2 + 0.002 * Float(k % 20)
                f.box += [x, 0.3, 0.15, 0.25]
            }
            let truth = rows.map(\.1)
            let cuts: [Double] = [10, 20, 30, 40, 50, 58]
            f.track = FaceClustering.tracks(f, cuts: cuts)
            f.group = FaceClustering.cluster(f)
            f.nextGroup = (f.group.max() ?? -1) + 1
            let groups = Dictionary(grouping: (0 ..< f.count).filter { f.group[$0] >= 0 }, by: { f.group[$0] })
            let pure = groups.values.allSatisfy { Set($0.map { truth[$0] }).count == 1 }
            check(groups.count == 4 && pure && groups.values.allSatisfy { $0.count == 11 }, "personnages : 4 groupes de 11 visages, chacun d'une seule personne, sosie séparé grâce à la contrainte d'image (\(groups.count) groupes, purs : \(pure))")
            check(f.group.last == -1, "personnages : un visage isolé n'est pas un personnage")
            check(Set(f.track).count <= 12 && f.track[0] == f.track[2], "suivis : les visages voisins d'un même plan sont réunis (\(Set(f.track).count) suivis)")
            var mini = FaceIndex(duration: 20)
            for s in [9.0, 10.0] { let q = FaceIndex.quantize(centers[0]); mini.t.append(Float(s)); mini.px.append(100); mini.emb += q.q; mini.embScale.append(q.scale); mini.box += [0.2, 0.3, 0.15, 0.25] }
            check(FaceClustering.tracks(mini, cuts: []) == [0, 0] && FaceClustering.tracks(mini, cuts: [10]) == [0, 1], "suivis : une coupure entre deux images sépare les suivis")
            let q0 = FaceIndex.quantize(centers[1]); var restored = f; restored.emb = q0.q + Array(f.emb.dropFirst(FaceIndex.dim)); restored.embScale[0] = q0.scale
            let cosQ = zip(restored.vector(0), centers[1]).reduce(0) { $0 + $1.0 * $1.1 }
            check(cosQ > 0.999, "empreintes : quantification sur 8 bits sans perte sensible (cosinus \(String(format: "%.5f", cosQ)))")

            let stats = f.characters()
            check(stats.count == 4 && stats.allSatisfy { $0.appearances == 2 && abs($0.seconds - 11) < 0.01 }, "personnages : 4, chacun apparaît 11 s en 2 passages \(stats.map { "\($0.id):\(f1($0.seconds))" })")
            let g0 = f.group[0], g1 = f.group[truth.firstIndex(of: 1)!]
            // requêtes : le Finder comprend « person: »
            var base = AnalysisIndex(duration: 70); base.hasVideo = true; base.cuts = cuts
            base.sceneOffsets = [0] + [Int32](repeating: 0, count: 140)
            let fnd = Finder(base, faces: f)
            var pq = FindQuery(terms: [FindTerm(kind: .person, key: String(g1))]); pq.wholeShots = false
            let pr = fnd.run(pq)
            check(pr.passages.count == 2 && abs(pr.passages[0].start - 11.2) < 0.01 && abs(pr.passages[0].end - 17.8) < 0.01 && abs(pr.passages[1].start - 41.2) < 0.01, "requête personnage : deux passages (marge 0,3 s) \(pr.passages.map { "\(f1($0.start))→\(f1($0.end))" })")
            pq.wholeShots = true
            let pw = fnd.run(pq)
            check(pw.passages.count == 2 && pw.passages[0].start == 10 && pw.passages[0].end == 20 && pw.passages[1].start == 40 && pw.passages[1].end == 50, "requête personnage en plans entiers : calée sur les coupures \(pw.passages.map { "\(f1($0.start))→\(f1($0.end))" })")
            var xq = FindQuery(terms: [FindTerm(kind: .person, key: String(g1)), FindTerm(kind: .person, key: String(g0), exclude: true)]); xq.wholeShots = false
            check(fnd.run(xq).passages.count == 2 && fnd.knows(FindTerm(kind: .person, key: String(g1))) && !fnd.knows(FindTerm(kind: .person, key: "99")), "requête personnage SAUF un autre : sans recouvrement, rien d'écarté ; personnage inconnu signalé")
            check(FindTerm.parse("person:3")?.token == "person:3" && FindTerm.parse("person:x") == nil && FindTerm.parse("person:-1") == nil, "critère person: 1 entier positif, rien d'autre")

            // corrections : nom, fusion, séparation, écart
            var e = f
            e.rename(g0, to: "A\nB\u{7}" + String(repeating: "x", count: 60))
            check(e.names[g0].map { !$0.contains("\n") && !$0.contains("\u{7}") && $0.count == 40 } == true, "nom : caractères de contrôle retirés, 40 caractères au plus")
            e.rename(g0, to: "  "); check(e.names[g0] == nil, "nom vide : le personnage redevient anonyme")
            e.rename(g1, to: "Alice")
            e.merge(g1, into: g0)
            check(e.names[g0] == "Alice" && e.names[g1] == nil && e.characters().count == 3 && e.characters().first?.faces == 22, "fusion : visages réunis, nom gardé")
            let moved = e.split(g0)
            let sets = Dictionary(grouping: (0 ..< e.count).filter { e.group[$0] == g0 || e.group[$0] == moved }, by: { e.group[$0] })
            check(moved != nil && sets.values.allSatisfy { Set($0.map { truth[$0] }).count == 1 } && sets.count == 2, "séparation : la fusion malheureuse se défait selon les personnes")
            var single = FaceIndex(duration: 10); let sq = FaceIndex.quantize(centers[2])
            for s in 0 ..< 4 { single.t.append(Float(s)); single.px.append(90); single.emb += sq.q; single.embScale.append(sq.scale); single.box += [0.2, 0.3, 0.15, 0.25] }
            single.track = [Int32](repeating: 0, count: 4); single.group = [Int32](repeating: 0, count: 4); single.nextGroup = 1
            check(single.split(0) == nil, "séparation : un seul suivi, rien à séparer")
            e.hide(g0); check(!e.characters().contains { $0.id == g0 } && !Finder(base, faces: e).knows(FindTerm(kind: .person, key: String(g0))), "personnage écarté : disparu de la liste et des requêtes")

            // sérialisation
            if let d = f.serialized(), let back = FaceIndex(serialized: d) {
                check(back.t == f.t && back.group == f.group && back.track == f.track && back.emb == f.emb && back.box == f.box && back.modelSHA == f.modelSHA, "index des visages : aller-retour sans perte (\(d.count) octets pour \(f.count) visages)")
                var cut = d; cut.removeLast(60)
                check(FaceIndex(serialized: cut) == nil && FaceIndex(serialized: Data("rien".utf8)) == nil, "index des visages tronqué ou illisible : refusé")
                var bad = f; bad.group[3] = 500
                check(bad.serialized().flatMap { FaceIndex(serialized: $0) } == nil, "index des visages incohérent (groupe hors table) : refusé")
                var bad2 = f; bad2.box[1] = .nan
                check(bad2.serialized().flatMap { FaceIndex(serialized: $0) } == nil, "index des visages avec une valeur non finie : refusé")
                var bad3 = f; bad3.t.swapAt(0, 20)
                check(bad3.serialized().flatMap { FaceIndex(serialized: $0) } == nil, "index des visages dont les instants ne sont pas triés : refusé")
            } else { check(false, "index des visages : sérialisation") }
        }

        // 12. voix : index, regroupement, liens avec les visages, critères « parle » / « seul » (données synthétiques à vérité connue)
        do {
            struct Rng: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }
            var rng = Rng(s: 7)
            func gauss() -> Float { let u1 = Float.random(in: 1e-6 ..< 1, using: &rng), u2 = Float.random(in: 0 ..< 1, using: &rng); return (-2 * logf(u1)).squareRoot() * cosf(2 * .pi * u2) }
            func unit(_ v: [Float]) -> [Float] { let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot(); return v.map { $0 / n } }
            func noise() -> [Float] { unit((0 ..< VoiceIndex.dim).map { _ in gauss() }) }
            let centers = (0 ..< 3).map { _ in noise() }
            // 3 voix : A parle 0-12 et 40-48, B 14-26 et 50-58, C 28-38 ; 20 s de silence en 60-80 ; une fenêtre isolée (D) à 85
            let speech: [(ClosedRange<Double>, Int)] = [(0 ... 12, 0), (14 ... 26, 1), (28 ... 38, 2), (40 ... 48, 0), (50 ... 58, 1)]
            var v = VoiceIndex(duration: 90)
            v.modelSHA = ModelCatalog.voices.sha256 ?? ""
            var truth: [Int] = []
            for (range, who) in speech {
                var t = range.lowerBound
                while t <= range.upperBound - VoiceIndex.window + 1e-6 {
                    let e = FaceIndex.quantize(unit(zip(centers[who], noise()).map { $0 + 0.6 * $1 }))
                    v.t.append(Float(t)); v.emb += e.q; v.embScale.append(e.scale); truth.append(who); t += VoiceIndex.hop
                }
            }
            let lone = FaceIndex.quantize(noise()); v.t.append(85); v.emb += lone.q; v.embScale.append(lone.scale); truth.append(3)
            v.group = VoiceClustering.cluster(v); v.nextGroup = (v.group.max() ?? -1) + 1
            let groups = Dictionary(grouping: (0 ..< v.count).filter { v.group[$0] >= 0 }, by: { v.group[$0] })
            let pure = groups.values.allSatisfy { Set($0.map { truth[$0] }).count == 1 }
            check(groups.count == 3 && pure, "voix : 3 voix, chacune d'une seule personne, prises de parole séparées par des silences réunies (\(groups.count) groupes, purs : \(pure))")
            check(v.group.last == -1, "voix : une fenêtre isolée n'est pas une voix")
            let st = v.voices()
            check(st.count == 3 && st.allSatisfy { $0.turns == 2 || $0.turns == 1 } && Set(st.map(\.id)).count == 3, "voix : liste du plus long au plus court \(st.map { "\($0.id):\(f1($0.seconds)) s/\($0.turns)" })")
            let a = v.group[0]
            let ivA = v.intervals(of: a)
            check(ivA.count == 2 && abs(ivA[0].start) < 1 && ivA[0].end > 10 && ivA[0].end < 13.5 && ivA[1].start > 39 && ivA[1].end < 49.5, "voix : plages de la voix A \(ivA.map { "\(f1($0.start))-\(f1($0.end))" })")
            // sérialisation : aller-retour, fichier trafiqué refusé
            var named = v; named.rename(a, to: "Alice"); named.link[a] = 5
            if let d = named.serialized(), let back = VoiceIndex(serialized: d) {
                check(back.group == named.group && back.t == named.t && back.names[a] == "Alice" && back.link[a] == 5 && back.emb == named.emb, "voix : enregistrement et relecture identiques (\(d.count / 1024) Ko)")
                var bad = named; bad.group[0] = 99
                check(bad.serialized().flatMap(VoiceIndex.init(serialized:)) == nil, "voix : groupe hors plage refusé à la relecture")
                var bad2 = named; bad2.t[1] = bad2.t[0] - 5
                check(bad2.serialized().flatMap(VoiceIndex.init(serialized:)) == nil, "voix : instants non triés refusés à la relecture")
            } else { check(false, "voix : sérialisation") }
            check(VoiceIndex(serialized: Data("not a plist".utf8)) == nil, "voix : fichier illisible refusé")
            var m = v; let b = m.group[truth.firstIndex(of: 1)!]
            m.link[b] = 1; m.merge(b, into: a)
            check(m.voices().count == 2 && m.link[a] == 1 && m.link[b] == nil, "voix : réunir deux voix garde le lien et vide l'autre")

            // liens voix ↔ visages : A est seul à l'écran (personnage 0) pendant qu'elle parle ; B parle hors champ puis apparaît (personnage 1) en groupe
            var f = FaceIndex(duration: 90); f.step = 1
            func face(_ t: Double, _ g: Int32) { let q = FaceIndex.quantize(noise()); f.t.append(Float(t)); f.box += [0.2, 0.2, 0.2, 0.3]; f.px.append(120); f.track.append(Int32(f.t.count)); f.group.append(g); f.emb += q.q; f.embScale.append(q.scale) }
            for s in stride(from: 1.0, to: 12.0, by: 1.0) { face(s, 0) }                               // le personnage 0 seul pendant la voix A
            for s in stride(from: 41.0, to: 48.0, by: 1.0) { face(s, 0) }
            for s in stride(from: 30.0, to: 38.0, by: 1.0) { face(s, 1); face(s, 0) }                  // pendant la voix C : deux personnages à l'écran
            f.nextGroup = 2
            let links = VoiceLinking.link(v, faces: f)
            check(links[a] == 0 && links.count == 1, "liens : la voix A est liée au personnage 0 ; une voix hors champ ou en groupe n'est liée à personne \(links)")

            // le Finder : voice:, speaks:, alone:
            var base = AnalysisIndex(duration: 90); base.hasVideo = true; base.hasAudio = true
            base.sceneOffsets = [0] + [Int32](repeating: 0, count: 180)
            var vl = v; vl.link = links
            let fnd = Finder(base, faces: f, voices: vl)
            var q = FindQuery(terms: [FindTerm(kind: .voice, key: String(a))]); q.wholeShots = false
            let rv = fnd.run(q)
            check(rv.passages.count == 2 && abs(rv.keptSeconds - 20) < 4, "recherche : voice:A → 2 passages, \(f1(rv.keptSeconds)) s")
            q = FindQuery(terms: [FindTerm(kind: .speaks, key: "0")]); q.wholeShots = false
            check(fnd.run(q).passages.count == 2 && fnd.knows(FindTerm(kind: .speaks, key: "0")) && !fnd.knows(FindTerm(kind: .speaks, key: "1")), "recherche : speaks:0 = la voix liée au personnage 0 ; speaks:1 inconnu (aucune voix liée)")
            q = FindQuery(terms: [FindTerm(kind: .alone, key: "0")]); q.wholeShots = false
            let ra = fnd.run(q)
            q = FindQuery(terms: [FindTerm(kind: .person, key: "0")]); q.wholeShots = false
            let rp = fnd.run(q)
            check(ra.keptSeconds < rp.keptSeconds - 5 && ra.passages.count == 2, "recherche : alone:0 exclut les moments où un autre personnage est à l'écran (\(f1(ra.keptSeconds)) s au lieu de \(f1(rp.keptSeconds)) s)")
            check(FindTerm.parse("voice:3")?.kind == .voice && FindTerm.parse("alone:2")?.kind == .alone && FindTerm.parse("speaks:x") == nil && FindTerm.parse("voice:-1") == nil, "critères : voice:, alone:, speaks: reconnus, valeurs fausses refusées")
            let vc = ModelCatalog.voices
            check(vc.available && vc.kind == .coreMLArchive && vc.url?.scheme == "https" && vc.sha256?.count == 64 && vc.sha256 == vc.sha256?.lowercased(), "modèle des voix : catalogue renseigné (HTTPS, SHA-256, archive Core ML, \(vc.sizeMB) Mo)")
            // caractéristiques sonores : 1,515 s donne 150 trames, moyenne nulle ; trop court refusé
            let tone = (0 ..< VoiceFeatures.windowSamples).map { Float(0.3 * sin(Double($0) * 2 * .pi * 440 / VoiceFeatures.rate)) }
            let fb = tone.withUnsafeBufferPointer { VoiceFeatures.fbank($0) }
            let meanAbs = fb.map { f in (0 ..< VoiceFeatures.bins).map { b in abs((0 ..< VoiceFeatures.frames).reduce(Float(0)) { $0 + f[$1 * VoiceFeatures.bins + b] }) }.max() ?? 1 } ?? 1
            check(fb?.count == VoiceFeatures.frames * VoiceFeatures.bins && meanAbs < 1e-2 && fb!.allSatisfy { $0.isFinite }, "caractéristiques : 150 × 80 valeurs finies, moyenne retirée")
            check(tone.prefix(1000).withUnsafeBufferPointer { VoiceFeatures.fbank($0) } == nil, "caractéristiques : signal trop court refusé")
        }

        // 11. reconnaissance réelle des personnages (le zip du modèle est donné par MSLICE_TEST_MODEL_ZIP ; installé dans un dossier d'essai)
        if let zipPath = ProcessInfo.processInfo.environment["MSLICE_TEST_MODEL_ZIP"], FileManager.default.fileExists(atPath: zipPath) {
            let spec = ModelCatalog.characters
            let copy = tmp.appendingPathComponent("model-copy.zip")
            try? FileManager.default.copyItem(atPath: zipPath, toPath: copy.path)
            do { try await ModelStore.installFile(copy, spec: spec, sha256: spec.sha256 ?? "") } catch { print("INFO   installation du modèle réel : \(error)") }
            check(ModelFiles.verified(spec), "modèle des personnages : installé et vérifié dans le dossier d'essai")
            AnalysisStore.save(index, for: info)                     // les coupures servent aux suivis
            FaceStore.remove(info)
            let before = ProcessMemory.footprintMB()
            let faceBox = PeakBox()
            let t0 = Date()
            let faces = await AnalysisRunner.runFaces(info, job: AnalysisJob(), progress: { faceBox.note($0.memoryMB, $0) })
            let secs = Date().timeIntervalSince(t0)
            if let faces {
                let chars = faces.characters()
                let grouped = faces.group.filter { $0 >= 0 }.count
                print("INFO   personnages : \(faces.count) visages, \(grouped) rattachés à \(chars.count) personnages, \(faces.track.max().map { Int($0) + 1 } ?? 0) suivis, calcul interne \(f1(faces.seconds)) s")
                for c in chars.prefix(8) { print("INFO     personnage \(c.id + 1) : \(c.faces) visages, \(f1(c.seconds)) s, \(c.appearances) apparitions") }
                check(secs < 180, "reconnaissance des personnages : \(f1(secs)) s pour \(Fmt.time(info.duration, decimals: false)) de vidéo (critère 180 s)")
                check(faceBox.peak < 300, "reconnaissance des personnages : pic de mémoire du processus \(f1(faceBox.peak)) Mo, modèle chargé compris (critère 300 Mo ; rendus à la fin du processus)")
                check(chars.count >= 10 && grouped * 2 > faces.count, "reconnaissance des personnages : \(chars.count) personnages (au moins 10), \(grouped) visages sur \(faces.count) rattachés")
                var clash = 0
                for (_, idx) in Dictionary(grouping: (0 ..< faces.count).filter { faces.group[$0] >= 0 }, by: { faces.group[$0] }) { clash += idx.count - Set(idx.map { faces.t[$0] }).count }
                check(clash == 0, "reconnaissance des personnages : jamais deux visages d'une même image dans un personnage (\(clash) conflit(s))")
                check(FaceStore.load(info)?.group == faces.group && FaceStore.load(info)?.modelSHA == spec.sha256, "reconnaissance des personnages : résultat enregistré, lié au modèle")
                let after = ProcessMemory.footprintMB()
                check(after < before + 8, "reconnaissance des personnages : l'appli ne garde rien (mémoire \(f1(before)) → \(f1(after)) Mo)")
                var ren = faces; ren.rename(chars[0].id, to: "Essai")
                FaceStore.save(ren, for: info)
                check(FaceStore.load(info)?.names[chars[0].id] == "Essai", "personnages : nom donné relu depuis le disque")
            } else { check(false, "reconnaissance des personnages : échec") }
            // annulation en cours de route : rien n'est enregistré
            FaceStore.remove(info)
            let cj = AnalysisJob()
            let run = Task { await AnalysisRunner.runFaces(info, job: cj, progress: { _ in }) }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let tc = Date(); cj.cancel(); let cancelled = await run.value
            check(cancelled == nil && Date().timeIntervalSince(tc) < 6 && FaceStore.load(info) == nil, "reconnaissance des personnages : annulation en \(f1(Date().timeIntervalSince(tc))) s, rien d'enregistré")
            // un modèle altéré n'est jamais chargé
            let weights = ModelFiles.compiled(spec).appendingPathComponent("weights/weight.bin")
            if var w = try? Data(contentsOf: weights), !w.isEmpty {
                w[w.count / 3] ^= 0xff; try? w.write(to: weights)
                let bad = await AnalysisRunner.runFaces(info, job: AnalysisJob(), progress: { _ in })
                check(bad == nil && FaceStore.load(info) == nil && !ModelFiles.verified(spec), "modèle altéré : refusé avant chargement, aucune reconnaissance")
            }
            try? FileManager.default.removeItem(at: ModelFiles.folder(spec))
            FaceStore.remove(info); AnalysisStore.remove(info)
        } else { print("INFO   reconnaissance réelle des personnages non essayée (MSLICE_TEST_MODEL_ZIP absent)") }

        // 12b. export par protagoniste : un fichier fusionné par groupe, nommé « <fichier> – <nom> », rien d'écrasé
        if info.duration > 45 {
            let out = tmp.appendingPathComponent("proto-export", isDirectory: true)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            var o = ExportOptions(); o.passthrough = false; o.format = info.isAudioOnly ? .m4a : .mp4; o.merge = true; o.folder = out.path
            let kf = Probe.keyframes(info)
            let groups: [(String, [Segment])] = [("Alice", [Segment(start: 4, end: 8), Segment(start: 20, end: 23)]), ("Bob / 2", [Segment(start: 30, end: 34)])]
            var outs: [OutputItem] = []
            for g in groups { outs += Planner.outputs(info: info, segments: g.1, opts: o, keyframes: kf, base: nil, mergeName: "\(info.url.deletingPathExtension().lastPathComponent) – \(g.0)") }
            let names = outs.map { $0.url.deletingPathExtension().lastPathComponent }
            check(outs.count == 2 && names[0].hasSuffix(" – Alice") && names[1].hasSuffix(" – Bob - 2") && outs[0].segments.count == 2, "export par protagoniste : 2 fichiers, un par groupe, noms sûrs \(names.map { String($0.suffix(12)) })")
            let run = await MainActor.run { ExportRun() }
            await MainActor.run { run.start(info: info, outputs: outs, opts: o, keyframes: kf) }
            while !(await MainActor.run { run.finished }) { try? await Task.sleep(nanoseconds: 50_000_000) }
            let d0 = Probe.read(outs[0].url)?.duration ?? 0, d1 = Probe.read(outs[1].url)?.duration ?? 0
            check(abs(d0 - 7) < 0.6 && abs(d1 - 4) < 0.6, "export par protagoniste : durées \(f1(d0)) s (7 attendues, deux morceaux fusionnés) et \(f1(d1)) s (4 attendues)")
            let again = Planner.outputs(info: info, segments: groups[0].1, opts: o, keyframes: kf, base: nil, mergeName: "\(info.url.deletingPathExtension().lastPathComponent) – Alice")
            check(again[0].url != outs[0].url, "export par protagoniste : un fichier existant n'est jamais écrasé (\(again[0].url.lastPathComponent.suffix(16)))")
        }

        // 12c. suggestions de fusion : deux groupes d'une même personne (jamais ensemble à l'écran) remontent ; un sosie présent dans les mêmes images, non
        do {
            struct Rng: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }
            var rng = Rng(s: 99)
            func gauss() -> Float { let u1 = Float.random(in: 1e-6 ..< 1, using: &rng), u2 = Float.random(in: 0 ..< 1, using: &rng); return (-2 * logf(u1)).squareRoot() * cosf(2 * .pi * u2) }
            func unit(_ v: [Float]) -> [Float] { let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot(); return v.map { $0 / n } }
            func noise() -> [Float] { unit((0 ..< FaceIndex.dim).map { _ in gauss() }) }
            let base = noise(), other = noise()
            var f = FaceIndex(duration: 60); f.step = 1
            func add(_ t: Double, _ g: Int32, _ c: [Float]) { let q = FaceIndex.quantize(unit(zip(c, noise()).map { $0 + 0.45 * $1 })); f.t.append(Float(t)); f.box += [0.2, 0.2, 0.2, 0.3]; f.px.append(100); f.track.append(Int32(f.t.count)); f.group.append(g); f.emb += q.q; f.embScale.append(q.scale) }
            for t in 1 ... 8 { add(Double(t), 0, base) }                       // groupe 0 : la personne A, secondes 1-8
            for t in 21 ... 28 { add(Double(t), 1, base) }                     // groupe 1 : la même personne A plus tard
            for t in 1 ... 8 { add(Double(t) + 0.0, 2, other) }                // groupe 2 : une autre personne, dans les mêmes images que le groupe 0
            for t in 41 ... 48 { add(Double(t), 3, other) }                    // groupe 3 : l'autre personne plus tard
            f.nextGroup = 4
            let sug = FaceClustering.suggestions(f, minSimilarity: 0.3)
            let pairs = Set(sug.map { Set([$0.a, $0.b]) })
            check(pairs == [[0, 1], [2, 3]], "suggestions : les groupes d'une même personne remontent, jamais deux groupes présents dans les mêmes images \(sug.map { "\($0.a)-\($0.b):\(String(format: "%.2f", $0.similarity))" })")
            f.hidden.insert(1)
            check(FaceClustering.suggestions(f, minSimilarity: 0.3).map { Set([$0.a, $0.b]) } == [[2, 3]], "suggestions : un personnage écarté n'est plus proposé")
        }

        // 13. reconnaissance réelle des voix (le zip du modèle est donné par MSLICE_TEST_VOICE_ZIP ; installé dans le dossier d'essai)
        if let zipPath = ProcessInfo.processInfo.environment["MSLICE_TEST_VOICE_ZIP"], FileManager.default.fileExists(atPath: zipPath), info.audio != nil {
            let spec = ModelCatalog.voices
            let copy = tmp.appendingPathComponent("voice-model-copy.zip")
            try? FileManager.default.copyItem(atPath: zipPath, toPath: copy.path)
            do { try await ModelStore.installFile(copy, spec: spec, sha256: spec.sha256 ?? "") } catch { print("INFO   installation du modèle de voix : \(error)") }
            check(ModelFiles.verified(spec), "modèle des voix : installé et vérifié dans le dossier d'essai")
            AnalysisStore.save(index, for: info)                     // l'analyse sonore (parole) restreint les fenêtres
            VoiceStore.remove(info)
            try? await Task.sleep(nanoseconds: 2_000_000_000)         // laisse les essais précédents rendre leur mémoire
            let before = ProcessMemory.footprintMB()
            let box = PeakBox()
            let t0 = Date()
            let voices = await AnalysisRunner.runVoices(info, job: AnalysisJob(), progress: { box.note($0.memoryMB, $0) })
            let secs = Date().timeIntervalSince(t0)
            print("INFO   mémoire de l'appli juste après la reconnaissance des voix : \(f1(ProcessMemory.footprintMB())) Mo")
            if let voices {
                let list = voices.voices()
                print("INFO   voix : \(voices.count) fenêtres de parole, \(list.count) voix, calcul interne \(f1(voices.seconds)) s")
                for s in list.prefix(8) { print("INFO     voix \(s.id + 1) : \(f1(s.seconds)) s, \(s.turns) prises de parole") }
                check(secs < max(30, info.duration / 4), "reconnaissance des voix : \(f1(secs)) s pour \(Fmt.time(info.duration, decimals: false)) (critère : un quart de la durée)")
                check(box.peak < 250, "reconnaissance des voix : pic de mémoire du processus \(f1(box.peak)) Mo, modèle chargé compris (critère 250 Mo)")
                check(!list.isEmpty && voices.group.filter { $0 >= 0 }.count * 2 > voices.count, "reconnaissance des voix : \(list.count) voix, \(voices.group.filter { $0 >= 0 }.count) fenêtres sur \(voices.count) rattachées")
                check(VoiceStore.load(info)?.group == voices.group && VoiceStore.load(info)?.modelSHA == spec.sha256, "reconnaissance des voix : résultat enregistré, lié au modèle")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                check(ProcessMemory.footprintMB() < before + 8, "reconnaissance des voix : l'appli ne garde rien (mémoire \(f1(before)) → \(f1(ProcessMemory.footprintMB())) Mo)")
            } else { check(false, "reconnaissance des voix : échec") }
            VoiceStore.remove(info)
            let cj = AnalysisJob()
            let run = Task { await AnalysisRunner.runVoices(info, job: cj, progress: { _ in }) }
            try? await Task.sleep(nanoseconds: 300_000_000)
            let tc = Date(); cj.cancel(); let cancelled = await run.value
            check((cancelled == nil && VoiceStore.load(info) == nil) || cancelled != nil, "reconnaissance des voix : annulation en \(f1(Date().timeIntervalSince(tc))) s")
            let weights = ModelFiles.compiled(spec).appendingPathComponent("weights/weight.bin")
            if var w = try? Data(contentsOf: weights), !w.isEmpty {
                w[w.count / 3] ^= 0xff; try? w.write(to: weights)
                VoiceStore.remove(info)
                let bad = await AnalysisRunner.runVoices(info, job: AnalysisJob(), progress: { _ in })
                check(bad == nil && VoiceStore.load(info) == nil && !ModelFiles.verified(spec), "modèle de voix altéré : refusé avant chargement, aucune reconnaissance")
            }
            try? FileManager.default.removeItem(at: ModelFiles.folder(spec))
            VoiceStore.remove(info); AnalysisStore.remove(info)
        } else { print("INFO   reconnaissance réelle des voix non essayée (MSLICE_TEST_VOICE_ZIP absent)") }

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
