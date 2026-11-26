// mSLICE — piste « voix seules » d'un fichier entier : l'audio passe par l'isolation de voix de macOS (`VoiceIsolation`, musique et bruits retirés), puis par
// DeepFilterNet3 (`DeepFilterNet`, souffle et bruits de fond résiduels ; modèle embarqué, repli sur l'isolation seule s'il manque). Le résultat est gardé en FLAC (sans perte, ~2× plus petit que le WAV) dans le dossier de support, sous la clé du fichier (chemin, taille, date).
// Elle sert à trois choses : écouter la voix seule dans le lecteur, exporter avec cette piste à la place de l'audio d'origine, et reconnaître les voix
// sur un son sans musique. Aucun modèle à télécharger. Partagé avec `mslice-mcp` (analyse des voix).
import AVFoundation
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
    /// ALAC dans un .m4a : AVFoundation s'y place à l'échantillon près, alors qu'il se trompe de plusieurs dizaines de ms en FLAC (sans table de recherche) : le son et l'image restent synchrones après chaque déplacement.
    static func url(_ info: MediaInfo) -> URL { dir.appendingPathComponent(SessionStore.key(info) + ".voice.m4a") }
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
        let part = dir.appendingPathComponent(".\(SessionStore.key(info))-\(UUID().uuidString.prefix(6)).m4a")
        defer { try? fm.removeItem(at: part) }
        progress(0)
        let r = await Run.exec(ff, ["-v", "error", "-y", "-nostdin", "-i", info.url.path, "-map", "0:a:0", "-vn"] + CastingSend.downmix(info) + ["-ar", "48000", "-c:a", "pcm_s16le", wav.path])
        guard r.status == 0, !job.cancelled else { return false }
        progress(0.05)
        let dfn = DeepFilterNet()
        let isoShare = dfn == nil ? 0.85 : 0.60
        guard await VoiceIsolation.run(input: wav, output: iso, job: job, progress: { progress(0.05 + isoShare * $0) }) else { return false }
        // L'isolation de macOS retarde le son de ~60 ms sans le dire (latence annoncée : 0) : on mesure ce retard sur le fichier et on le rattrape, sinon la voix est en retard sur l'image.
        let lag = await onThread { AudioLag.estimate(reference: wav, processed: iso) } ?? 0
        try? fm.removeItem(at: wav)
        var final = iso
        if let dfn {
            let clean = work.appendingPathComponent("clean.wav"), base = 0.05 + isoShare
            let ok = await onThread { dfn.run(input: iso, output: clean, job: job, progress: { progress(base + (0.90 - base) * $0) }) }
            if job.cancelled { return false }
            if ok { final = clean }                                         // sinon : la voix isolée par macOS reste la piste
        }
        var filter = "anull"
        if lag > 0.004 && lag < 0.5 { filter = String(format: "atrim=start=%.4f,asetpts=PTS-STARTPTS,apad=whole_dur=%.4f", lag, (try? AVAudioFile(forReading: final)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? info.duration) }      // retard rattrapé, longueur conservée
        let f = await Run.exec(ff, ["-v", "error", "-y", "-nostdin", "-i", final.path, "-af", filter, "-c:a", "alac", "-movflags", "+faststart", "-f", "ipod", part.path])
        guard f.status == 0, !job.cancelled else { return false }
        let target = url(info)
        try? fm.removeItem(at: target)
        for old in [".flac", ".dfn.flac"] { try? fm.removeItem(at: dir.appendingPathComponent(SessionStore.key(info) + old)) }        // anciennes pistes (FLAC : positionnement imprécis)
        guard (try? fm.moveItem(at: part, to: target)) != nil else { return false }
        progress(1)
        prune(keeping: target)
        return true
    }

    /// Garde le dossier sous 6 Go : les pistes les moins récemment utilisées partent d'abord (elles se recalculent en quelques secondes par heure de son).
    static func prune(keeping: URL, limit: Int64 = 6 << 30) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        for old in items where old.pathExtension == "flac" { try? fm.removeItem(at: old) }                    // ancien format (positionnement imprécis) : jamais relu, on libère la place
        var files = items.filter { $0.pathExtension == "m4a" }.map { u -> (URL, Int64, Date) in
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey])
            return (u, Int64(v?.fileSize ?? 0), v?.contentAccessDate ?? v?.contentModificationDate ?? .distantPast)
        }
        var total = files.reduce(0) { $0 + $1.1 }
        files.sort { $0.2 < $1.2 }
        for f in files where total > limit && f.0 != keeping { try? fm.removeItem(at: f.0); total -= f.1 }
    }
}

