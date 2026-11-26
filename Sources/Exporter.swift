// mSLICE — plan d'export (noms, commandes ffmpeg) et exécution avec progression.
import Foundation

struct Cmd {
    var args: [String]
    var out: URL
    var expected: Double          // durée de média produite (pour la progression)
    var temps: [URL] = []         // fichiers à effacer après usage
}

enum Planner {
    // MARK: Images clés

    /// Début réel d'un morceau en copie directe : la dernière image clé avant l'entrée (la vidéo ne peut pas démarrer ailleurs).
    static func effectiveStart(_ a: Double, keyframes: [Double], passthrough: Bool, hasVideo: Bool) -> Double {
        guard passthrough, hasVideo, !keyframes.isEmpty else { return a }
        var lo = 0, hi = keyframes.count - 1, best = -1
        while lo <= hi { let mid = (lo + hi) / 2; if keyframes[mid] <= a + 0.001 { best = mid; lo = mid + 1 } else { hi = mid - 1 } }
        return best >= 0 ? keyframes[best] : keyframes[0]
    }

    static func nearestKeyframe(_ t: Double, in k: [Double]) -> Double? {
        guard !k.isEmpty else { return nil }
        var lo = 0, hi = k.count - 1
        while lo < hi { let mid = (lo + hi) / 2; if k[mid] < t { lo = mid + 1 } else { hi = mid } }
        if lo > 0, abs(k[lo - 1] - t) <= abs(k[lo] - t) { return k[lo - 1] }
        return k[lo]
    }

    /// Les images clés de part et d'autre de `t` (strictement avant / après), pour la navigation ↑ ↓.
    static func keyframe(after t: Double, in k: [Double]) -> Double? { k.first { $0 > t + 0.0005 } }
    static func keyframe(before t: Double, in k: [Double]) -> Double? { k.last { $0 < t - 0.0005 } }

    // MARK: Noms de fichiers

    static func destinationDir(_ info: MediaInfo, _ opts: ExportOptions) -> URL {
        opts.folder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? info.url.deletingLastPathComponent()
    }

