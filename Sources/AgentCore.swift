// mSLICE — noyau des agents (sans interface, partagé par l'appli, le panneau de discussion et l'exécutable MCP `mslice-mcp`).
//
// Un seul catalogue d'outils : sondage, silences, morceaux (bistouri), aperçu et export, élagage en lot, image d'un instant.
// Garde-fous, quels que soient l'agent et le moteur : l'agent CRÉE de nouveaux fichiers, jamais d'écrasement (ffmpeg `-n` et noms uniques),
// jamais de suppression ni de corbeille, et il n'écrit que dans le dossier du fichier source (ou l'un de ses sous-dossiers) ou dans
// le dossier d'export choisi par l'utilisateur. Tout est inactif tant que « Autoriser un agent » n'est pas coché dans les préférences.
import Foundation

struct AgentError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// Résultat d'un outil, au format MCP : blocs de texte et d'image.
struct ToolOutput {
    var content: [[String: Any]]
    var isError = false
    static func text(_ s: String, error: Bool = false) -> ToolOutput { ToolOutput(content: [["type": "text", "text": s]], isError: error) }
    static func json(_ o: Any) -> ToolOutput { .text(AgentJSON.string(o)) }
    var plainText: String { content.compactMap { $0["text"] as? String }.joined(separator: "\n") }
}

enum AgentJSON {
    static func string(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "\(o)" }
        return String(data: d, encoding: .utf8) ?? "{}"
    }
    static func parse(_ s: String) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] }
}

/// L'appli ouverte (fournie par l'appli ; absente quand `mslice-mcp` travaille seul).
@MainActor protocol AgentHost: AnyObject {
    func openFiles() -> [URL]
    func currentFile() -> URL?
    func playhead() -> Double?
    /// Morceaux d'un fichier ouvert dans l'appli (nil : fichier pas ouvert).
    func segments(of url: URL) -> [Segment]?
    /// Remplace les morceaux d'un fichier ouvert ; renvoie faux s'il n'est pas ouvert.
    func setSegments(_ segs: [Segment], of url: URL) -> Bool
    func open(_ url: URL)
    func seek(_ t: Double)
    func notify(_ text: String)
    func userExportFolder() -> String?
}

struct ToolDef {
    var name: String
    var description: String
    var properties: [(String, String, String)]      // (nom, type JSON, description)
    var required: [String] = []
    var schema: [String: Any] {
        var props: [String: Any] = [:]
        for (n, t, d) in properties {
            var p: [String: Any] = ["type": t, "description": d]
            if t == "array" { p["items"] = n == "paths" ? ["type": "string"] : ["type": "object"] }
            props[n] = p
        }
        return ["type": "object", "properties": props, "required": required]
    }
    var mcp: [String: Any] { ["name": name, "description": description, "inputSchema": schema] }
}

@MainActor
enum Agent {
    // MARK: Catalogue

    static let instructions = """
    mSLICE trims audio and video: the user marks pieces to keep in a file, then exports them as numbered files or as one merged file, with direct stream copy (no re-encoding, instant, lossless) or re-encoded. \
    Typical flow: probe_media -> (find_silences / get_frame to decide) -> set_segments (or trim_edges / trim_silences / split_on_silence) -> preview_export -> export. \
    Times are in seconds (or "m:ss.d" / "h:mm:ss"). With direct copy a video piece can only start on a keyframe: the real start snaps to the keyframe before the requested one (preview_export tells which pieces move); \
    use passthrough=false to cut exactly. Pieces are saved per file: if mSLICE is open on the file, the timeline updates live. \
    The agent only creates new files: nothing is ever overwritten, deleted or moved to the trash, and exports stay in the source file's folder (or a sub-folder of it, or the user's chosen export folder).
    """

