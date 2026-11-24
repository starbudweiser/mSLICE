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
}
