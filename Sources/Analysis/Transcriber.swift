// mSLICE — transcription de la parole en répliques : `SpeechAnalyzer` + `SpeechTranscriber` de macOS 26 (sur l'appareil, rien n'est envoyé), sur l'audio 16 kHz mono
// que fabrique le ffmpeg embarqué. Les résultats arrivent par groupes de phrases (jusqu'à 12 s) : on les redécoupe en répliques avec les plages de temps par mot
// (ponctuation, pause de plus de 0,6 s, 12 s au plus). Tourne dans le processus séparé `mslice-mcp --dialogues` (comme l'analyse Trouver) : la mémoire des modèles
// de langue revient au système avec lui. Les ressources de langue d'Apple s'installent par `AssetInventory` seulement avec l'accord de l'utilisateur (côté appli).
// Sur macOS 14-15 la transcription n'existe pas : l'interface grise l'option.
import AVFoundation
import Foundation
import Speech

/// Un mot et sa plage de temps.
struct TimedWord: Equatable, Sendable { var text: String; var start: Double; var end: Double }

/// Découpage des mots en répliques (logique pure, essayée sans macOS 26).
enum Utterances {
    static let pause = 0.6
    static let maxDuration = 12.0
    static let minComma = 3.0                 // une virgule ne sert de point de coupe que si la réplique dure déjà autant

    static func split(_ words: [TimedWord]) -> [DialogueLine] {
        var out: [DialogueLine] = []
        var cur: [TimedWord] = []
        func flush(_ ws: [TimedWord]) {
            guard let f = ws.first, let l = ws.last else { return }
            let text = DialogueText.sanitize(ws.map(\.text).joined(separator: " "))
            guard text.contains(where: { $0.isLetter || $0.isNumber }), l.end > f.start else { return }
            out.append(DialogueLine(start: f.start, end: l.end, text: text))
        }
        for (i, w) in words.enumerated() {
            cur.append(w)
            let endsSentence = w.text.last.map { ".?!…".contains($0) } ?? false
            let gap = i + 1 < words.count ? words[i + 1].start - w.end : .infinity
            if endsSentence || gap > pause || i + 1 == words.count { flush(cur); cur = []; continue }
            if w.end - cur[0].start >= maxDuration {
                // coupe après la dernière virgule assez loin dans la réplique, sinon ici
                if let k = cur.lastIndex(where: { $0.text.last.map { ",;:".contains($0) } ?? false }), cur[k].end - cur[0].start >= minComma, k < cur.count - 1 {
                    flush(Array(cur[...k])); cur = Array(cur[(k + 1)...])
                } else { flush(cur); cur = [] }
            }
        }
        return out
    }
}

enum TranscriptionSupport {
    /// Vrai sur macOS 26 et plus.
    static var available: Bool { if #available(macOS 26.0, *) { true } else { false } }

    /// Langues proposées (code de langue de macOS).
    static let languages: [(code: String, label: String)] = [("fr-FR", "Français"), ("en-US", "English"), ("es-ES", "Español"), ("it-IT", "Italiano"), ("de-DE", "Deutsch")]

    enum AssetState: Sendable { case installed, needsDownload, unsupported, unavailable }

    /// Les ressources de langue sont-elles installées ? (Rien n'est téléchargé ici.)
    static func assetState(_ code: String) async -> AssetState {
        guard #available(macOS 26.0, *) else { return .unavailable }
        return await SpeechRunner.assetState(code)
    }

    /// Télécharge et installe les ressources de langue d'Apple : à n'appeler qu'avec l'accord de l'utilisateur.
    static func install(_ code: String) async -> Bool {
        guard #available(macOS 26.0, *) else { return false }
        return await SpeechRunner.install(code)
    }
}

enum Transcriber {
    /// Audio 16 kHz mono (WAV) du fichier, fabriqué par ffmpeg dans le dossier temporaire ; nil si le fichier n'a pas de son.
    static func extractAudio(_ info: MediaInfo) async -> URL? {
        guard info.audio != nil, let ff = Tools.ffmpeg else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-dlg-\(UUID().uuidString).wav")
        let r = await Run.exec(ff, ["-v", "error", "-y", "-nostdin", "-i", info.url.path, "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", tmp.path])
        guard r.status == 0 else { try? FileManager.default.removeItem(at: tmp); return nil }
        return tmp
    }