    static let tools: [ToolDef] = [
        ToolDef(name: "get_state", description: "State of mSLICE: whether the app is open, the files it has open (with their pieces and the playhead), and the defaults used by export. Call it first.", properties: []),
        ToolDef(name: "probe_media", description: "Describe an audio/video file: duration, size, container, streams (codec, size, frame rate, channels), and optionally its keyframes (count and longest gap, which limit direct-copy cuts).",
                properties: [("path", "string", "Absolute path of the file"), ("keyframes", "boolean", "Also count the keyframes (reads the packets: a few seconds on long files). Default false.")], required: ["path"]),
        ToolDef(name: "find_silences", description: "List the silent intervals of the first audio stream, plus the leading and trailing silence and the sounding ranges between silences.",
                properties: [("path", "string", "Absolute path of the file"), ("noise_db", "number", "Silence threshold in dB. Default -40 (use -30 for noisy rooms)."), ("min_duration", "number", "Minimum silence length in seconds. Default 1.")], required: ["path"]),
        ToolDef(name: "get_frame", description: "Return the picture of the video at a given time (PNG), to look at the content before deciding where to cut.",
                properties: [("path", "string", "Absolute path of the file"), ("time", "string", "Time in seconds or m:ss.d"), ("width", "number", "Width in pixels (default 640, max 1280)")], required: ["path", "time"]),
        ToolDef(name: "get_segments", description: "The pieces (segments) marked to keep in a file, in order, numbered from 1. Read live from mSLICE if the file is open, else from the saved session.",
                properties: [("path", "string", "Absolute path of the file")], required: ["path"]),
        ToolDef(name: "set_segments", description: "Replace all the pieces of a file. Pieces are clamped to the file, sorted, and overlapping ones are merged. If mSLICE has the file open, the timeline updates live.",
                properties: [("path", "string", "Absolute path of the file"), ("segments", "array", "Array of {start, end, name?}: times in seconds or m:ss.d; name is the exported file name without extension (optional)")], required: ["path", "segments"]),
        ToolDef(name: "add_segment", description: "Add one piece to keep (merged with any piece it overlaps).",
                properties: [("path", "string", "Absolute path of the file"), ("start", "string", "In point"), ("end", "string", "Out point"), ("name", "string", "Exported file name without extension (optional)")], required: ["path", "start", "end"]),
        ToolDef(name: "remove_segment", description: "Remove one piece by its number (1-based, as returned by get_segments).",
                properties: [("path", "string", "Absolute path of the file"), ("index", "number", "Piece number, from 1")], required: ["path", "index"]),
        ToolDef(name: "clear_segments", description: "Remove all the pieces of a file.", properties: [("path", "string", "Absolute path of the file")], required: ["path"]),
        ToolDef(name: "trim_edges", description: "Keep one piece that drops the first `head` seconds and the last `tail` seconds (replaces the existing pieces).",
                properties: [("path", "string", "Absolute path of the file"), ("head", "number", "Seconds to remove at the start (default 0)"), ("tail", "number", "Seconds to remove at the end (default 0)")], required: ["path"]),
        ToolDef(name: "trim_silences", description: "Keep one piece that drops the opening and closing silence (replaces the existing pieces). Reports when there is nothing to remove.",
                properties: [("path", "string", "Absolute path of the file"), ("noise_db", "number", "Silence threshold in dB. Default -40."), ("min_silence", "number", "Minimum silence length in seconds. Default 1."), ("margin", "number", "Seconds kept around the sound. Default 0.25.")], required: ["path"]),
        ToolDef(name: "split_on_silence", description: "Replace the pieces with the sounding ranges between silences (removes every silence longer than min_silence, including in the middle). Then export with merge=true for a tightened cut, or merge=false for one file per range.",
                properties: [("path", "string", "Absolute path of the file"), ("noise_db", "number", "Silence threshold in dB. Default -35."), ("min_silence", "number", "Silences at least this long (seconds) are removed. Default 0.8."), ("padding", "number", "Seconds kept on each side of the sound. Default 0.15."), ("min_piece", "number", "Drop sounding pieces shorter than this (seconds). Default 0.5.")], required: ["path"]),
        ToolDef(name: "preview_export", description: "Dry run of an export: the files that would be created, durations, estimated size, whether direct copy is possible, and pieces whose start snaps to an earlier keyframe. Writes nothing.",
                properties: exportProps, required: ["path"]),
        ToolDef(name: "export", description: "Export the pieces of a file: one numbered file per piece (merge=false, default) or one merged file (merge=true). Direct stream copy by default (passthrough=true). Returns the created files. Never overwrites: existing names get a suffix. May take minutes when re-encoding.",
                properties: exportProps, required: ["path"]),
        ToolDef(name: "batch_trim", description: "Trim several files at once: drop `head` seconds at the start and `tail` seconds at the end of each (or the opening/closing silence with silences=true), writing new files next to the originals.",
                properties: [("paths", "array", "Absolute paths of the files"), ("head", "number", "Seconds to remove at the start (default 0)"), ("tail", "number", "Seconds to remove at the end (default 0)"), ("silences", "boolean", "Remove the opening/closing silence instead of fixed durations"), ("passthrough", "boolean", "Direct stream copy, no re-encoding (default true)")], required: ["paths"]),
        ToolDef(name: "open_in_app", description: "Open a file in the mSLICE window (launches the app in the background without taking focus if needed), so the user sees the pieces on the timeline.",
                properties: [("path", "string", "Absolute path of the file")], required: ["path"]),
        ToolDef(name: "seek", description: "Move the playhead of the mSLICE window to a time (the app must be open).", properties: [("time", "string", "Time in seconds or m:ss.d")], required: ["time"]),
    ]
    static let toolNames = Set(tools.map(\.name))

