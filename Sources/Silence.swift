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

    /// Réglages des « blancs retirés » : un silence est ce qui reste sous −35 dB pendant 0,35 s ; on en garde 0,1 s de chaque côté d'une coupe (0,2 s de respiration entre deux prises).
    static let trimNoiseDB = -35.0, trimMinDuration = 0.35, trimKeep = 0.1

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