    /// Transcription complète d'un fichier en répliques ; nil si annulée, impossible (macOS < 26, ressources absentes, pas de son).
    static func run(_ info: MediaInfo, language: String, job: AnalysisJob, progress: @escaping @Sendable (Double) -> Void) async -> [DialogueLine]? {
        guard #available(macOS 26.0, *), let wav = await extractAudio(info) else { return nil }
        defer { try? FileManager.default.removeItem(at: wav) }
        if job.cancelled { return nil }
        guard let words = await SpeechRunner.words(wav: wav, language: language, duration: info.duration, job: job, progress: progress), !job.cancelled else { return nil }
        return Utterances.split(words)
    }
}

@available(macOS 26.0, *)
enum SpeechRunner {
    static func locale(_ code: String) async -> Locale? { await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: code)) }

    static func assetState(_ code: String) async -> TranscriptionSupport.AssetState {
        guard SpeechTranscriber.isAvailable, let loc = await locale(code) else { return .unsupported }
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == loc.identifier(.bcp47) }) { return .installed }
        return .needsDownload
    }

    static func install(_ code: String) async -> Bool {
        guard let loc = await locale(code) else { return false }
        let t = SpeechTranscriber(locale: loc, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        do {
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await req.downloadAndInstall() }
            return true
        } catch { return false }
    }

    /// Les mots du fichier avec leurs plages de temps ; nil si annulée ou si la langue n'est pas installée.
    static func words(wav: URL, language: String, duration: Double, job: AnalysisJob, progress: @escaping @Sendable (Double) -> Void) async -> [TimedWord]? {
        guard await assetState(language) == .installed, let loc = await locale(language), let file = try? AVAudioFile(forReading: wav) else { return nil }
        let transcriber = SpeechTranscriber(locale: loc, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let watcher = Task {
            while !Task.isCancelled { if job.cancelled { await analyzer.cancelAndFinishNow(); return }; try? await Task.sleep(nanoseconds: 100_000_000) }
        }
        defer { watcher.cancel() }
        let collector = Task<[TimedWord], Error> {
            var words: [TimedWord] = []
            for try await r in transcriber.results {
                words += timedWords(r.text)
                if let e = words.last?.end { progress(min(e / max(duration, 0.1), 1)) }
            }
            return words
        }
        do {
            if let last = try await analyzer.analyzeSequence(from: file) { try await analyzer.finalizeAndFinish(through: last) } else { await analyzer.cancelAndFinishNow() }
            let words = try await collector.value
            return job.cancelled ? nil : words.sorted { $0.start < $1.start }
        } catch { collector.cancel(); return nil }
    }

    /// Un mot par série de caractères portant une plage de temps ; le texte sans plage se colle au mot précédent.
    static func timedWords(_ text: AttributedString) -> [TimedWord] {
        var out: [TimedWord] = []
        for run in text.runs {
            let s = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            if let r = run.audioTimeRange, r.start.seconds.isFinite, r.end.seconds.isFinite {
                out.append(TimedWord(text: s, start: r.start.seconds, end: r.end.seconds))
            } else if !out.isEmpty {
                out[out.count - 1].text += (s.first.map { ".,;:!?…)".contains($0) } ?? false) ? s : " " + s
            }
        }
        return out
    }
}

/// Côté processus séparé : `mslice-mcp --dialogues <fichier> <langue> <sortie.json>` ; progression en JSON sur la sortie standard (« i » = part faite),
/// ordres « cancel » sur l'entrée standard, résultat écrit dans le fichier de sortie.
enum DialoguesChild {
    static func main(path: String, language: String, out: String) -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        func say(_ o: [String: Any]) {
            guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
            print(s); fflush(stdout)
        }
        guard let info = Probe.read(URL(fileURLWithPath: path)) else { say(["error": "unreadable file"]); exit(2) }
        let job = AnalysisJob()
        Thread.detachNewThread {
            while let l = readLine() { if l == "cancel" { job.cancel() } }
            exit(3)
        }
        Task {
            let lines = await Transcriber.run(info, language: language, job: job) { f in say(["i": f, "t": f * info.duration, "mb": ProcessMemory.footprintMB()]) }
            if let lines, let d = try? JSONEncoder().encode(lines), (try? d.write(to: URL(fileURLWithPath: out), options: .atomic)) != nil { say(["done": true, "n": lines.count]); exit(0) }
            say(["error": job.cancelled ? "cancelled" : "transcription failed"]); exit(job.cancelled ? 4 : 1)
        }
        dispatchMain()
    }
}
