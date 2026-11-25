// mSLICE — export des répliques en fichiers : un WAV par réplique (mono 48 kHz, voix seule en option) et un fichier SRT, dans un dossier « <nom> – dialogues »
// créé à côté de la vidéo (jamais d'écrasement : un numéro s'ajoute si le dossier existe). Aussi : noms des personnages lus sur disque (pour l'agent, sans l'appli).
// Sans interface : partagé avec `mslice-mcp`.
import Foundation

enum DialogueExport {
    /// 3723.5 → « 01:02:03,500 »
    static func srtTime(_ t: Double) -> String {
        let ms = Int((max(t, 0) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    /// SRT des répliques : « [Nom] texte » quand le personnage est connu (l'analyse des sous-titres de mSLICE relit ce format).
    static func srt(_ lines: [CastingLine]) -> String {
        var out = ""
        for (i, l) in lines.enumerated() {
            let name = l.character.flatMap { $0.isEmpty ? nil : "[\($0)] " } ?? ""
            out += "\(i + 1)\n\(srtTime(l.start)) --> \(srtTime(l.end))\n\(name)\(l.text)\n\n"
        }
        return out
    }

    /// Nom de fichier sûr : lettres, chiffres, espaces et tirets.
    static func safeName(_ s: String) -> String {
        let t = String(s.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : "_" }.prefix(40)).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "sans nom" : t
    }

    /// Dossier d'export neuf à côté de la vidéo.
    static func newFolder(for info: MediaInfo) -> URL {
        let dir = info.url.deletingLastPathComponent(), base = info.url.deletingPathExtension().lastPathComponent + " – dialogues"
        var u = dir.appendingPathComponent(base), n = 2
        while FileManager.default.fileExists(atPath: u.path) { u = dir.appendingPathComponent("\(base) \(n)"); n += 1 }
        return u
    }

    /// Écrit les WAV et le SRT ; rend le dossier. `isolate` : voix seule.
    static func write(_ info: MediaInfo, lines: [CastingLine], isolate: Bool, job: AnalysisJob, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard !lines.isEmpty, let ff = Tools.ffmpeg, info.audio != nil else { throw CastingSend.Failure.noAudio }
        let fm = FileManager.default
        let folder = newFolder(for: info)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let work = fm.temporaryDirectory.appendingPathComponent("mslice-exp-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        do {
            var source = info.url, mono = false
            if isolate {
                guard VoiceIsolation.available else { throw CastingSend.Failure.isolation }
                let wav = work.appendingPathComponent("full.wav"), iso = work.appendingPathComponent("voice.wav")
                let r = await Run.exec(ff, ["-v", "error", "-y", "-nostdin", "-i", info.url.path, "-map", "0:a:0", "-vn"] + CastingSend.downmix(info) + ["-ar", "48000", "-c:a", "pcm_s16le", wav.path])
                guard r.status == 0 else { throw CastingSend.Failure.ffmpeg }
                guard await VoiceIsolation.run(input: wav, output: iso, job: job, progress: { progress(0.45 * $0) }) else { throw job.cancelled ? CastingSend.Failure.cancelled : CastingSend.Failure.isolation }
                source = iso; mono = true
            }
            let spans = CastingSend.spans(lines, duration: info.duration)
            let filter = mono ? ["-ac", "1"] : CastingSend.downmix(info)
            let base = isolate ? 0.45 : 0.0
            for (i, l) in lines.enumerated() {
                if job.cancelled { throw CastingSend.Failure.cancelled }
                let name = String(format: "%04d", i + 1) + (l.character.map { " " + safeName($0) } ?? "") + ".wav"
                let a = spans[i]
                let r = await Run.exec(ff, ["-v", "error", "-y", "-nostdin", "-ss", String(format: "%.3f", a.start), "-t", String(format: "%.3f", max(a.end - a.start, 0.05)), "-i", source.path, "-map", "0:a:0", "-vn"]
                                       + filter + ["-ar", "48000", "-c:a", "pcm_s16le", folder.appendingPathComponent(name).path])
                guard r.status == 0 else { throw CastingSend.Failure.ffmpeg }
                progress(base + (1 - base) * Double(i + 1) / Double(lines.count))
            }
            try srt(lines).write(to: folder.appendingPathComponent(info.url.deletingPathExtension().lastPathComponent + ".srt"), atomically: true, encoding: .utf8)
            return folder
        } catch { try? fm.removeItem(at: folder); throw error }
    }

    // MARK: Noms lus sur disque (agent, essais)

    /// Nom d'un personnage d'après les index enregistrés : nom donné, sinon « Character n » / « Voice n ».
    static func name(of l: DialogueLine, faces: FaceIndex?, voices: VoiceIndex?) -> String? {
        if let w = l.who { return w }
        guard let sp = l.speaker, let id = Int32(sp.dropFirst()) else { return nil }
        if sp.hasPrefix("p") { return faces?.names[id] ?? voices?.link.first(where: { $0.value == id }).flatMap { voices?.names[$0.key] } ?? "Character \(id + 1)" }
        if sp.hasPrefix("v") { return voices?.names[id] ?? "Voice \(id + 1)" }
        return nil
    }
}
