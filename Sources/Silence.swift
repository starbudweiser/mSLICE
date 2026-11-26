// mSLICE — détection des silences (ffmpeg silencedetect), pour l'élagage en lot et pour les agents.
import Foundation

enum Silence {
    /// Intervalles de silence du premier flux audio : (début, fin) en secondes. Un silence qui court jusqu'à la fin du fichier se termine à la durée.
    static func ranges(_ info: MediaInfo, noiseDB: Double = -40, minDuration: Double = 1) async -> [(start: Double, end: Double)] {
        guard let ffmpeg = Tools.ffmpeg, info.audio != nil else { return [] }
        let text: String = await Task.detached(priority: .utility) {
            let p = Process(); p.executableURL = ffmpeg
            p.arguments = ["-nostdin", "-hide_banner", "-nostats", "-i", info.url.path, "-vn", "-map", "0:a:0", "-af", "silencedetect=noise=\(noiseDB)dB:d=\(minDuration)", "-f", "null", "-"]
            let err = Pipe(); p.standardError = err; p.standardOutput = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return "" }
            let d = err.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return String(decoding: d, as: UTF8.self)
        }.value
        var starts: [Double] = [], ends: [Double] = []
        for line in text.split(separator: "\n") {
            if let r = line.range(of: "silence_start: ") { if let v = Double(line[r.upperBound...].split(separator: " ").first ?? "") { starts.append(v) } }
            if let r = line.range(of: "silence_end: ") { if let v = Double(line[r.upperBound...].split(separator: " ").first ?? "") { ends.append(v) } }
        }
        return starts.enumerated().map { i, s in (max(s, 0), i < ends.count ? min(ends[i], info.duration) : info.duration) }
    }

    /// Début et fin à garder, d'après les silences d'ouverture et de fin du premier flux audio (seuil −40 dB, au moins 1 s), avec 0,25 s de marge.
    static func detect(_ info: MediaInfo, margin: Double = 0.25, noiseDB: Double = -40, minDuration: Double = 1) async -> (start: Double, end: Double)? {
        let r = await ranges(info, noiseDB: noiseDB, minDuration: minDuration)
        guard !r.isEmpty else { return nil }
        var a = 0.0, b = info.duration
        if let f = r.first, f.start <= 0.15 { a = f.end }                                                     // silence dès le début
        if let l = r.last, l.end >= info.duration - 0.15, l.start > a { b = l.start }                          // silence jusqu'à la fin
        a = max(a - margin, 0); b = min(b + margin, info.duration)
        guard b - a > 0.5, a > 0.01 || b < info.duration - 0.01 else { return nil }      // rien à retirer : aucun résultat
        return (a, b)
    }

    /// Respiration gardée de chaque côté d'une coupe par défaut (réglage moyen de l'intensité).
    static let trimKeep = 0.1

    /// Resserre les morceaux sur la parole. Début et fin : le silence d'ouverture ou de fermeture est réduit à `keep`. Si `inside`, un silence au milieu d'un morceau est coupé
    /// (il en reste `keep` de chaque côté) : le morceau devient plusieurs prises, utile quand tout est assemblé dans un seul fichier. Un morceau entièrement muet disparaît.
    static func tighten(_ segments: [Segment], silences: [(start: Double, end: Double)], keep: Double = trimKeep, inside: Bool) -> [Segment] {
        let sil = silences.sorted { $0.start < $1.start }
        var out: [Segment] = []
        for seg in segments {
            var a = seg.start, b = seg.end
            var cuts: [(Double, Double)] = []                                          // (fin de la prise, reprise suivante)
            for z in sil where z.end > a && z.start < b {
                if z.start <= a + 0.02 { a = max(a, z.end - keep) }                        // silence d'ouverture
                else if z.end >= b - 0.02 { b = min(b, z.start + keep) }                   // silence de fermeture
                else if inside, z.end - z.start > 2 * keep { cuts.append((z.start + keep, z.end - keep)) }
            }
            guard b - a > 0.05 else { continue }
            var cur = a, first = true
            for c in cuts.sorted(by: { $0.0 < $1.0 }) where c.0 > cur && c.0 < b && c.1 < b {
                if c.0 - cur > 0.05 { var n = Segment(start: cur, end: c.0, who: seg.who); if first { n.name = seg.name; n.id = seg.id; first = false }; out.append(n) }
                cur = c.1
            }
            if b - cur > 0.05 { var n = Segment(start: cur, end: b, who: seg.who); if first { n.name = seg.name; n.id = seg.id }; out.append(n) }
        }
        return out
    }
}

/// Niveau sonore du fichier (un point de 25 ms, en dB), calculé une fois ; les silences s'en déduisent instantanément pour toute intensité (le curseur reste fluide).
/// Le seuil est RELATIF au bruit de fond de la vidéo (niveau bas du fichier + une marge), pas un nombre fixe : une salle bruyante ou un rire de public ne cachent plus les pauses.
struct LoudnessProfile: Sendable {
    static let hop = 0.025
    let frameDB: [Float]
    let duration: Double
    let floorDB: Float, peakDB: Float

