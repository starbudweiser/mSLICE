// mSLICE — piste « voix seules » d'un fichier entier : l'audio passe par l'isolation de voix de macOS (`VoiceIsolation`, musique et bruits retirés), puis par
// DeepFilterNet3 (`DeepFilterNet`, souffle et bruits de fond résiduels ; modèle embarqué, repli sur l'isolation seule s'il manque). Le résultat est gardé en FLAC (sans perte, ~2× plus petit que le WAV) dans le dossier de support, sous la clé du fichier (chemin, taille, date).
// Elle sert à trois choses : écouter la voix seule dans le lecteur, exporter avec cette piste à la place de l'audio d'origine, et reconnaître les voix
// sur un son sans musique. Aucun modèle à télécharger. Partagé avec `mslice-mcp` (analyse des voix).
import Foundation

enum CleanVoice {
    /// `MSLICE_CLEAN_DIR` redirige le dossier (essais).
    static var dir: URL {
        let d: URL
        if let t = ProcessInfo.processInfo.environment["MSLICE_CLEAN_DIR"] { d = URL(fileURLWithPath: t, isDirectory: true) }
        else { d = Env.supportDir.appendingPathComponent("clean", isDirectory: true) }
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ info: MediaInfo) -> URL { dir.appendingPathComponent(SessionStore.key(info) + ".dfn.flac") }        // « .dfn » : les anciennes pistes (isolation seule) se refont
    static var available: Bool { VoiceIsolation.available && Tools.ffmpeg != nil }

    static func exists(_ info: MediaInfo) -> Bool {
        let size = (try? url(info).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return (size ?? 0) > 1024
    }

    /// Fabrique la piste (mono, 48 kHz) ; progression 0…1, annulable. Vrai si le fichier est en place. Ne touche jamais au fichier d'origine.
    static func build(_ info: MediaInfo, job: AnalysisJob, slot: Bool = true, progress: @escaping @Sendable (Double) -> Void) async -> Bool {
        guard info.audio != nil, available, let ff = Tools.ffmpeg else { return false }
        if exists(info) { progress(1); return true }
        if slot { await AnalysisSlot.shared.acquire() }
        defer { if slot { Task { await AnalysisSlot.shared.release() } } }
        if job.cancelled { return false }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("mslice-clean-\(UUID().uuidString.prefix(8))")
        guard (try? fm.createDirectory(at: work, withIntermediateDirectories: true)) != nil else { return false }
        defer { try? fm.removeItem(at: work) }
        let wav = work.appendingPathComponent("full.wav"), iso = work.appendingPathComponent("voice.wav")
        let part = dir.appendingPathComponent(".\(SessionStore.key(info))-\(UUID().uuidString.prefix(6)).flac")
        defer { try? fm.removeItem(at: part) }
        progress(0)
        let r = await Run.exec(ff, ["-v", "error", "-y", "-nostdin", "-i", info.url.path, "-map", "0:a:0", "-vn"] + CastingSend.downmix(info) + ["-ar", "48000", "-c:a", "pcm_s16le", wav.path])
        guard r.status == 0, !job.cancelled else { return false }
        progress(0.05)
        let dfn = DeepFilterNet()
        let isoShare = dfn == nil ? 0.85 : 0.60
        guard await VoiceIsolation.run(input: wav, output: iso, job: job, progress: { progress(0.05 + isoShare * $0) }) else { return false }
        try? fm.removeItem(at: wav)
        var final = iso
        if let dfn {
            let clean = work.appendingPathComponent("clean.wav"), base = 0.05 + isoShare
            let ok = await onThread { dfn.run(input: iso, output: clean, job: job, progress: { progress(base + (0.90 - base) * $0) }) }
            if job.cancelled { return false }
            if ok { final = clean }                                         // sinon : la voix isolée par macOS reste la piste
        }
        let f = await Run.exec(ff, ["-v", "error", "-y", "-nostdin", "-i", final.path, "-c:a", "flac", "-f", "flac", part.path])
        guard f.status == 0, !job.cancelled else { return false }
        let target = url(info)
        try? fm.removeItem(at: target)
        try? fm.removeItem(at: dir.appendingPathComponent(SessionStore.key(info) + ".flac"))        // ancienne piste (avant DeepFilterNet)
        guard (try? fm.moveItem(at: part, to: target)) != nil else { return false }
        progress(1)
        prune(keeping: target)
        return true
    }

    /// Garde le dossier sous 6 Go : les pistes les moins récemment utilisées partent d'abord (elles se recalculent en quelques secondes par heure de son).
    static func prune(keeping: URL, limit: Int64 = 6 << 30) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        var files = items.filter { $0.pathExtension == "flac" }.map { u -> (URL, Int64, Date) in
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey])
            return (u, Int64(v?.fileSize ?? 0), v?.contentAccessDate ?? v?.contentModificationDate ?? .distantPast)
        }
        var total = files.reduce(0) { $0 + $1.1 }
        files.sort { $0.2 < $1.2 }
        for f in files where total > limit && f.0 != keeping { try? fm.removeItem(at: f.0); total -= f.1 }
    }
}
