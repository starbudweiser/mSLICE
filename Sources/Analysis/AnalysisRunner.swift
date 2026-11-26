// mSLICE — lance l'analyse dans un processus séparé (`mslice-mcp --analyze <fichier>`, livré dans l'appli).
//
// Vision et SoundAnalysis chargent leurs modèles neuronaux (≈ 30 Mo) et ne les rendent pas : dans le processus de l'appli, cette mémoire resterait
// occupée après l'analyse. Dans un processus à part, tout est rendu au système quand il se termine (rien au repos), et un plantage éventuel d'un
// modèle d'Apple ne touche pas l'appli. L'appli reçoit la progression par une ligne JSON ; le résultat est enregistré par le processus d'analyse
// dans `AnalysisStore`, puis relu. Annulation et pause passent par l'entrée standard du processus (« cancel », « pause », « resume »).
// Sans exécutable auxiliaire (essais, ou `mslice-mcp` lui-même), l'analyse tourne dans le processus courant.
import Foundation

enum AnalysisRunner {
    /// `mslice-mcp` à côté de l'exécutable de l'appli ; nil dans `mslice-mcp` lui-même ou si l'exécutable est absent.
    static func helper() -> URL? {
        if ProcessInfo.processInfo.environment["MSLICE_ANALYZE_IN_PROCESS"] == "1" { return nil }
        guard let exe = Bundle.main.executableURL, exe.lastPathComponent != "mslice-mcp" else { return nil }
        let h = exe.deletingLastPathComponent().appendingPathComponent("mslice-mcp")
        return FileManager.default.isExecutableFile(atPath: h.path) ? h : nil
    }

    private final class Child: @unchecked Sendable {
        let lock = NSLock()
        var buffer = Data(), done = false, error: String?
        var finished = false
    }

    static func run(_ info: MediaInfo, job: AnalysisJob, progress: @escaping @Sendable (AnalysisProgress) -> Void) async -> AnalysisIndex? {
        guard let helper = helper() else { return await Analyzer.run(info, job: job, progress: progress) }
        let base = AnalysisProgress(hasVideo: !info.isAudioOnly, hasAudio: info.audio != nil)
        guard await spawn(helper, ["--analyze", info.url.path], base: base, job: job, progress: progress) else { return nil }
        return AnalysisStore.load(info)
    }

    /// Reconnaissance des personnages (modèle optionnel installé) : même principe, dans `mslice-mcp --faces`.
    static func runFaces(_ info: MediaInfo, job: AnalysisJob, progress: @escaping @Sendable (AnalysisProgress) -> Void) async -> FaceIndex? {
        guard let helper = helper() else { return await FaceAnalyzer.run(info, job: job, progress: progress) }
        guard await spawn(helper, ["--faces", info.url.path], base: AnalysisProgress(hasVideo: true, hasAudio: false), job: job, progress: progress) else { return nil }
        return FaceStore.load(info)
    }

    /// Reconnaissance des voix (modèle optionnel installé) : même principe, dans `mslice-mcp --voices`.
    static func runVoices(_ info: MediaInfo, job: AnalysisJob, progress: @escaping @Sendable (AnalysisProgress) -> Void) async -> VoiceIndex? {
        guard let helper = helper() else { return await VoiceAnalyzer.run(info, job: job, progress: progress) }
        guard await spawn(helper, ["--voices", info.url.path], base: AnalysisProgress(hasVideo: true, hasAudio: false), job: job, progress: progress) else { return nil }
        return VoiceStore.load(info)
    }

    /// Transcription de la parole (macOS 26) dans `mslice-mcp --dialogues` ; le résultat passe par un fichier temporaire. nil si annulée ou impossible.
    static func runDialogues(_ info: MediaInfo, language: String, job: AnalysisJob, progress: @escaping @Sendable (AnalysisProgress) -> Void) async -> [DialogueLine]? {
        let raw = DialogueStore.rawURL(info)
        defer { try? FileManager.default.removeItem(at: raw) }
        guard let helper = helper() else {
            return await Transcriber.run(info, language: language, job: job) { f in var p = AnalysisProgress(hasVideo: true, hasAudio: false); p.images = f; p.imagesTime = f * info.duration; progress(p) }
        }
        guard await spawn(helper, ["--dialogues", info.url.path, language, raw.path], base: AnalysisProgress(hasVideo: true, hasAudio: false), job: job, progress: progress),
              let d = try? Data(contentsOf: raw), let lines = try? JSONDecoder().decode([DialogueLine].self, from: d) else { return nil }
        return lines
    }