/// Retard d'un son traité par rapport à l'original, mesuré sur la forme d'onde (8 kHz) : plusieurs fenêtres de 3 s choisies là où le son est le plus fort (la parole), corrélation normalisée à ±200 ms,
/// retenue seulement si elle est nette. Plus fiable que les enveloppes quand la musique a été retirée (la voix isolée ne ressemble plus à l'original par son niveau).
enum AudioLag {
    static func estimate(reference: URL, processed: URL, windows: Int = 8, seconds: Double = 3) -> Double? {
        guard let a = try? AVAudioFile(forReading: reference), let b = try? AVAudioFile(forReading: processed) else { return nil }
        let sr = a.processingFormat.sampleRate, dec = max(Int((sr / 8000).rounded()), 1), rate = sr / Double(dec)
        let total = Int(min(a.length, b.length)), span = Int(sr * seconds), pad = Int(sr * 0.25)
        guard total > span + 2 * pad else { return nil }
        func read(_ f: AVAudioFile, _ start: Int, _ count: Int) -> [Float] {
            f.framePosition = AVAudioFramePosition(start)
            guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(count)), (try? f.read(into: buf, frameCount: AVAudioFrameCount(count))) != nil,
                  let ch = buf.floatChannelData?[0] else { return [] }
            let n = Int(buf.frameLength) / dec
            return (0..<n).map { i in var v: Float = 0; for k in 0..<dec { v += ch[i * dec + k] }; return v / Float(dec) }
        }
        // fenêtres candidates : on garde les plus énergiques de l'original (la parole), éloignées les unes des autres
        let step = max((total - span - 2 * pad) / 60, 1)
        var cands: [(Int, Float)] = []
        for k in 0..<60 {
            let st = pad + k * step; let x = read(b, st, span)                                                        // énergie de la voix isolée : là où il y a de la parole
            cands.append((st, x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))))
        }
        let picked = cands.sorted { $0.1 > $1.1 }.prefix(windows).map { $0.0 }
        let maxLag = Int(rate * 0.2)
        var best: [Int] = []
        for st in picked {
            let x = read(a, st, span), y = read(b, st - pad, span + 2 * pad)         // y contient la même fenêtre avec 250 ms de marge de chaque côté
            guard x.count > 2000, y.count >= x.count + 2 * pad / dec - 2 else { continue }
            let nx = x.reduce(0) { $0 + $1 * $1 }.squareRoot(); guard nx > 1e-3 else { continue }
            var bestC: Float = 0, bestL = 0
            let off = pad / dec
            for l in -maxLag ... maxLag {
                var c: Float = 0, ny: Float = 0
                for i in stride(from: 0, to: x.count, by: 1) { let j = i + off + l; if j >= 0 && j < y.count { c += x[i] * y[j]; ny += y[j] * y[j] } }
                let r = c / (nx * ny.squareRoot() + 1e-9)
                if r > bestC { bestC = r; bestL = l }
            }
            if bestC > 0.1 { best.append(bestL) }                                       // corrélation faible acceptée (musique mêlée à la voix), mais il faudra un accord entre fenêtres
        }
        // accord : au moins 3 fenêtres à ±1 ms l'une de l'autre et plus de la moitié des fenêtres valides ; sinon on ne corrige rien
        let tol = max(Int(rate * 0.001), 1)
        var top: (count: Int, lag: Int) = (0, 0)
        for c in best { let group = best.filter { abs($0 - c) <= tol }; if group.count > top.count { top = (group.count, group.sorted()[group.count / 2]) } }
        guard top.count >= 3, top.count * 2 > best.count else { return nil }
        return Double(top.lag) / rate
    }
}
