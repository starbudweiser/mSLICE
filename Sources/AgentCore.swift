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
    /// Analyse d'un fichier ouvert dans l'appli : la progression s'affiche dans l'onglet « Trouver ». nil si elle échoue ou est annulée.
    func analyze(_ url: URL, force: Bool) async -> AnalysisIndex?
    /// Reconnaissance des personnages d'un fichier ouvert dans l'appli (modèle optionnel installé). nil si elle échoue ou est annulée.
    func recognize(_ url: URL) async -> FaceIndex?
    /// Nom donné à un personnage d'un fichier ouvert dans l'appli ; faux si le fichier n'est pas ouvert (l'outil écrit alors le fichier des visages).
    func renameSubject(_ id: Int32, to name: String, of url: URL) -> Bool
    /// Reconnaissance des voix d'un fichier ouvert dans l'appli (modèle optionnel installé). nil si elle échoue ou est annulée.
    func recognizeVoices(_ url: URL) async -> VoiceIndex?
    /// Nom donné à une voix, ou lien avec un personnage (`person` : -1 pour délier, nil pour ne pas toucher au lien) ; faux si le fichier n'est pas ouvert.
    func editVoice(_ id: Int32, name: String?, person: Int32?, of url: URL) -> Bool
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
            if t == "array" { p["items"] = ["paths", "include", "exclude"].contains(n) ? ["type": "string"] : ["type": "object"] }
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
    To find content by what it shows or sounds like (explosions, night scenes, laughter, a crowd, music, speech...): analyze_media (built-in macOS models, local, about 1 s per minute of video, saved and reused) -> find_scenes (include / exclude, apply="add" or "set") -> preview_export -> export. \
    To find a character (by face): the user must have installed the optional characters model in the Find tab; then analyze_media with characters=true -> list_subjects -> name_subject -> find_scenes with include ["person:<id or name>"]. \
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
        ToolDef(name: "analyze_media", description: "Analyze a video or audio file with the models built into macOS (nothing is downloaded, nothing leaves the Mac): detects the shots (cuts), the kinds of scenes (fire, crowd, night, vehicles, people, animals, food, sports...) and the sounds (speech, music, laughter, gunfire, explosions, sirens...). Takes about 1 s per minute of video; the result is saved and reused. Returns the shot count and the scene and sound families found, each with an identifier (\"scene:fire\", \"sound:laugh\") for find_scenes, its total duration and its number of passages. It does not recognise individual people by itself: with characters=true it also recognises the characters (faces, grouped by person) if the user installed the optional characters model in mSLICE's Find tab (the agent never downloads anything: without the model, characters.status is \"model_not_installed\"). Recognition takes about 1 s per minute of video and is saved with the file. With voices=true it also recognises the voices (speaker embeddings, grouped by speaker) if the user installed the second optional model (voices.status is \"model_not_installed\" otherwise); each voice is linked to the character whose face is alone on screen while it speaks. Works on audio-only files too.",
                properties: [("path", "string", "Absolute path of the file"), ("force", "boolean", "Analyze again even if a saved result exists (default false). Character recognition is never redone by this flag: it would lose the names given to the characters."), ("all", "boolean", "List every family found instead of the 25 longest of each kind (default false)"),
                             ("characters", "boolean", "Also recognise the characters (faces) with the optional model, then list them (default false)"), ("voices", "boolean", "Also recognise the voices with the second optional model, then list them (default false)")], required: ["path"]),
        ToolDef(name: "find_scenes", description: "Find the passages of a file that match scene and sound criteria, and optionally turn them into pieces. `include`: every criterion must hold at the same time (AND). `exclude`: passages that overlap any of these are dropped (they are still listed, marked excluded_by). Criteria: \"scene:<family>\" or \"sound:<family>\" (identifiers from analyze_media, e.g. scene:fire, scene:night, sound:laugh, sound:gunfire, sound:explosion, sound:music), \"label:<name>\" (raw macOS image label, e.g. label:fireworks) or \"sound_label:<name>\" (raw sound label, e.g. sound_label:gunshot_gunfire), or \"person:<id or name>\" (a character from list_subjects whose face is on screen, e.g. person:0 or person:House; needs the recognised characters), \"alone:<id or name>\" (that character is the only face on screen), \"speaks:<id or name>\" (the voice linked to that character is heard, even off screen) or \"voice:<id or name>\" (a voice from list_subjects, e.g. voice:2; works on audio-only files). Passages are smoothed (gaps under 1.5 s filled, under 1 s dropped) and, with whole_shots=true, widened to whole shots. apply=\"none\" (default) only lists them; \"add\" adds the kept passages to the existing pieces; \"set\" replaces the pieces. Analyzes the file first if needed.",
                properties: [("path", "string", "Absolute path of the file"), ("include", "array", "Criteria that must all hold, e.g. [\"scene:night\", \"sound:gunfire\"]"), ("exclude", "array", "Criteria that discard a passage, e.g. [\"sound:music\"]"),
                             ("whole_shots", "boolean", "Widen each passage to the whole shots it touches (default true); false adds a 0.3 s margin instead"), ("apply", "string", "none (default), add or set"),
                             ("min_scene_score", "number", "Minimum image-label confidence 0.05-0.95 (default 0.35)"), ("min_sound_score", "number", "Minimum sound confidence 0.05-0.95 (default 0.5)"), ("min_length", "number", "Shortest passage kept, in seconds (default 1)")], required: ["path", "include"]),
        ToolDef(name: "list_subjects", description: "List the voices and characters recognised in a file. Voices (grouped by speaker, id \"voice:0\", with the linked character when there is one) need analyze_media with voices=true. Characters (by their faces, grouped by person), the most present first: id (\"person:0\"), name (given by name_subject, else \"Character N\"), whether it was named, total seconds on screen, number of appearances, first and last time seen. Needs the characters to have been recognised: analyze_media with characters=true (optional model installed by the user).",
                properties: [("path", "string", "Absolute path of the file")], required: ["path"]),
        ToolDef(name: "name_subject", description: "Give a name to a recognised character or voice (stored with the file's analysis, shown in mSLICE's Find tab, usable in find_scenes as person:<name> / voice:<name>). An empty name makes it anonymous again. Names are limited to 40 characters. For a voice (subject \"voice:2\"), link_to_person links it to a character (\"person:0\", \"0\" or its name) so that speaks:<character> finds it; an empty link_to_person unlinks it.",
                properties: [("path", "string", "Absolute path of the file"), ("subject", "string", "The character (\"person:0\", \"0\" or its current name) or the voice (\"voice:2\")"), ("name", "string", "The new name (empty to clear)"), ("link_to_person", "string", "Voices only: the character this voice belongs to (empty to unlink)")], required: ["path", "subject", "name"]),
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
        guard !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\r" }) else { throw AgentError("The path contains control characters (refused).") }
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
        guard let v = timeRaw(any), v.isFinite else { return nil }       // NaN et infini refusés (min/max de Swift les laisseraient passer)
        return v
    }
    private static func timeRaw(_ any: Any?) -> Double? {
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
            guard let n = number(a["index"]), n >= 1, n <= Double(cur.count) else { throw AgentError("index must be between 1 and \(cur.count).") }      // comparé en Double : Int(1e30) planterait
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

        case "analyze_media":
            let i = try await info(try fileURL(a))
            let (index, fresh) = try await analysis(i, force: bool(a["force"]) ?? false, host: host)
            let chars: [String: Any]? = (bool(a["characters"]) ?? false) ? await recognizeCharacters(i, host: host) : nil
            let voices: [String: Any]? = (bool(a["voices"]) ?? false) ? await recognizeVoiceTool(i, host: host) : nil
            return analysisSummary(index, i, fresh: fresh, all: bool(a["all"]) ?? false, characters: chars, voices: voices)

        case "list_subjects":
            let i = try await info(try fileURL(a))
            let f = FaceStore.load(i), v = VoiceStore.load(i)
            guard f != nil || v != nil else { throw AgentError(noFaces) }
            return listSubjects(f, v, i)

        case "name_subject":
            return try await nameSubject(a, host: host)

        case "find_scenes":
            return try await findScenes(a, host: host)

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

    // MARK: Analyse et recherche

    /// Résultat d'analyse enregistré, sinon analyse du fichier (dans l'appli si le fichier y est ouvert : l'onglet « Trouver » montre la progression).
    static func analysis(_ i: MediaInfo, force: Bool, host: AgentHost?) async throws -> (AnalysisIndex, Bool) {
        if !force, let c = AnalysisStore.load(i) { return (c, false) }
        var idx: AnalysisIndex?
        if let host, host.segments(of: i.url) != nil { idx = await host.analyze(i.url, force: force) }
        if idx == nil { idx = await AnalysisRunner.run(i, job: AnalysisJob(), progress: { _ in }) }
        guard let idx else { throw AgentError("The analysis failed or was cancelled (is the file readable by macOS, with an image or sound track?).") }
        return (idx, true)
    }

    private static func englishName(_ t: FindTerm) -> String {
        switch t.kind {
        case .scene: return SceneFamilies.byID[t.key]?.names[1] ?? t.key
        case .sound: return SoundFamilies.byID[t.key]?.names[1] ?? t.key
        case .person: return t.label ?? "Character \((Int(t.key) ?? 0) + 1)"
        case .voice: return t.label ?? "Voice \((Int(t.key) ?? 0) + 1)"
        case .speaks: return "\(t.label ?? "Character \((Int(t.key) ?? 0) + 1)") speaks"
        case .alone: return "\(t.label ?? "Character \((Int(t.key) ?? 0) + 1)") alone on screen"
        default: return t.key
        }
    }

    static let noFaces = "No characters recognised in this file yet: call analyze_media with characters=true (needs the optional characters model, installed by the user from mSLICE's Find tab; the agent cannot download it)."

    private static func subjectRows(_ f: FaceIndex, limit: Int) -> [[String: Any]] {
        f.characters().prefix(limit).map { c in
            let iv = f.intervals(of: c.id)
            var d: [String: Any] = ["id": "person:\(c.id)", "name": f.names[c.id] ?? "Character \(c.id + 1)", "named": f.names[c.id] != nil, "seconds": r1(c.seconds), "appearances": c.appearances, "faces": c.faces]
            if let a = iv.first, let b = iv.last { d["first_seen"] = r1(a.start); d["last_seen"] = r1(b.end) }
            return d
        }
    }

    static func listSubjects(_ f: FaceIndex?, _ v: VoiceIndex?, _ i: MediaInfo) -> ToolOutput {
        var o: [String: Any] = ["file": i.url.path, "duration": r1(i.duration),
                                "hint": "Use find_scenes with include [\"person:<id or name>\"] (on screen), [\"alone:<…>\"], [\"speaks:<character>\"] or [\"voice:<id or name>\"]; name_subject gives a name."]
        if let f {
            let rows = subjectRows(f, limit: 50)
            o["count"] = f.characters().count; o["subjects"] = rows
            if f.characters().count > rows.count { o["note"] = "Only the 50 most present characters are listed." }
        }
        if let v {
            o["voices"] = v.voices().prefix(50).map { s -> [String: Any] in
                var d: [String: Any] = ["id": "voice:\(s.id)", "name": v.names[s.id] ?? "Voice \(s.id + 1)", "named": v.names[s.id] != nil, "seconds": r1(s.seconds), "turns": s.turns, "sample_start": r1(s.sample)]
                if let p = v.link[s.id] { d["linked_character"] = "person:\(p)"; if let n = f?.names[p] { d["linked_character_name"] = n } }
                return d
            }
        }
        return .json(o)
    }

    /// Reconnaissance des voix pour `analyze_media` : jamais de téléchargement ; sans modèle, le dit clairement.
    private static func recognizeVoiceTool(_ i: MediaInfo, host: AgentHost?) async -> [String: Any] {
        if i.audio == nil { return ["status": "no_audio"] }
        var fresh = false
        var v = VoiceStore.load(i)
        if v == nil {
            guard ModelFiles.isInstalled(ModelCatalog.voices) else {
                return ["status": "model_not_installed", "hint": "Ask the user to install the optional voices model in mSLICE's Find tab (Voices card). The agent cannot download it."]
            }
            if let host, host.segments(of: i.url) != nil { v = await host.recognizeVoices(i.url) }
            if v == nil { v = await AnalysisRunner.runVoices(i, job: AnalysisJob(), progress: { _ in }) }
            fresh = true
        }
        guard let v else { return ["status": "failed", "hint": "Voice recognition failed or was cancelled (is the model intact? the user can remove and download it again in the Find tab)."] }
        return ["status": "ok", "analyzed_now": fresh, "recognition_seconds": r1(v.seconds), "count": v.voices().count,
                "voices": v.voices().prefix(12).map { s -> [String: Any] in
                    var d: [String: Any] = ["id": "voice:\(s.id)", "name": v.names[s.id] ?? "Voice \(s.id + 1)", "seconds": r1(s.seconds), "turns": s.turns]
                    if let p = v.link[s.id] { d["linked_character"] = "person:\(p)" }
                    return d },
                "hint": "list_subjects gives all of them; find_scenes accepts voice:<id or name>, and speaks:<character> for a voice linked to a character."]
    }

    /// « voice:2 », « 2 » ou le nom d'une voix → critère de recherche.
    static func resolveVoice(_ spec: String, voices: VoiceIndex?, exclude: Bool) throws -> FindTerm {
        guard let v = voices else { throw AgentError("No voices recognised in this file yet: call analyze_media with voices=true (needs the optional voices model, installed by the user from mSLICE's Find tab; the agent cannot download it).") }
        var s = spec.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasPrefix("voice:") { s = String(s.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        let list = v.voices()
        var id: Int32?
        if let n = Int32(s) { id = list.contains { $0.id == n } ? n : nil }
        else if !s.isEmpty, s.count <= 80 {
            let m = list.filter { v.names[$0.id]?.lowercased() == s.lowercased() }
            if m.count > 1 { throw AgentError("Ambiguous voice name \"\(s.prefix(40))\": \(m.map { "voice:\($0.id)" }.joined(separator: ", ")). Use the id.") }
            id = m.first?.id
        }
        guard let id else { throw AgentError("Unknown voice \"\(s.prefix(40))\". Known: \(list.prefix(12).map { "voice:\($0.id)" + (v.names[$0.id].map { " (\($0.prefix(40)))" } ?? "") }.joined(separator: ", ")). Use list_subjects.") }
        return FindTerm(kind: .voice, key: String(id), exclude: exclude, label: v.names[id])
    }

    /// Reconnaissance des personnages pour `analyze_media` : jamais de téléchargement ; sans modèle, le dit clairement.
    private static func recognizeCharacters(_ i: MediaInfo, host: AgentHost?) async -> [String: Any] {
        if i.isAudioOnly || i.video == nil { return ["status": "no_video"] }
        var fresh = false
        var faces = FaceStore.load(i)
        if faces == nil {
            guard ModelFiles.isInstalled(ModelCatalog.characters) else {
                return ["status": "model_not_installed", "hint": "Ask the user to install the optional characters model in mSLICE's Find tab (Characters card). The agent cannot download it."]
            }
            if let host, host.segments(of: i.url) != nil { faces = await host.recognize(i.url) }
            if faces == nil { faces = await AnalysisRunner.runFaces(i, job: AnalysisJob(), progress: { _ in }) }
            fresh = true
        }
        guard let f = faces else { return ["status": "failed", "hint": "Recognition failed or was cancelled (is the model intact? the user can remove and download it again in the Find tab)."] }
        return ["status": "ok", "analyzed_now": fresh, "recognition_seconds": r1(f.seconds), "count": f.characters().count, "subjects": subjectRows(f, limit: 12),
                "hint": "list_subjects gives all of them; find_scenes accepts person:<id or name>."]
    }

    /// « person:3 », « 3 » ou le nom d'un personnage (sans tenir compte des majuscules) → critère de recherche.
    static func resolvePerson(_ spec: String, faces: FaceIndex?, exclude: Bool) throws -> FindTerm {
        guard let f = faces else { throw AgentError(noFaces) }
        var s = spec.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasPrefix("person:") { s = String(s.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        let chars = f.characters()
        func known() -> String { chars.prefix(12).map { "person:\($0.id)" + (f.names[$0.id].map { " (\($0.prefix(40)))" } ?? "") }.joined(separator: ", ") }
        var id: Int32?
        if let n = Int32(s) { id = chars.contains { $0.id == n } ? n : nil }
        else if !s.isEmpty, s.count <= 80 {
            let m = chars.filter { f.names[$0.id]?.lowercased() == s.lowercased() }
            if m.count > 1 { throw AgentError("Ambiguous character name \"\(s.prefix(40))\": \(m.map { "person:\($0.id)" }.joined(separator: ", ")). Use the id.") }
            id = m.first?.id
        }
        guard let id else { throw AgentError("Unknown character \"\(s.prefix(40))\". Known: \(known()). Use list_subjects.") }
        return FindTerm(kind: .person, key: String(id), exclude: exclude, label: f.names[id])
    }

    private static func nameVoice(_ a: [String: Any], _ i: MediaInfo, host: AgentHost?) throws -> ToolOutput {
        guard var v = VoiceStore.load(i) else { throw AgentError("No voices recognised in this file yet: call analyze_media with voices=true.") }
        let t = try resolveVoice(a["subject"] as? String ?? "", voices: v, exclude: false)
        let id = Int32(t.key) ?? 0
        guard let raw = a["name"] as? String, raw.count <= 500 else { throw AgentError("name is required (use an empty string to clear it) and must be shorter than 500 characters.") }
        var person: Int32?
        if let l = a["link_to_person"] as? String {
            if l.trimmingCharacters(in: .whitespaces).isEmpty { person = -1 }
            else { person = Int32(try resolvePerson(l, faces: FaceStore.load(i), exclude: false).key) }
        }
        var next = v; next.rename(id, to: raw)
        if let person { if person >= 0 { for (k, p) in next.link where p == person && k != id { next.link[k] = nil } }; next.setLink(id, to: person >= 0 ? person : nil) }
        var live = false
        if let host, host.editVoice(id, name: raw, person: person, of: i.url) { live = true }
        else { v = next; guard VoiceStore.save(v, for: i) else { throw AgentError("The name could not be saved.") } }
        let name = next.names[id]
        var o: [String: Any] = ["file": i.url.path, "id": "voice:\(id)", "name": name ?? "Voice \(id + 1)", "named": name != nil, "live_in_app": live]
        if let p = next.link[id] { o["linked_character"] = "person:\(p)" }
        return .json(o)
    }

    private static func nameSubject(_ a: [String: Any], host: AgentHost?) async throws -> ToolOutput {
        let i = try await info(try fileURL(a))
        if let sub = a["subject"] as? String, sub.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("voice:") { return try nameVoice(a, i, host: host) }
        guard var f = FaceStore.load(i) else { throw AgentError(noFaces) }
        guard let subject = a["subject"] as? String, !subject.isEmpty else { throw AgentError("subject is required: \"person:0\", \"0\" or the character's name.") }
        guard let raw = a["name"] as? String, raw.count <= 500 else { throw AgentError("name is required (use an empty string to clear it) and must be shorter than 500 characters.") }
        let t = try resolvePerson(subject, faces: f, exclude: false)
        let id = Int32(t.key) ?? 0
        var next = f; next.rename(id, to: raw)
        var live = false
        if let host, host.renameSubject(id, to: raw, of: i.url) { live = true }
        else { f = next; guard FaceStore.save(f, for: i) else { throw AgentError("The name could not be saved.") } }
        let name = next.names[id]
        return .json(["file": i.url.path, "id": "person:\(id)", "name": name ?? "Character \(id + 1)", "named": name != nil, "live_in_app": live])
    }

    static func analysisSummary(_ index: AnalysisIndex, _ i: MediaInfo, fresh: Bool, all: Bool, characters: [String: Any]? = nil, voices: [String: Any]? = nil) -> ToolOutput {
        let s = Finder(index).summary()
        func rows(_ r: [SummaryRow]) -> [[String: Any]] { (all ? r : Array(r.prefix(25))).map { ["id": $0.term.token, "name": englishName($0.term), "seconds": r1($0.seconds), "passages": $0.count] } }
        var o: [String: Any] = ["file": i.url.path, "duration": r1(i.duration), "analyzed_now": fresh, "analysis_seconds": r1(index.seconds), "has_video": index.hasVideo, "has_audio": index.hasAudio,
                                "scenes": rows(s.scenes), "sounds": rows(s.sounds),
                                "hint": "Use find_scenes with include / exclude criteria such as \"scene:fire\" or \"sound:laugh\"; label:<name> and sound_label:<name> reach the raw macOS labels."]
        if index.hasVideo { o["shots"] = index.shotCount }
        if let characters { o["characters"] = characters }
        if let voices { o["voices"] = voices }
        if !all, s.scenes.count > 25 || s.sounds.count > 25 { o["note"] = "Only the 25 longest of each kind are listed; pass all=true for the rest." }
        return .json(o)
    }

    private static func findScenes(_ a: [String: Any], host: AgentHost?) async throws -> ToolOutput {
        let i = try await info(try fileURL(a))
        let faces = FaceStore.load(i), voices = VoiceStore.load(i)
        func terms(_ key: String, exclude: Bool) throws -> [FindTerm] {
            guard let list = a[key] as? [Any] else { return [] }
            return try list.map { any in
                if let s = any as? String {
                    let low = s.trimmingCharacters(in: .whitespaces).lowercased()
                    if low.hasPrefix("person:") { return try resolvePerson(s, faces: faces, exclude: exclude) }
                    if low.hasPrefix("alone:") || low.hasPrefix("speaks:") {
                        let alone = low.hasPrefix("alone:")
                        var t = try resolvePerson(String(s.trimmingCharacters(in: .whitespaces).dropFirst(alone ? 6 : 7)), faces: faces, exclude: exclude)
                        t.kind = alone ? .alone : .speaks
                        if !alone, !(voices?.link.values.contains(Int32(t.key) ?? -1) ?? false) { throw AgentError("No voice is linked to \(t.token.replacingOccurrences(of: "speaks:", with: "person:")): recognise the voices (analyze_media voices=true) and, if needed, link one with name_subject (subject \"voice:N\", link_to_person).") }
                        return t
                    }
                    if low.hasPrefix("voice:") { return try resolveVoice(s, voices: voices, exclude: exclude) }
                }
                guard let s = any as? String, let t = FindTerm.parse(s.trimmingCharacters(in: .whitespaces), exclude: exclude) else { throw AgentError("Bad criterion \"\("\(any)".prefix(60))\": use scene:<family>, sound:<family>, label:<name>, sound_label:<name>, person:/alone:/speaks:<id or name> or voice:<id or name>.") }
                if t.kind == .scene, SceneFamilies.byID[t.key] == nil { throw AgentError("Unknown scene family \"\(t.key.prefix(40))\". Known: \(SceneFamilies.all.map(\.id).joined(separator: ", ")).") }
                if t.kind == .sound, SoundFamilies.byID[t.key] == nil { throw AgentError("Unknown sound family \"\(t.key.prefix(40))\". Known: \(SoundFamilies.all.map(\.id).joined(separator: ", ")).") }
                return t
            }
        }
        let inc = try terms("include", exclude: false), exc = try terms("exclude", exclude: true)
        guard !inc.isEmpty, inc.count + exc.count <= 12 else { throw AgentError("include must list 1 to 12 criteria in total with exclude (e.g. [\"scene:fire\"]).") }
        let apply = (a["apply"] as? String)?.lowercased() ?? "none"
        guard ["none", "add", "set"].contains(apply) else { throw AgentError("apply must be none, add or set.") }
        var q = FindQuery(terms: inc + exc)
        q.wholeShots = bool(a["whole_shots"]) ?? true
        if let v = number(a["min_scene_score"]) { q.sceneMin = min(max(v, 0.05), 0.95) }
        if let v = number(a["min_sound_score"]) { q.soundMin = min(max(v, 0.05), 0.95) }
        if let v = number(a["min_length"]) { q.minLength = min(max(v, 0.5), 30) }
        let (index, fresh) = try await analysis(i, force: false, host: host)
        let finder = Finder(index, faces: faces, voices: voices)
        var notes: [String] = []
        for t in inc + exc {
            if t.needsVideo && !index.hasVideo { throw AgentError("This file has no video: image criteria (\(t.token)) cannot match. Use sound criteria.") }
            if (t.isSound || t.kind == .voice || t.kind == .speaks) && !index.hasAudio { throw AgentError("This file has no audio: sound criteria (\(t.token)) cannot match.") }
            if !finder.knows(t) { notes.append("\(t.token) never appears in this file.") }
        }
        let r = finder.run(q)
        var o: [String: Any] = ["file": i.url.path, "analyzed_now": fresh, "include": inc.map(\.token), "exclude": exc.map(\.token), "whole_shots": q.wholeShots,
                                "passages_found": r.passages.count, "passages_kept": r.passages.filter { $0.excludedBy == nil }.count, "kept_seconds": r1(r.keptSeconds)]
        o["passages"] = r.passages.prefix(200).enumerated().map { n, p -> [String: Any] in
            var d: [String: Any] = ["index": n + 1, "start": r1(p.start), "end": r1(p.end), "duration": r1(p.duration), "start_text": Fmt.time(p.start), "end_text": Fmt.time(p.end)]
            if let by = p.excludedBy { d["excluded_by"] = by }
            return d
        }
        if r.passages.count > 200 { o["truncated"] = true }
        if !notes.isEmpty { o["notes"] = notes }
        let found = r.segments.map { Segment(start: $0.start, end: $0.end) }
        if apply == "none" || found.isEmpty {
            if apply != "none" { o["applied"] = false; o["note"] = "Nothing to apply: no passage matches." }
            o["pieces_if_applied"] = r.segments.count
            return .json(o)
        }
        let segs = normalize(apply == "add" ? currentSegments(i, host: host).segs + found : found, duration: i.duration)
        let live = store(segs, i, host: host)
        host?.notify("Agent : \(found.count) \(found.count > 1 ? "morceaux trouvés" : "morceau trouvé")")
        o["applied"] = apply; o["live_in_app"] = live; o["count"] = segs.count; o["kept_total_seconds"] = r1(segs.reduce(0) { $0 + $1.duration }); o["segments"] = rows(segs)
        return .json(o)
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
        // Rotation : au-delà de 1 Mo, on garde la seconde moitié du journal.
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize), size > 1_048_576, let d = try? Data(contentsOf: url) {
            let tail = d.suffix(d.count / 2); let cut = tail.firstIndex(of: 10).map { tail.index(after: $0) } ?? tail.startIndex
            try? Data(tail[cut...]).write(to: url, options: .atomic)
        }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8); try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
    }
}