    private static let exportProps: [(String, String, String)] = [
        ("path", "string", "Absolute path of the source file"),
        ("segments", "array", "Optional: pieces to export, [{start, end, name?}]. Default: the pieces saved for the file (get_segments)."),
        ("merge", "boolean", "One merged file instead of one file per piece. Default false."),
        ("passthrough", "boolean", "Direct stream copy, no re-encoding (instant, lossless; video starts on a keyframe). Default true."),
        ("format", "string", "same (default), mp4, mov, mkv, webm, mp3, m4a, wav, flac, aiff or opus. Audio formats extract the sound."),
        ("codec", "string", "When re-encoding video: h264 (default), hevc, prores or vp9"),
        ("quality", "string", "When re-encoding: high (default), medium or low"),
        ("folder", "string", "Destination folder: the source folder (default) or a sub-folder of it"),
        ("base_name", "string", "Base of the numbered file names (default: the source name)"),
        ("merge_name", "string", "Name of the merged file without extension (default: <name>_<suffix>)"),
    ]

    // MARK: Autorisation et exécution

    /// nil si l'agent est autorisé, sinon le message à lui renvoyer.
    static func authorize() -> String? {
        if (Env.pref("agent.enabled") as? Bool) == true { return nil }
        return "AI control is off in mSLICE. Ask the user to open mSLICE › Settings › Agent and turn on \"Allow an agent to control mSLICE\". It is off by default so that no program can cut or export files without the user's consent."
    }

    static func run(_ name: String, _ args: [String: Any], host: AgentHost?, client: String) async -> ToolOutput {
        if let refus = authorize() { AgentLog.write(client, name, args, "refused"); return .text(refus, error: true) }
        guard toolNames.contains(name) else { return .text("Unknown tool: \(name)", error: true) }
        do {
            let out = try await execute(name, args, host: host)
            AgentLog.write(client, name, args, out.isError ? "error" : "ok")
            return out
        } catch {
            AgentLog.write(client, name, args, "error: \(error.localizedDescription)")
            return .text(error.localizedDescription, error: true)
        }
    }

    // MARK: Aides

    private static var infoCache: [String: (MediaInfo, Date)] = [:]
    private static var keyframeCache: [String: [Double]] = [:]

    static func fileURL(_ args: [String: Any], _ key: String = "path") throws -> URL {
        guard let raw = args[key] as? String, !raw.isEmpty else { throw AgentError("\(key) is required (absolute path of an audio or video file).") }
        let u = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue else { throw AgentError("File not found: \(u.path)") }
        return u
    }

    static func info(_ url: URL) async throws -> MediaInfo {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if let (i, m) = infoCache[url.path], m == mtime { return i }
        guard Tools.ffprobe != nil else { throw AgentError("The ffprobe engine could not be found.") }
        guard let i = await Task.detached(operation: { Probe.read(url) }).value else { throw AgentError("Not a readable audio or video file: \(url.lastPathComponent)") }
        infoCache[url.path] = (i, mtime)
        return i
    }

    static func keyframes(_ i: MediaInfo) async -> [Double] {
        if let k = keyframeCache[i.url.path] { return k }
        let k = await Task.detached(operation: { Probe.keyframes(i) }).value
        keyframeCache[i.url.path] = k
        return k
    }

    /// « 12.5 », « 1:23.5 », « 1:02:03 » → secondes.
    static func time(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        guard var s = (any as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: ",", with: ".")
        let parts = s.split(separator: ":").map(String.init)
        var total = 0.0
        for p in parts { guard let v = Double(p) else { return nil }; total = total * 60 + v }
        return total
    }
    static func number(_ any: Any?) -> Double? { time(any) }
    static func bool(_ any: Any?) -> Bool? { if let b = any as? Bool { return b }; if let s = (any as? String)?.lowercased() { return ["true", "yes", "1", "oui"].contains(s) ? true : (["false", "no", "0", "non"].contains(s) ? false : nil) }; return (any as? NSNumber)?.boolValue }

