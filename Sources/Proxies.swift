// mSLICE — fichier que macOS sait lire : l'original, sinon un proxy fabriqué par ffmpeg (remux sans perte, sinon basse définition).
// Partagé par le lecteur et par l'analyse (`mslice-mcp` compris) : le proxy, gardé en cache, n'est fabriqué qu'une fois.
import AVFoundation
import CryptoKit
import Foundation

enum Proxies {
    static func isPlayable(_ url: URL, needsVideo: Bool) async -> Bool {
        let a = AVURLAsset(url: url)
        guard (try? await a.load(.isPlayable)) == true else { return false }
        guard let tracks = try? await a.load(.tracks) else { return false }
        for t in tracks where (try? await t.load(.isDecodable)) == false { return false }
        if needsVideo { return tracks.contains { $0.mediaType == .video } }
        return !tracks.isEmpty
    }

    /// `onPrepare` est appelé (une fois) quand un proxy doit être fabriqué : le lecteur affiche « Préparation de l'aperçu… ».
    static func playableURL(_ info: MediaInfo, onPrepare: (@Sendable () -> Void)? = nil) async -> URL {
        if await isPlayable(info.url, needsVideo: !info.isAudioOnly) { return info.url }
        guard let ffmpeg = Tools.ffmpeg else { return info.url }
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/mSLICE/proxies", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mtime = (try? info.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        let key = SHA256.hash(data: Data("\(info.url.path)|\(info.size)|\(mtime)".utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let ext = info.isAudioOnly ? "m4a" : "mov"
        let out = dir.appendingPathComponent(key).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: out.path), await isPlayable(out, needsVideo: !info.isAudioOnly) { return out }
        onPrepare?()
        let tmp = dir.appendingPathComponent(key + ".part").appendingPathExtension(ext)
        let src = info.url.path
        let base = ["-nostdin", "-hide_banner", "-v", "error", "-y"]
        var attempts: [[String]] = []
        if info.isAudioOnly {
            attempts = [base + ["-i", src, "-vn", "-map", "0:a:0", "-c:a", "aac_at", "-b:a", "192k", tmp.path]]
        } else {
            attempts = [
                base + ["-i", src, "-map", "0:\(info.video?.index ?? 0)", "-map", "0:a:0?", "-c", "copy", "-f", "mov", tmp.path],     // remux sans perte
                base + ["-i", src, "-map", "0:\(info.video?.index ?? 0)", "-map", "0:a:0?", "-vf", "scale='min(1280,iw)':-2", "-c:v", "h264_videotoolbox", "-b:v", "6M", "-allow_sw", "1", "-pix_fmt", "yuv420p", "-g", "12",
                        "-c:a", "aac_at", "-b:a", "160k", "-f", "mov", tmp.path],
            ]
        }
        for args in attempts {
            try? FileManager.default.removeItem(at: tmp)
            let r = await Run.exec(ffmpeg, args)
            if r.status == 0, await isPlayable(tmp, needsVideo: !info.isAudioOnly) {
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.moveItem(at: tmp, to: out)
                return out
            }
        }
        try? FileManager.default.removeItem(at: tmp)
        return info.url
    }
}
