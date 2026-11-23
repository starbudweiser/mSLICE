// mSLICE — description d'un fichier audio / vidéo (ffprobe) et index de ses images clés.
import Foundation

struct StreamInfo {
    var index: Int
    var kind: String            // video, audio, subtitle, data
    var codec: String
    var width = 0, height = 0
    var fps = 0.0
    var channels = 0, sampleRate = 0
    var bitrate = 0.0
    var cover = false           // image de pochette attachée (pas une vraie vidéo)
}

struct MediaInfo {
    var url: URL
    var duration: Double
    var size: Int64
    var bitrate: Double
    var format: String
    var streams: [StreamInfo]

    var video: StreamInfo? { streams.first { $0.kind == "video" && !$0.cover } }
    var audio: StreamInfo? { streams.first { $0.kind == "audio" } }
    var isAudioOnly: Bool { video == nil }
    var ext: String { url.pathExtension.lowercased() }

    static func codecName(_ c: String) -> String {
        switch c {
        case "h264": "H.264"; case "hevc": "H.265"; case "prores": "ProRes"; case "mpeg4": "MPEG-4"; case "vp9": "VP9"; case "vp8": "VP8"; case "av1": "AV1"
        case "aac": "AAC"; case "mp3": "MP3"; case "flac": "FLAC"; case "opus": "Opus"; case "vorbis": "Vorbis"; case "ac3": "AC-3"; case "eac3": "E-AC-3"; case "alac": "ALAC"
        case "dnxhd": "DNxHD"; case "mjpeg": "MJPEG"
        default: c.hasPrefix("pcm") ? "PCM" : c.uppercased()
        }
    }

    /// « 3840×2160 · H.265 · 25 i/s · AAC 48 kHz · 3:42.1 · 4,2 Go »
    var summary: String {
        var parts: [String] = []
        if let v = video {
            parts.append("\(v.width)×\(v.height)"); parts.append(MediaInfo.codecName(v.codec))
            if v.fps > 0 { parts.append("\(Fmt.fps(v.fps)) i/s") }
        }
        if let a = audio { parts.append("\(MediaInfo.codecName(a.codec)) \(Fmt.khz(a.sampleRate))") }
        parts.append(Fmt.time(duration)); parts.append(Fmt.size(size))
        return parts.joined(separator: " · ")
    }
}

enum Probe {
    static func read(_ url: URL) -> MediaInfo? {
        guard let ffprobe = Tools.ffprobe,
              let data = Run.data(ffprobe, ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", url.path]),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let fmt = root["format"] as? [String: Any] ?? [:]
        func num(_ v: Any?) -> Double { if let s = v as? String { return Double(s) ?? 0 }; return (v as? NSNumber)?.doubleValue ?? 0 }
        var streams: [StreamInfo] = []
        for s in (root["streams"] as? [[String: Any]] ?? []) {
            var st = StreamInfo(index: Int(num(s["index"])), kind: s["codec_type"] as? String ?? "data", codec: s["codec_name"] as? String ?? "?")
            st.width = Int(num(s["width"])); st.height = Int(num(s["height"]))
            let rate = (s["avg_frame_rate"] as? String) ?? (s["r_frame_rate"] as? String) ?? "0/1"
            let rp = rate.split(separator: "/").compactMap { Double($0) }
            if rp.count == 2, rp[1] > 0 { st.fps = rp[0] / rp[1] }
            st.channels = Int(num(s["channels"])); st.sampleRate = Int(num(s["sample_rate"])); st.bitrate = num(s["bit_rate"])
            if let d = s["disposition"] as? [String: Any], num(d["attached_pic"]) == 1 { st.cover = true }
            streams.append(st)
        }
        var duration = num(fmt["duration"])
        if duration <= 0 { duration = (root["streams"] as? [[String: Any]] ?? []).map { num($0["duration"]) }.max() ?? 0 }
        guard duration > 0 else { return nil }
        return MediaInfo(url: url, duration: duration, size: Int64(num(fmt["size"])), bitrate: num(fmt["bit_rate"]), format: fmt["format_name"] as? String ?? "", streams: streams)
    }

    /// Instants des images clés de la vidéo (sans décoder : lecture des paquets seulement).
    static func keyframes(_ info: MediaInfo) -> [Double] {
        guard let ffprobe = Tools.ffprobe, let v = info.video,
              let data = Run.data(ffprobe, ["-v", "error", "-select_streams", String(v.index), "-show_entries", "packet=pts_time,dts_time,flags", "-of", "csv=p=0", info.url.path]) else { return [] }
        var out: [Double] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 3, f[2].contains("K") else { continue }
            if let t = Double(f[0]) ?? Double(f[1]) { out.append(t) }
        }
        return out.sorted()
    }
}

/// Mises en forme partagées (durées, tailles) : une décimale, virgule en français.
enum Fmt {
    /// 3:42.1 ou 1:03:55.2
    static func time(_ t: Double, decimals: Bool = true) -> String {
        let t = max(0, t)
        let tenths = Int((t * 10).rounded(.down))
        let h = tenths / 36000, m = (tenths / 600) % 60, s = (tenths / 10) % 60, d = tenths % 10
        let sec = String(format: "%02d", s)
        let base = h > 0 ? "\(h):\(String(format: "%02d", m)):\(sec)" : "\(m):\(sec)"
        return decimals ? base + ".\(d)" : base
    }
    static func size(_ bytes: Int64) -> String {
        let b = Double(bytes)
        let comma = L.lang == .fr || L.lang == .es || L.lang == .it
        func f(_ v: Double, _ unit: String) -> String { let s = String(format: v < 10 ? "%.2f" : v < 100 ? "%.1f" : "%.0f", v); return (comma ? s.replacingOccurrences(of: ".", with: ",") : s) + " " + unit }
        if b >= 1e9 { return f(b / 1e9, L.t("unit.gb")) }
        if b >= 1e6 { return f(b / 1e6, L.t("unit.mb")) }
        return f(max(b / 1e3, 0), L.t("unit.kb"))
    }
    /// Nombre à une décimale, virgule en français, espagnol et italien.
    static func dec(_ v: Double) -> String { let s = String(format: "%.1f", v); return L.lang == .en ? s : s.replacingOccurrences(of: ".", with: ",") }
    static func fps(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v).replacingOccurrences(of: ".", with: L.lang == .en ? "." : ",") }
    static func khz(_ hz: Int) -> String { hz % 1000 == 0 ? "\(hz / 1000) kHz" : String(format: "%.1f kHz", Double(hz) / 1000) }
}