    static func r1(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    static func rows(_ segs: [Segment]) -> [[String: Any]] {
        segs.enumerated().map { i, s in
            var d: [String: Any] = ["index": i + 1, "start": r1(s.start), "end": r1(s.end), "duration": r1(s.duration), "start_text": Fmt.time(s.start), "end_text": Fmt.time(s.end)]
            if let n = s.name, !n.isEmpty { d["name"] = n }
            return d
        }
    }

    /// Bornes, tri, fusion des chevauchements (comme le bistouri de l'appli) ; les morceaux trop courts sont écartés.
    static func normalize(_ raw: [Segment], duration: Double) -> [Segment] {
        var out: [Segment] = []
        for s in raw.map({ Segment(id: $0.id, start: max(0, min($0.start, $0.end)), end: min(duration, max($0.start, $0.end)), name: $0.name) }).filter({ $0.end - $0.start >= 0.05 }).sorted(by: { $0.start < $1.start }) {
            if var last = out.last, s.start <= last.end { last.end = max(last.end, s.end); out[out.count - 1] = last } else { out.append(s) }
        }
        return out
    }

    static func parseSegments(_ any: Any?) throws -> [Segment] {
        guard let arr = any as? [[String: Any]] else { throw AgentError("segments must be an array of {start, end, name?}.") }
        return try arr.map { d in
            guard let a = time(d["start"]), let b = time(d["end"]) else { throw AgentError("Each piece needs numeric start and end (seconds or m:ss.d).") }
            let n = (d["name"] as? String).map(Planner.sanitize).flatMap { $0.isEmpty ? nil : $0 }
            return Segment(start: a, end: b, name: n)
        }
    }

    /// Morceaux d'un fichier : en direct si l'appli l'a ouvert, sinon la session enregistrée.
    static func currentSegments(_ i: MediaInfo, host: AgentHost?) -> (segs: [Segment], live: Bool) {
        if let s = host?.segments(of: i.url) { return (s, true) }
        return (SessionStore.load(i).segments, false)
    }

    @discardableResult
    static func store(_ segs: [Segment], _ i: MediaInfo, host: AgentHost?) -> Bool {
        if host?.setSegments(segs, of: i.url) == true { return true }
        var s = SessionStore.load(i); s.segments = segs
        SessionStore.save(i, s)
        return false
    }

    static func segmentsResult(_ segs: [Segment], live: Bool, _ i: MediaInfo, extra: [String: Any] = [:]) -> ToolOutput {
        var o: [String: Any] = ["file": i.url.path, "count": segs.count, "kept_seconds": r1(segs.reduce(0) { $0 + $1.duration }), "file_duration": r1(i.duration), "live_in_app": live, "segments": rows(segs)]
        for (k, v) in extra { o[k] = v }
        return .json(o)
    }

    // MARK: Outils

    private static func execute(_ name: String, _ a: [String: Any], host: AgentHost?) async throws -> ToolOutput {
        switch name {
        case "get_state":
            var files: [[String: Any]] = []
            for u in host?.openFiles() ?? [] {
                var f: [String: Any] = ["path": u.path]
                if let s = host?.segments(of: u) { f["segments"] = rows(s) }
                files.append(f)
            }
            var o: [String: Any] = ["app_open": host != nil, "open_files": files,
                                    "defaults": ["passthrough": true, "merge": false, "format": "same", "note": "Exports are written next to the source file; names are numbered and never overwrite."]]
            if let c = host?.currentFile() { o["current_file"] = c.path }
            if let p = host?.playhead() { o["playhead"] = r1(p) }
            if host == nil { o["note"] = "mSLICE is not open: file tools still work; pieces are saved per file and appear on the timeline when the file is opened. Use open_in_app to show a file." }
            return .json(o)

        case "probe_media":
            let i = try await info(try fileURL(a))
            var o: [String: Any] = ["file": i.url.path, "duration": r1(i.duration), "duration_text": Fmt.time(i.duration), "size_bytes": i.size, "container": i.format, "summary": i.summary, "audio_only": i.isAudioOnly,
                                    "streams": i.streams.map { s -> [String: Any] in
                                        var d: [String: Any] = ["index": s.index, "kind": s.kind, "codec": s.codec]
                                        if s.width > 0 { d["width"] = s.width; d["height"] = s.height }
                                        if s.fps > 0 { d["fps"] = (s.fps * 100).rounded() / 100 }
                                        if s.channels > 0 { d["channels"] = s.channels; d["sample_rate"] = s.sampleRate }
                                        if s.cover { d["cover_art"] = true }
                                        return d
                                    }]
            if bool(a["keyframes"]) == true, !i.isAudioOnly {
                let k = await keyframes(i)
                var gap = 0.0; for n in 1 ..< max(k.count, 1) { gap = max(gap, k[n] - k[n - 1]) }
                o["keyframes"] = ["count": k.count, "longest_gap_seconds": r1(gap), "average_gap_seconds": r1(k.count > 1 ? (k.last! - k.first!) / Double(k.count - 1) : 0)]
            }
            return .json(o)

        case "find_silences":
            let i = try await info(try fileURL(a))
            guard i.audio != nil else { throw AgentError("This file has no audio stream.") }
            let noise = number(a["noise_db"]) ?? -40, minD = max(number(a["min_duration"]) ?? 1, 0.1)
            let r = await Silence.ranges(i, noiseDB: noise, minDuration: minD)
            var sound: [(Double, Double)] = [], cur = 0.0
            for s in r { if s.start - cur > 0.05 { sound.append((cur, s.start)) }; cur = s.end }
            if i.duration - cur > 0.05 { sound.append((cur, i.duration)) }
            func pair(_ p: (start: Double, end: Double)) -> [String: Any] { ["start": r1(p.start), "end": r1(p.end), "duration": r1(p.end - p.start)] }
            var o: [String: Any] = ["file": i.url.path, "noise_db": noise, "min_duration": minD, "silences": r.map(pair), "sounding": sound.map { ["start": r1($0.0), "end": r1($0.1), "duration": r1($0.1 - $0.0)] }]
            if let f = r.first, f.start <= 0.15 { o["leading_silence_until"] = r1(f.end) }
            if let l = r.last, l.end >= i.duration - 0.15 { o["trailing_silence_from"] = r1(l.start) }
            return .json(o)

        case "get_frame":
            let url = try fileURL(a)
            let i = try await info(url)
            guard !i.isAudioOnly else { throw AgentError("This file has no video.") }
            guard let t = time(a["time"]), t >= 0, t <= i.duration else { throw AgentError("time must be between 0 and \(r1(i.duration)) seconds.") }
            guard let ffmpeg = Tools.ffmpeg else { throw AgentError("The ffmpeg engine could not be found.") }
            let w = Int(min(max(number(a["width"]) ?? 640, 64), 1280)) & ~1
            let png: Data? = await Task.detached { Run.data(ffmpeg, ["-nostdin", "-v", "error", "-ss", Planner.f(t), "-i", url.path, "-frames:v", "1", "-vf", "scale=\(w):-2", "-f", "image2pipe", "-vcodec", "png", "-"]) }.value
            guard let png, !png.isEmpty else { throw AgentError("Could not read a picture at that time.") }
            return ToolOutput(content: [["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"], ["type": "text", "text": "Frame of \(url.lastPathComponent) at \(Fmt.time(t)) (\(r1(t)) s)."]])

        case "get_segments":
            let i = try await info(try fileURL(a))
            let (s, live) = currentSegments(i, host: host)
            return segmentsResult(s, live: live, i)

        case "set_segments":
            let i = try await info(try fileURL(a))
            let segs = normalize(try parseSegments(a["segments"]), duration: i.duration)
            guard !segs.isEmpty else { throw AgentError("No valid piece: each piece needs start < end inside the file (0 to \(r1(i.duration)) s), at least 0.05 s long.") }
            let live = store(segs, i, host: host)
            return segmentsResult(segs, live: live, i)

        case "add_segment":
            let i = try await info(try fileURL(a))
            guard let s = time(a["start"]), let e = time(a["end"]) else { throw AgentError("start and end are required (seconds or m:ss.d).") }
            var cur = currentSegments(i, host: host).segs
            let n = (a["name"] as? String).map(Planner.sanitize).flatMap { $0.isEmpty ? nil : $0 }
            cur.append(Segment(start: s, end: e, name: n))
            let segs = normalize(cur, duration: i.duration)
            guard segs.count > 0, segs.contains(where: { $0.start <= max(s, 0) + 1e-6 && $0.end >= min(e, i.duration) - 1e-6 }) else { throw AgentError("The piece is empty once clamped to the file (0 to \(r1(i.duration)) s).") }
            let live = store(segs, i, host: host)
            return segmentsResult(segs, live: live, i)

        case "remove_segment":
            let i = try await info(try fileURL(a))
            var cur = currentSegments(i, host: host).segs
            guard let n = number(a["index"]), Int(n) >= 1, Int(n) <= cur.count else { throw AgentError("index must be between 1 and \(cur.count).") }
            cur.remove(at: Int(n) - 1)
            let live = store(cur, i, host: host)
            return segmentsResult(cur, live: live, i)

        case "clear_segments":
            let i = try await info(try fileURL(a))
            let live = store([], i, host: host)
            return segmentsResult([], live: live, i)

        case "trim_edges":
            let i = try await info(try fileURL(a))
            let head = max(number(a["head"]) ?? 0, 0), tail = max(number(a["tail"]) ?? 0, 0)
            guard i.duration - head - tail >= 0.1 else { throw AgentError("The file (\(r1(i.duration)) s) is too short to remove \(r1(head)) s + \(r1(tail)) s.") }
            let segs = [Segment(start: head, end: i.duration - tail)]
            let live = store(segs, i, host: host)
            return segmentsResult(segs, live: live, i)

        case "trim_silences":
            let i = try await info(try fileURL(a))
            guard i.audio != nil else { throw AgentError("This file has no audio stream.") }
            guard let r = await Silence.detect(i, margin: number(a["margin"]) ?? 0.25, noiseDB: number(a["noise_db"]) ?? -40, minDuration: max(number(a["min_silence"]) ?? 1, 0.1)) else {
                return .json(["file": i.url.path, "changed": false, "note": "No opening or closing silence to remove at this threshold; pieces left unchanged."])
            }
            let live = store([Segment(start: r.start, end: r.end)], i, host: host)
            return segmentsResult([Segment(start: r.start, end: r.end)], live: live, i, extra: ["changed": true])

        case "split_on_silence":
            let i = try await info(try fileURL(a))
            guard i.audio != nil else { throw AgentError("This file has no audio stream.") }
            let minS = max(number(a["min_silence"]) ?? 0.8, 0.1), pad = max(number(a["padding"]) ?? 0.15, 0), minP = max(number(a["min_piece"]) ?? 0.5, 0.05)
            let sil = await Silence.ranges(i, noiseDB: number(a["noise_db"]) ?? -35, minDuration: minS)
            var pieces: [Segment] = [], cur = 0.0
            for s in sil { if s.start - cur > 0.01 { pieces.append(Segment(start: cur - pad, end: s.start + pad)) }; cur = s.end }
            if i.duration - cur > 0.01 { pieces.append(Segment(start: cur - pad, end: i.duration)) }
            let segs = normalize(pieces.filter { $0.duration - 2 * pad >= minP }, duration: i.duration)
            guard !segs.isEmpty else { throw AgentError("No sounding range found at this threshold; try a lower noise_db (e.g. -45) or a longer min_silence.") }
            let live = store(segs, i, host: host)
            return segmentsResult(segs, live: live, i, extra: ["removed_seconds": r1(i.duration - segs.reduce(0) { $0 + $1.duration })])

        case "preview_export", "export":
            return try await exportTool(a, dryRun: name == "preview_export", host: host)

        case "batch_trim":
            return try await batchTrim(a, host: host)

        case "open_in_app":
            let url = try fileURL(a)
            if let host { host.open(url); return .json(["opened": url.path, "app_was_open": true]) }
            let app = Bundle.main.bundleURL
            guard app.pathExtension == "app" else { throw AgentError("mSLICE.app could not be located; open the file in the app manually.") }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-g", "-a", app.path, url.path]
            try p.run()
            return .json(["opened": url.path, "app_was_open": false, "note": "mSLICE was launched in the background; it can take a few seconds before live tools (seek, live pieces) respond."])

        case "seek":
            guard let host else { throw AgentError("mSLICE is not open. Call open_in_app first.") }
            guard let t = time(a["time"]), t >= 0 else { throw AgentError("time must be a positive number of seconds or m:ss.d.") }
            host.seek(t)
            return .json(["playhead": r1(t)])

        default:
            throw AgentError("Unknown tool: \(name)")
        }
    }

    // MARK: Export

    /// Dossier de destination autorisé : celui du fichier source, un de ses sous-dossiers, ou le dossier d'export choisi par l'utilisateur.
    static func checkedFolder(_ folder: Any?, source: URL, host: AgentHost?) throws -> String? {
        guard let f = folder as? String, !f.isEmpty else { return nil }
        let dir = URL(fileURLWithPath: (f as NSString).expandingTildeInPath, relativeTo: source.deletingLastPathComponent()).standardizedFileURL
        func real(_ u: URL) -> String { u.resolvingSymlinksInPath().path }
        func inside(_ p: String, _ root: String) -> Bool { p == root || p.hasPrefix(root + "/") }
        var roots = [real(source.deletingLastPathComponent())]
        if let u = host?.userExportFolder() ?? userFolderFromPrefs() { roots.append(real(URL(fileURLWithPath: u))) }
        // Le dossier peut ne pas exister encore : on contrôle son plus proche parent existant.
        var probe = dir
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" { probe = probe.deletingLastPathComponent() }
        let full = real(probe) + dir.path.dropFirst(probe.path.count)
        guard roots.contains(where: { inside(full, $0) }) else {
            throw AgentError("Folder not allowed: exports stay in the source file's folder (or a sub-folder) or in the export folder chosen in mSLICE. Allowed: \(roots.joined(separator: ", ")).")
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    static func userFolderFromPrefs() -> String? {
        guard let d = Env.pref("export.opts") as? Data, let o = try? JSONDecoder().decode(ExportOptions.self, from: d) else { return nil }
        return o.folder
    }

    struct Plan { var info: MediaInfo; var segments: [Segment]; var opts: ExportOptions; var outputs: [OutputItem]; var keyframes: [Double]; var notes: [String] }

    static func makePlan(_ a: [String: Any], segments segsIn: [Segment]?, host: AgentHost?, forcedPassthrough: Bool? = nil) async throws -> Plan {
        let url = try fileURL(a)
        let i = try await info(url)
        var segs: [Segment]
        if let given = a["segments"] { segs = normalize(try parseSegments(given), duration: i.duration) }
        else if let s = segsIn { segs = s }
        else { segs = currentSegments(i, host: host).segs }
        guard !segs.isEmpty else { throw AgentError("No pieces to export: call set_segments (or trim_edges / trim_silences / split_on_silence) first, or pass segments.") }

        // Réglages de l'agent : explicites et prévisibles (indépendants de l'état de l'interface), sauf numérotation et suffixe de l'utilisateur.
        var o = ExportOptions()
        if let d = Env.pref("export.opts") as? Data, let u = try? JSONDecoder().decode(ExportOptions.self, from: d) { o.digits = u.digits; o.suffix = u.suffix }
        o.passthrough = forcedPassthrough ?? bool(a["passthrough"]) ?? true
        o.merge = bool(a["merge"]) ?? false
        if let f = a["format"] as? String, !f.isEmpty { guard let v = OutFormat(rawValue: f.lowercased()) else { throw AgentError("Unknown format \"\(f)\". Use same, mp4, mov, mkv, webm, mp3, m4a, wav, flac, aiff or opus.") }; o.format = v }
        if let c = a["codec"] as? String, !c.isEmpty { guard let v = VideoCodec(rawValue: c.lowercased()) else { throw AgentError("Unknown codec \"\(c)\". Use h264, hevc, prores or vp9.") }; o.codec = v }
        if let q = a["quality"] as? String, !q.isEmpty { guard let v = Quality(rawValue: q.lowercased()) else { throw AgentError("Unknown quality \"\(q)\". Use high, medium or low.") }; o.quality = v }
        o.folder = try checkedFolder(a["folder"], source: url, host: host)

        var notes: [String] = []
        if o.passthrough, !Planner.canCopy(info: i, to: o.format) { throw AgentError("Direct copy is not possible into \(o.format.title) with this file's codecs. Use passthrough=false to re-encode, or another format.") }
        if o.passthrough, !i.isAudioOnly, o.resolvedFormat(for: i).isAudio, i.audio == nil { throw AgentError("This file has no audio to extract.") }
        if !o.passthrough, o.format == .same { o.format = i.isAudioOnly ? .m4a : .mp4 }
        if !o.passthrough, !i.isAudioOnly, o.format.isAudio { /* extraction audio recompressée : rien de plus */ }

        let kf = o.passthrough && !i.isAudioOnly ? await keyframes(i) : []
        let base = (a["base_name"] as? String).map(Planner.sanitize), merged = (a["merge_name"] as? String).map(Planner.sanitize)
        let outs = Planner.outputs(info: i, segments: segs, opts: o, keyframes: kf, base: base, mergeName: merged)
        for (n, want, real) in Planner.shifts(info: i, segments: segs, opts: o, keyframes: kf) {
            notes.append("Piece \(n): requested start \(Fmt.time(want)) snaps to the keyframe at \(Fmt.time(real)) (direct copy). Use passthrough=false to cut exactly.")
        }
        return Plan(info: i, segments: segs, opts: o, outputs: outs, keyframes: kf, notes: notes)
    }

    private static func exportTool(_ a: [String: Any], dryRun: Bool, host: AgentHost?) async throws -> ToolOutput {
        let plan = try await makePlan(a, segments: nil, host: host)
        let est = Planner.estimate(info: plan.info, segments: plan.segments, opts: plan.opts)
        let planned: [[String: Any]] = plan.outputs.map { ["path": $0.url.path, "duration": r1($0.expected), "pieces": $0.segments.count] }
        if dryRun {
            return .json(["dry_run": true, "source": plan.info.url.path, "mode": plan.opts.merge ? "merged file" : "one file per piece", "passthrough": plan.opts.passthrough,
                          "will_create": planned, "estimated_size_bytes": est.bytes, "estimated_seconds": r1(est.seconds), "notes": plan.notes])
        }
        let (results, error, elapsed) = await runExport(plan)
        let created: [[String: Any]] = results.map { u in ["path": u.path, "size_bytes": (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0] }
        if let error { throw AgentError("Export failed: \(error)" + (created.isEmpty ? "" : " (files already created: \(created.compactMap { $0["path"] as? String }.joined(separator: ", ")))")) }
        host?.notify("Agent : \(results.count) \(results.count > 1 ? "fichiers exportés" : "fichier exporté")")
        return .json(["exported": true, "source": plan.info.url.path, "created": created, "seconds": r1(elapsed), "passthrough": plan.opts.passthrough, "notes": plan.notes])
    }

    static func runExport(_ plan: Plan) async -> (results: [URL], error: String?, elapsed: Double) {
        let r = ExportRun(); let t0 = Date()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            r.start(info: plan.info, outputs: plan.outputs, opts: plan.opts, keyframes: plan.keyframes) { c.resume() }
        }
        return (r.results, r.error ?? (r.cancelled ? "cancelled" : nil), Date().timeIntervalSince(t0))
    }

    private static func batchTrim(_ a: [String: Any], host: AgentHost?) async throws -> ToolOutput {
        guard let paths = a["paths"] as? [String], !paths.isEmpty else { throw AgentError("paths must be a non-empty array of absolute file paths.") }
        let head = max(number(a["head"]) ?? 0, 0), tail = max(number(a["tail"]) ?? 0, 0)
        let useSilence = bool(a["silences"]) ?? false
        guard useSilence || head + tail > 0 else { throw AgentError("Give head and/or tail seconds, or silences=true.") }
        var results: [[String: Any]] = []
        for p in paths {
            do {
                let url = try fileURL(["path": p])
                let i = try await info(url)
                var seg: Segment
                if useSilence {
                    guard let r = await Silence.detect(i) else { results.append(["source": url.path, "skipped": "no opening or closing silence to remove (or no audio)"]); continue }
                    seg = Segment(start: r.start, end: r.end)
                } else {
                    guard i.duration - head - tail >= 0.5 else { results.append(["source": url.path, "skipped": "too short to remove \(r1(head)) s + \(r1(tail)) s"]); continue }
                    seg = Segment(start: head, end: i.duration - tail)
                }
                var args: [String: Any] = ["path": url.path, "merge": false]
                if let pt = a["passthrough"] { args["passthrough"] = pt }
                let plan = try await makePlan(args, segments: [seg], host: host)
                let (done, error, _) = await runExport(plan)
                if let error { results.append(["source": url.path, "error": error]) }
                else { results.append(["source": url.path, "created": done.map(\.path), "notes": plan.notes]) }
            } catch {
                results.append(["source": p, "error": error.localizedDescription])
            }
        }
        let ok = results.filter { $0["created"] != nil }.count
        host?.notify("Agent : \(ok)/\(paths.count) fichiers élagués")
        return .json(["processed": paths.count, "trimmed": ok, "results": results])
    }
}

/// Journal des actions des agents : une ligne par appel (date, client, outil, arguments, résultat), dans Application Support.
enum AgentLog {
    static var url: URL { Env.supportDir.appendingPathComponent("agent.log") }
    static func write(_ client: String, _ tool: String, _ args: [String: Any], _ result: String) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let summary = args.keys.sorted().map { k -> String in let v = "\(args[k] ?? "")".replacingOccurrences(of: "\n", with: " "); return "\(k)=\(v.count > 70 ? "…" + v.suffix(67) : v)" }.joined(separator: " ")
        let line = "\(f.string(from: Date()))\t\(client)\t\(tool)\t\(summary)\t\(result)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() } else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
}