    /// Prochain numéro libre : on continue après le plus grand numéro existant (jamais d'écrasement).
    static func nextIndex(dir: URL, base: String, ext: String) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let prefix = base + "_", suffix = "." + ext.lowercased()
        var maxN = 0
        for n in names {
            let l = n.lowercased()
            guard l.hasPrefix(prefix.lowercased()), l.hasSuffix(suffix) else { continue }
            let mid = String(n.dropFirst(prefix.count).dropLast(suffix.count))
            if let v = Int(mid) { maxN = max(maxN, v) }
        }
        return maxN + 1
    }

    static func uniqueURL(dir: URL, name: String, ext: String) -> URL {
        var u = dir.appendingPathComponent(name).appendingPathExtension(ext), n = 2
        while FileManager.default.fileExists(atPath: u.path) { u = dir.appendingPathComponent("\(name)_\(n)").appendingPathExtension(ext); n += 1 }
        return u
    }

    // MARK: Plan

    /// Nom de fichier sûr : sans « / » ni « : », sans point initial, espaces de bord retirés.
    static func sanitize(_ s: String) -> String {
        var t = String(String.UnicodeScalarView(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\0" }))
        t = t.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix(".") { t.removeFirst() }
        return String(t.prefix(200))
    }

    /// Fichiers à produire. `base` remplace le nom de l'original dans la numérotation ; `mergeName` nomme le fichier fusionné ;
    /// le nom d'un morceau (`Segment.name`) prime sur tout. Un nom déjà pris (sur le disque ou dans ce lot) reçoit « _2 », « _3 »… : rien n'est écrasé.
    static func outputs(info: MediaInfo, segments: [Segment], opts: ExportOptions, keyframes: [Double], name: String? = nil, base baseOverride: String? = nil, mergeName: String? = nil) -> [OutputItem] {
        let fmt = opts.resolvedFormat(for: info)
        let ext = fmt.ext(source: info.ext)
        let dir = destinationDir(info, opts)
        let customBase = sanitize(baseOverride ?? "")
        let base = customBase.isEmpty ? info.url.deletingPathExtension().lastPathComponent : customBase
        let videoOut = !fmt.isAudio && !info.isAudioOnly
        let segs = segments.sorted { $0.start < $1.start }.map { s -> Segment in
            var t = s; t.start = effectiveStart(s.start, keyframes: keyframes, passthrough: opts.passthrough, hasVideo: videoOut); return t
        }
        if opts.merge {
            let custom = sanitize(mergeName ?? "")
            let u = uniqueURL(dir: dir, name: custom.isEmpty ? (name ?? "\(base)_\(opts.suffix)") : custom, ext: ext)
            return [OutputItem(url: u, segments: segs, expected: segs.reduce(0) { $0 + $1.duration })]
        }
        let autoCount = segs.filter { sanitize($0.name ?? "").isEmpty }.count
        var n = nextIndex(dir: dir, base: base, ext: ext)
        let width = max(opts.digits, String(n + max(autoCount, 1) - 1).count)
        var used = Set<String>()
        return segs.map { s in
            let custom = sanitize(s.name ?? "")
            var stem = custom
            if custom.isEmpty { stem = "\(base)_\(String(format: "%0\(width)d", n))"; n += 1 }
            var url = dir.appendingPathComponent(stem).appendingPathExtension(ext), k = 2
            while FileManager.default.fileExists(atPath: url.path) || used.contains(url.lastPathComponent.lowercased()) {
                url = dir.appendingPathComponent("\(stem)_\(k)").appendingPathExtension(ext); k += 1
            }
            used.insert(url.lastPathComponent.lowercased())
            return OutputItem(url: url, segments: [s], expected: s.duration)
        }
    }

    /// Morceaux dont le début réel est plus tôt que l'entrée demandée (copie directe) : (numéro, entrée, début réel).
    static func shifts(info: MediaInfo, segments: [Segment], opts: ExportOptions, keyframes: [Double]) -> [(Int, Double, Double)] {
        guard opts.passthrough, !info.isAudioOnly, !opts.resolvedFormat(for: info).isAudio else { return [] }
        return segments.sorted { $0.start < $1.start }.enumerated().compactMap { i, s in
            let e = effectiveStart(s.start, keyframes: keyframes, passthrough: true, hasVideo: true)
            return s.start - e > 0.05 ? (i + 1, s.start, e) : nil
        }
    }

    // MARK: Compatibilité de la copie directe

    /// Une copie sans recompression est possible si les codecs de l'original sont acceptés par le conteneur de sortie.
    static func canCopy(info: MediaInfo, to fmt: OutFormat) -> Bool {
        if fmt == .same { return true }
        let v = info.video?.codec ?? "", a = info.audio?.codec ?? ""
        func pcm(_ c: String) -> Bool { c.hasPrefix("pcm") }
        switch fmt {
        case .same: return true
        case .mkv: return true
        case .mp4: return (info.video == nil || ["h264", "hevc", "av1", "mpeg4", "mpeg2video", "mjpeg", "vp9"].contains(v)) && (info.audio == nil || ["aac", "mp3", "ac3", "eac3", "alac", "opus", "flac"].contains(a))
        case .mov: return (info.video == nil || ["h264", "hevc", "prores", "mpeg4", "mjpeg", "dnxhd", "dvvideo", "av1"].contains(v)) && (info.audio == nil || ["aac", "mp3", "ac3", "alac"].contains(a) || pcm(a))
        case .webm: return (info.video == nil || ["vp8", "vp9", "av1"].contains(v)) && (info.audio == nil || ["opus", "vorbis"].contains(a))
        case .mp3: return a == "mp3"
        case .m4a: return a == "aac" || a == "alac"
        case .wav, .aiff: return pcm(a)
        case .flac: return a == "flac"
        case .opus: return a == "opus"
        }
    }

    // MARK: Commandes ffmpeg

    static let common = ["-nostdin", "-hide_banner", "-v", "error", "-progress", "pipe:1", "-nostats", "-n"]

    static func f(_ t: Double) -> String { String(format: "%.6f", t) }

    static func videoBitrate(_ info: MediaInfo, quality: Quality, codec: VideoCodec) -> Int {
        var br = info.video?.bitrate ?? 0
        if br <= 0 { br = max(info.bitrate - Double((info.audio?.bitrate ?? 160_000)), 0) }
        if br <= 0, let v = info.video { br = Double(v.width * v.height) / (1920 * 1080) * 10_000_000 }
        if br <= 0 { br = 10_000_000 }
        if codec == .hevc { br *= 0.7 }
        return Int(min(max(br * quality.factor, 1_500_000), 120_000_000) / 1000)
    }

    static func codecFor(_ fmt: OutFormat, _ chosen: VideoCodec) -> VideoCodec {
        switch fmt { case .webm: .vp9; case .mp4: chosen == .prores || chosen == .vp9 ? .h264 : chosen; case .mov: chosen == .vp9 ? .h264 : chosen; case .mkv: chosen; default: chosen }
    }

    /// Sélection des flux et codecs pour un export (hors positionnement).
    static func streamArgs(info: MediaInfo, fmt: OutFormat, opts: ExportOptions, voice: Bool = false) -> [String] {
        let outExt = fmt.ext(source: info.ext)
        if fmt.isAudio || info.isAudioOnly {
            // « voix seules » : la piste nettoyée est la seule entrée (0), toujours réencodée
            if voice { return ["-vn", "-map", "0:a:0"] + audioEncode(fmt, ext: outExt, video: false) }
            var a = ["-vn", "-map", "0:a:0"]
            if opts.passthrough { return a + ["-c:a", "copy"] }
            switch fmt {
            case .mp3: a += ["-c:a", "libmp3lame", "-q:a", "2"]
            case .m4a: a += ["-c:a", "aac_at", "-b:a", "256k"]
            case .wav: a += ["-c:a", "pcm_s16le"]
            case .aiff: a += ["-c:a", "pcm_s16be"]
            case .flac: a += ["-c:a", "flac"]
            case .opus: a += ["-c:a", "libopus", "-b:a", "160k"]
            default: a += ["-c:a", "aac_at", "-b:a", "256k"]
            }
            return a
        }
        if opts.passthrough {
            // Flux explicites : la pochette attachée (image fixe) fausserait la durée et le recalage des temps des morceaux fusionnés.
            var a = ["-map", "0:\(info.video?.index ?? 0)", "-map", voice ? "1:a:0" : "0:a?"]
            let sameBox = outExt == info.ext
            if sameBox || fmt == .mkv { a += ["-map", "0:s?"] }
            if sameBox && outExt == "mov" { a += ["-map", "0:d?"] }          // timecode des fichiers MOV
            a += ["-c", "copy"]
            if voice { a += audioEncode(fmt, ext: outExt, video: true) }
            if info.video?.codec == "hevc", fmt == .mp4 || fmt == .mov || (fmt == .same && ["mp4", "mov", "m4v"].contains(info.ext)) { a += ["-tag:v", "hvc1"] }
            return a
        }
        let codec = codecFor(fmt, opts.codec)
        var a = ["-map", "0:v:0", "-map", voice ? "1:a:0" : "0:a?"]
        let br = "\(videoBitrate(info, quality: opts.quality, codec: codec))k"
        switch codec {
        case .h264: a += ["-c:v", "h264_videotoolbox", "-b:v", br, "-profile:v", "high", "-allow_sw", "1"]
        case .hevc: a += ["-c:v", "hevc_videotoolbox", "-b:v", br, "-tag:v", "hvc1", "-allow_sw", "1"]
        case .prores: a += ["-c:v", "prores_videotoolbox", "-profile:v", "hq"]
        case .vp9: a += ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", String(Int(36 - 8 * opts.quality.factor)), "-row-mt", "1", "-deadline", "good", "-cpu-used", "4"]
        }
        switch (fmt, codec) {
        case (.webm, _): a += ["-c:a", "libopus", "-b:a", "128k"]
        case (_, .prores): a += ["-c:a", "pcm_s16le"]
        default: a += ["-c:a", "aac_at", "-b:a", "192k"]
        }
        return a + ["-sn", "-dn"]
    }

    /// Encodage de l'audio quand il est refait (piste « voix seules » : mono, 48 kHz).
    static func audioEncode(_ fmt: OutFormat, ext: String, video: Bool) -> [String] {
        let f = fmt == .same ? (OutFormat(rawValue: ext.lowercased()) ?? .mp4) : fmt
        switch f {
        case .mp3: return ["-c:a", "libmp3lame", "-q:a", "2"]
        case .wav: return ["-c:a", "pcm_s16le"]
        case .aiff: return ["-c:a", "pcm_s16be"]
        case .flac: return ["-c:a", "flac"]
        case .opus: return ["-c:a", "libopus", "-b:a", "160k"]
        case .webm: return ["-c:a", "libopus", "-b:a", "128k"]
        default: return ["-c:a", "aac_at", "-b:a", video ? "192k" : "256k"]
        }
    }

    static func commands(info: MediaInfo, item: OutputItem, opts: ExportOptions, keyframes: [Double] = []) -> [Cmd] {
        let fmt = opts.resolvedFormat(for: info)
        let clean: URL? = opts.voiceOnly && CleanVoice.exists(info) ? CleanVoice.url(info) : nil
        let streams = streamArgs(info: info, fmt: fmt, opts: opts, voice: clean != nil)
        let src = info.url.path
        func single(_ s: Segment, to out: URL) -> Cmd {
            let start = max(s.start, 0), dur = max(s.duration, 0.001)
            if let clean {
                // Sortie audio : seule la piste nettoyée est lue. Sortie vidéo : l'image de l'original (copie ou recompression) et le son de la piste nettoyée,
                // chacun cherché au même instant (le début d'un morceau en copie directe est déjà l'image clé, voir `outputs`).
                let isAudioOut = fmt.isAudio || info.isAudioOnly
                let inputs = isAudioOut ? ["-ss", f(start), "-i", clean.path] : ["-ss", f(start), "-i", src, "-ss", f(start), "-i", clean.path]
                return Cmd(args: common + inputs + ["-t", f(dur)] + streams + (opts.passthrough ? ["-avoid_negative_ts", "make_zero"] : []) + [out.path], out: out, expected: dur)
            }
            var pre = ["-ss", f(start)], post: [String] = []
            // Audio copié depuis une vidéo : la recherche se fait sur l'image clé (flux vidéo). On se place sur l'image clé exacte,
            // puis on saute le reste en sortie, pour que le morceau commence vraiment à l'entrée demandée.
            if opts.passthrough, fmt.isAudio, !info.isAudioOnly {
                let kp = effectiveStart(start, keyframes: keyframes, passthrough: true, hasVideo: true)
                if start - kp > 0.001 { pre = ["-ss", f(kp)]; post = ["-ss", f(start - kp)] }
            }
            let args = common + pre + ["-i", src] + post + ["-t", f(dur)] + streams + (opts.passthrough ? ["-avoid_negative_ts", "make_zero"] : []) + [out.path]
            return Cmd(args: args, out: out, expected: dur)
        }
        if item.segments.count == 1 { return [single(item.segments[0], to: item.url)] }
        let outExt = item.url.pathExtension
        if opts.passthrough, clean == nil, !(fmt.isAudio && !info.isAudioOnly) {
            // Un seul passage : le démultiplexeur « concat » lit directement les morceaux de l'original.
            let list = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-\(UUID().uuidString).ffconcat")
            var text = "ffconcat version 1.0\n"
            let esc = src.replacingOccurrences(of: "'", with: "'\\''")
            for s in item.segments { text += "file '\(esc)'\ninpoint \(f(max(s.start, 0)))\noutpoint \(f(s.end))\n" }
            try? text.write(to: list, atomically: true, encoding: .utf8)
            let args = common + ["-f", "concat", "-safe", "0", "-i", list.path] + streams + ["-avoid_negative_ts", "make_zero", item.url.path]
            return [Cmd(args: args, out: item.url, expected: item.expected, temps: [list])]
        }
        // Recompression : chaque morceau est encodé avec les mêmes réglages, puis les fichiers sont collés sans nouvel encodage.
        let dir = item.url.deletingLastPathComponent()
        var cmds: [Cmd] = [], parts: [URL] = []
        for s in item.segments {
            let tmp = dir.appendingPathComponent(".mslice-\(UUID().uuidString.prefix(8))").appendingPathExtension(outExt)
            parts.append(tmp); cmds.append(single(s, to: tmp))
        }
        let list = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-\(UUID().uuidString).ffconcat")
        let text = "ffconcat version 1.0\n" + parts.map { "file '\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'\n" }.joined()
        try? text.write(to: list, atomically: true, encoding: .utf8)
        cmds.append(Cmd(args: common + ["-f", "concat", "-safe", "0", "-i", list.path, "-map", "0", "-c", "copy", item.url.path], out: item.url, expected: 0, temps: parts + [list]))
        return cmds
    }

    // MARK: Estimations (affichées avec « ≈ »)

    static func estimate(info: MediaInfo, segments: [Segment], opts: ExportOptions) -> (bytes: Int64, seconds: Double) {
        let kept = segments.reduce(0) { $0 + $1.duration }
        let fmt = opts.resolvedFormat(for: info)
        if opts.passthrough {
            let share = info.duration > 0 ? kept / info.duration : 0
            let audioShare = fmt.isAudio && !info.isAudioOnly ? Double(info.audio?.bitrate ?? 160_000) * kept / 8 : nil
            return (Int64(audioShare ?? Double(info.size) * share), max(0.5, Double(info.size) * share / 1.5e9))
        }
        if fmt.isAudio || info.isAudioOnly { return (Int64(kept * 256_000 / 8), max(1, kept / 60)) }
        let codec = codecFor(fmt, opts.codec)
        let br = Double(videoBitrate(info, quality: opts.quality, codec: codec)) * 1000 + 192_000
        return (Int64(br * kept / 8), max(1, kept / (codec == .vp9 ? 0.5 : 5)))
    }
}

/// Exécute un export : une file de commandes ffmpeg, avec progression par fichier et annulation.
@MainActor
final class ExportRun: ObservableObject {
    enum State: Equatable { case waiting, running, done, failed(String), cancelled }
    struct Item: Identifiable { var id = UUID(); var name: String; var duration: Double; var fraction = 0.0; var state = State.waiting; var bytes: Int64 = 0 }

    @Published var items: [Item] = []
    @Published var overall = 0.0
    @Published var bytesDone: Int64 = 0
    @Published var speed = 0.0              // octets par seconde
    @Published var finished = false
    @Published var error: String?
    @Published var cancelled = false
    private(set) var results: [URL] = []
    private(set) var totalBytes: Int64 = 0
    private(set) var elapsed = 0.0
    let cancel = CancelToken()

    /// Lance l'export ; `completion` est appelé à la fin (réussite, échec ou annulation).
    func start(info: MediaInfo, outputs: [OutputItem], opts: ExportOptions, keyframes: [Double] = [], completion: (() -> Void)? = nil) {
        guard let ffmpeg = Tools.ffmpeg else { error = L.t("err.noffmpeg"); finished = true; completion?(); return }
        items = outputs.map { Item(name: $0.url.lastPathComponent, duration: $0.expected) }
        // Le fichier d'origine doit exister (sinon ffmpeg ne dit que « No such file or directory »).
        if !FileManager.default.fileExists(atPath: info.url.path) {
            let msg = L.t("err.sourcegone", info.url.path)
            for k in items.indices { items[k].state = .failed(msg) }
            error = msg; finished = true; completion?(); return
        }
        // Le dossier de destination est créé s'il manque (dossier supprimé, volume démonté puis remonté…).
        for o in outputs { try? FileManager.default.createDirectory(at: o.url.deletingLastPathComponent(), withIntermediateDirectories: true) }
        let plans = outputs.map { Planner.commands(info: info, item: $0, opts: opts, keyframes: keyframes) }
        let total = max(plans.flatMap { $0 }.reduce(0) { $0 + max($1.expected, 0.001) }, 0.001)
        let t0 = Date()
        Task {
            var done = 0.0
            outer: for (i, cmds) in plans.enumerated() {
                items[i].state = .running
                let itemTotal = max(cmds.reduce(0) { $0 + max($1.expected, 0.001) }, 0.001)
                var itemDone = 0.0
                for (j, cmd) in cmds.enumerated() {
                    let weight = max(cmd.expected, 0.001)
                    let isLast = j == cmds.count - 1
                    let itemBase = itemDone, doneBase = done
                    let r = await Run.exec(ffmpeg, cmd.args, cancel: cancel) { [weak self] line in
                        guard line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) else { return }
                        let frac = min(max(us / 1e6 / weight, 0), 1)
                        Task { @MainActor in
                            guard let self else { return }
                            let part = (itemBase + frac * weight) / itemTotal
                            self.items[i].fraction = isLast || cmds.count == 1 ? max(self.items[i].fraction, frac) : max(self.items[i].fraction, part)
                            self.overall = min((doneBase + frac * weight) / total, 1)
                        }
                    }
                    itemDone += weight; done += weight
                    for t in cmd.temps where t != cmd.out && isLast { try? FileManager.default.removeItem(at: t) }
                    if cancel.cancelled { cleanup(cmds); for k in i ..< items.count { items[k].state = .cancelled }; cancelled = true; break outer }
                    if r.status != 0 {
                        cleanup(cmds)
                        let msg = r.err.split(separator: "\n").last.map(String.init) ?? "ffmpeg \(r.status)"
                        items[i].state = .failed(msg); error = msg; break outer
                    }
                    elapsed = Date().timeIntervalSince(t0)
                }
                let size = (try? cmds.last?.out.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init) ?? 0
                items[i].bytes = size; items[i].fraction = 1; items[i].state = .done
                totalBytes += size; bytesDone = totalBytes; results.append(outputs[i].url)
                speed = elapsed > 0 ? Double(totalBytes) / elapsed : 0
            }
            elapsed = Date().timeIntervalSince(t0)
            if error == nil && !cancelled { overall = 1 }
            finished = true
            completion?()
        }
    }

    private func cleanup(_ cmds: [Cmd]) {
        for c in cmds { try? FileManager.default.removeItem(at: c.out); for t in c.temps { try? FileManager.default.removeItem(at: t) } }
    }
}