    init(frameDB: [Float], duration: Double) {
        self.frameDB = frameDB; self.duration = duration
        let live = frameDB.filter { $0 > -85 }.sorted()                       // les silences numériques purs ne disent rien du bruit de fond
        func q(_ p: Double) -> Float { live.isEmpty ? -90 : live[min(Int(Double(live.count - 1) * p), live.count - 1)] }
        floorDB = q(0.15); peakDB = q(0.95)
    }

    /// Intensité 0…1 → marge au-dessus du bruit de fond, durée minimale d'un silence, respiration gardée de chaque côté.
    /// Doux : 5 dB, 0,6 s, 0,15 s. Serré : 15 dB, 0,2 s, 0,05 s. Moyen (0,5) : 10 dB, 0,4 s, 0,10 s.
    static func params(_ intensity: Double) -> (marginDB: Double, minDuration: Double, keep: Double) {
        let i = min(max(intensity, 0), 1)
        return (5 + 10 * i, 0.6 - 0.4 * i, 0.15 - 0.10 * i)
    }

    /// Seuil de silence : bruit de fond + marge, sans jamais monter à moins de 18 dB (Doux) à 12 dB (Serré) sous les crêtes : la parole n'est pas coupée.
    func threshold(_ intensity: Double) -> Float { min(floorDB + Float(Self.params(intensity).marginDB), peakDB - Float(18 - 6 * min(max(intensity, 0), 1))) }

    func silences(intensity: Double) -> [(start: Double, end: Double)] {
        let p = Self.params(intensity), thr = threshold(intensity)
        let minFrames = Int((p.minDuration / Self.hop).rounded(.up))
        var out: [(start: Double, end: Double)] = []
        var runStart: Int?, lastQuiet = 0, loud = 0
        func close(_ end: Int) {
            if let a = runStart, end - a >= minFrames { out.append((Double(a) * Self.hop, min(Double(end) * Self.hop, duration))) }
            runStart = nil
        }
        for (i, v) in frameDB.enumerated() {
            if v < thr { if runStart == nil { runStart = i }; lastQuiet = i + 1; loud = 0 }
            else if runStart != nil { loud += 1; if loud >= 3 { close(lastQuiet); loud = 0 } }          // 3 images fortes de suite (75 ms) ferment un silence ; un clic isolé ne le coupe pas
        }
        close(runStart != nil && loud < 3 ? lastQuiet : frameDB.count)
        return out
    }

    /// Décode la première piste audio en mono 8 kHz et mesure le niveau toutes les 25 ms (ffmpeg, en flux : pas de fichier temporaire).
    static func measure(_ info: MediaInfo, progress: @escaping @Sendable (Double) -> Void = { _ in }) async -> LoudnessProfile? {
        guard let ffmpeg = Tools.ffmpeg, info.audio != nil else { return nil }
        return await Task.detached(priority: .utility) { () -> LoudnessProfile? in
            let p = Process(); p.executableURL = ffmpeg
            p.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", info.url.path, "-vn", "-map", "0:a:0", "-ac", "1", "-ar", "8000", "-f", "f32le", "-"]
            let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return nil }
            let win = 200                                                     // 25 ms à 8 kHz
            var frames: [Float] = [], acc: Double = 0, n = 0, carry = Data()
            let expected = max(info.duration * 8000 * 4, 1), step = expected / 100          // octets attendus : sert à la barre de progression
            var read = 0.0, nextReport = step
            let h = out.fileHandleForReading
            while true {
                let chunk = h.readData(ofLength: 1 << 16)
                if chunk.isEmpty { break }
                carry.append(chunk)
                read += Double(chunk.count)
                if read >= nextReport { progress(min(read / expected, 1)); nextReport = read + step }
                let usable = carry.count / 4 * 4
                carry.withUnsafeBytes { raw in
                    let f = raw.bindMemory(to: Float.self)
                    for i in 0 ..< usable / 4 {
                        let v = Double(f[i]); acc += v * v; n += 1
                        if n == win { frames.append(Float(10 * log10(acc / Double(win) + 1e-10))); acc = 0; n = 0 }
                    }
                }
                carry = Data(carry.suffix(carry.count - usable))
            }
            p.waitUntilExit()
            guard !frames.isEmpty else { return nil }
            return LoudnessProfile(frameDB: frames, duration: info.duration)
        }.value
    }
}

extension LoudnessProfile {
    /// Recale des répliques sur la parole réelle : un début placé dans un silence avance jusqu'au premier son, une fin placée dans un silence recule jusqu'au dernier son
    /// (0,08 s de marge). Les répliques ne se chevauchent jamais et gardent au moins 0,25 s.
    func align(_ ranges: [(start: Double, end: Double)]) -> [(start: Double, end: Double)] {
        let quiet = silences(intensity: 0.75)
        var out: [(start: Double, end: Double)] = []
        for r in ranges {
            var s = r.start, e = r.end
            for z in quiet where z.end > s && z.start < e {
                if z.start <= s + 0.06, z.end < e - 0.25 { s = max(s, z.end - 0.08) }          // silence d'ouverture
                else if z.end >= e - 0.06, z.start > s + 0.25 { e = min(e, z.start + 0.08) }   // silence de fermeture
            }
            if e - s < 0.25 { s = r.start; e = r.end }
            out.append((s, e))
        }
        return out
    }
}