    /// Lance le processus d'analyse, relaie sa progression, transmet l'annulation et la pause ; vrai s'il a terminé normalement.
    private static func spawn(_ helper: URL, _ arguments: [String], base: AnalysisProgress, job: AnalysisJob, progress: @escaping @Sendable (AnalysisProgress) -> Void) async -> Bool {
        await AnalysisSlot.shared.acquire()
        defer { Task { await AnalysisSlot.shared.release() } }
        if job.cancelled { return false }
        progress(base)
        let child = Child()
        let ok: Bool = await withCheckedContinuation { cont in
            let p = Process(); p.executableURL = helper; p.arguments = arguments
            let inp = Pipe(), out = Pipe()
            p.standardInput = inp; p.standardOutput = out; p.standardError = FileHandle.nullDevice
            p.qualityOfService = .utility
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; if d.isEmpty { return }
                child.lock.lock(); child.buffer.append(d)
                var lines: [Data] = []
                while let i = child.buffer.firstIndex(of: 10) { lines.append(child.buffer[child.buffer.startIndex ..< i]); child.buffer.removeSubrange(child.buffer.startIndex ... i) }
                child.lock.unlock()
                for l in lines {
                    guard let o = (try? JSONSerialization.jsonObject(with: l)) as? [String: Any] else { continue }
                    if o["done"] as? Bool == true { child.lock.lock(); child.done = true; child.lock.unlock() }
                    else if let e = o["error"] as? String { child.lock.lock(); child.error = e; child.lock.unlock() }
                    else {
                        var v = base
                        v.images = (o["i"] as? Double) ?? 0; v.sounds = (o["s"] as? Double) ?? 0; v.imagesTime = (o["t"] as? Double) ?? 0
                        v.soundsSeconds = (o["ss"] as? Double) ?? 0; v.paused = (o["p"] as? Bool) ?? false; v.memoryMB = (o["mb"] as? Double) ?? 0
                        progress(v)
                    }
                }
            }
            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                child.lock.lock(); child.finished = true; let ok = proc.terminationStatus == 0 && child.done; child.lock.unlock()
                cont.resume(returning: ok)
            }
            do { try p.run() } catch { cont.resume(returning: false); return }
            // surveillance : annulation (puis arrêt forcé si le processus tarde) et pause demandées par l'appli
            let write: @Sendable (String) -> Void = { s in try? inp.fileHandleForWriting.write(contentsOf: Data((s + "\n").utf8)) }
            let monitor = Thread {
                var paused = false, cancelSent: Date?
                while true {
                    child.lock.lock(); let fin = child.finished; child.lock.unlock()
                    if fin { break }
                    if job.cancelled {
                        if cancelSent == nil { cancelSent = Date(); write("cancel") }
                        else if Date().timeIntervalSince(cancelSent!) > 2 { p.terminate() }
                    }
                    let want = AnalysisGate.shared.paused
                    if want != paused { paused = want; write(want ? "pause" : "resume") }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                try? inp.fileHandleForWriting.close()
            }
            monitor.qualityOfService = .utility; monitor.start()
        }
        return ok && !job.cancelled
    }
}

/// Côté processus d'analyse (`mslice-mcp --analyze <fichier>`) : progression en JSON sur la sortie standard, ordres sur l'entrée standard.
enum AnalysisChild {
    static func main(path: String, faces: Bool = false, voices: Bool = false, clean: Bool = false) -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        func say(_ o: [String: Any]) {
            guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
            print(s); fflush(stdout)
        }
        guard let info = Probe.read(URL(fileURLWithPath: path)) else { say(["error": "unreadable file"]); exit(2) }
        let job = AnalysisJob()
        Thread.detachNewThread {
            while let l = readLine() {
                switch l { case "cancel": job.cancel(); case "pause": AnalysisGate.shared.paused = true; case "resume": AnalysisGate.shared.paused = false; default: break }
            }
            exit(3)                                        // l'appli a disparu : on s'arrête aussi
        }
        Task {
            let report: @Sendable (AnalysisProgress) -> Void = { p in
                say(["i": p.images, "s": p.sounds, "t": p.imagesTime, "ss": p.soundsSeconds, "p": p.paused, "mb": p.memoryMB])
            }
            let t0 = Date()
            let seconds: Double? = clean
                ? (await CleanVoice.build(info, job: job, slot: false, progress: { say(["s": $0]) }) ? Date().timeIntervalSince(t0) : nil)
                : voices
                ? await VoiceAnalyzer.run(info, job: job, slot: false, progress: report)?.seconds
                : faces
                ? await FaceAnalyzer.run(info, job: job, slot: false, progress: report)?.seconds
                : await Analyzer.run(info, job: job, slot: false, progress: report)?.seconds
            if let seconds { say(["done": true, "seconds": seconds]); exit(0) }
            say(["error": job.cancelled ? "cancelled" : "analysis failed"]); exit(job.cancelled ? 4 : 1)
        }
        dispatchMain()
    }
}
