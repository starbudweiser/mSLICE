// mSLICE — sous-titres : pistes texte intégrées (subrip, ass / ssa, mov_text, webvtt ; extraites par le ffmpeg embarqué) et fichiers de même nom à côté de la vidéo
// (.srt, .<langue>.srt, .ass, .vtt). Analyse SRT / ASS / VTT : balises retirées, noms des malentendants (« STEVE : », « [Steve] ») gardés à part, didascalies
// « (musique) » écartées, répliques à tirets « - … / - … » séparées. Sous-titres en image (PGS, VobSub) : non pris en charge (la transcription les remplace).
// Sans interface : partagé avec `mslice-mcp`.
import Foundation

/// Un sous-titre brut avant nettoyage.
struct SubCue: Equatable, Sendable {
    var start: Double
    var end: Double
    var lines: [String]
    var actor: String? = nil               // ASS : colonne « Name » ; WebVTT : balise <v Nom>
}

/// Une source de sous-titres proposée à l'utilisateur.
struct SubtitleSource: Identifiable, Equatable, Sendable {
    enum Origin: Equatable, Sendable { case embedded(stream: Int, codec: String), file(URL) }
    var origin: Origin
    var language: String                   // code déclaré (« fre », « fr »…), vide si inconnu
    var title: String
    var id: String {
        switch origin { case .embedded(let s, _): "s\(s)"; case .file(let u): "f" + u.lastPathComponent }
    }
    var isEmbedded: Bool { if case .embedded = origin { true } else { false } }
}

enum Subtitles {
    static let textCodecs: Set<String> = ["subrip", "srt", "ass", "ssa", "mov_text", "webvtt", "text", "subviewer", "microdvd"]
    static let fileExtensions = ["srt", "ass", "ssa", "vtt"]

    // MARK: Sources

    /// Pistes texte intégrées, puis fichiers à côté de la vidéo.
    static func sources(for info: MediaInfo) -> [SubtitleSource] {
        var out: [SubtitleSource] = []
        for s in info.streams where s.kind == "subtitle" && textCodecs.contains(s.codec) {
            out.append(SubtitleSource(origin: .embedded(stream: s.index, codec: s.codec), language: s.lang, title: s.title))
        }
        out += siblingFiles(of: info.url)
        return out
    }

    /// « Film.srt », « Film.fr.srt », « Film.French.srt », « Film.ass », « Film.vtt » dans le dossier de la vidéo.
    static func siblingFiles(of video: URL) -> [SubtitleSource] {
        let dir = video.deletingLastPathComponent()
        let base = video.deletingPathExtension().lastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        var out: [SubtitleSource] = []
        for n in names.sorted() {
            let u = dir.appendingPathComponent(n)
            guard fileExtensions.contains(u.pathExtension.lowercased()) else { continue }
            let stem = u.deletingPathExtension().lastPathComponent
            guard stem == base || stem.hasPrefix(base + ".") else { continue }
            let lang = stem == base ? "" : String(stem.dropFirst(base.count + 1))
            guard lang.count <= 24, !lang.contains("/") else { continue }
            out.append(SubtitleSource(origin: .file(u), language: lang, title: ""))
        }
        return out
    }

    // MARK: Chargement

    /// Lit une source et rend les répliques nettoyées ; nil si illisible ou vide.
    static func load(_ source: SubtitleSource, info: MediaInfo) async -> [DialogueLine]? {
        guard let text = await rawText(source, info: info) else { return nil }
        let lines = dialogue(from: parse(text))
        return lines.isEmpty ? nil : lines
    }

    private static func rawText(_ source: SubtitleSource, info: MediaInfo) async -> String? {
        switch source.origin {
        case .file(let u):
            guard let d = try? Data(contentsOf: u), d.count < 20_000_000 else { return nil }
            return decode(d)
        case .embedded(let stream, let codec):
            guard let ff = Tools.ffmpeg else { return nil }
            let ass = codec == "ass" || codec == "ssa"
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-sub-\(UUID().uuidString).\(ass ? "ass" : "srt")")
            defer { try? FileManager.default.removeItem(at: tmp) }
            let r = await Run.exec(ff, ["-v", "error", "-y", "-nostdin", "-i", info.url.path, "-map", "0:\(stream)", "-f", ass ? "ass" : "srt", tmp.path])
            guard r.status == 0, let d = try? Data(contentsOf: tmp), d.count < 20_000_000 else { return nil }
            return decode(d)
        }
    }

    /// UTF-8 (avec ou sans BOM), UTF-16 (BOM), sinon Windows-1252 (fichiers anciens).
    static func decode(_ d: Data) -> String? {
        if d.starts(with: [0xFF, 0xFE]) || d.starts(with: [0xFE, 0xFF]) { return String(data: d, encoding: .utf16) }
        if let s = String(data: d, encoding: .utf8) { return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s }
        return String(data: d, encoding: .windowsCP1252) ?? String(data: d, encoding: .isoLatin1)
    }

    // MARK: Analyse

    /// Reconnaît le format par son contenu : ASS (« [Events] »), WebVTT (« WEBVTT »), sinon SRT.
    static func parse(_ text: String) -> [SubCue] {
        let t = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if t.contains("[Events]") { return parseASS(t) }
        return parseBlocks(t, vtt: t.hasPrefix("WEBVTT") || t.contains("\nWEBVTT"))
    }

    /// 00:01:02,345 · 1:02.345 · 62.5
    static func parseTime(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard (1 ... 3).contains(parts.count) else { return nil }
        var total = 0.0
        for p in parts { guard let v = Double(p), v >= 0, v.isFinite else { return nil }; total = total * 60 + v }
        return total
    }

    /// SRT et WebVTT : des blocs séparés par une ligne vide, avec une ligne « début --> fin ».
    static func parseBlocks(_ t: String, vtt: Bool) -> [SubCue] {
        var cues: [SubCue] = []
        for block in t.components(separatedBy: "\n\n") {
            let ls = block.components(separatedBy: "\n")
            guard let ti = ls.firstIndex(where: { $0.contains("-->") }) else { continue }
            let halves = ls[ti].components(separatedBy: "-->")
            guard halves.count == 2, let a = parseTime(halves[0]),
                  let b = parseTime(halves[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""), b > a else { continue }
            let body = Array(ls[(ti + 1)...]).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if body.isEmpty { continue }
            var actor: String?
            if vtt, let m = body.first.flatMap({ firstMatch(#"<v(?:\.[^ >]*)?\s+([^>]+)>"#, in: $0) }) { actor = m.trimmingCharacters(in: .whitespaces) }
            cues.append(SubCue(start: a, end: b, lines: body, actor: actor))
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// ASS / SSA : colonnes lues dans la ligne « Format: » de [Events], texte = dernière colonne (peut contenir des virgules).
    static func parseASS(_ t: String) -> [SubCue] {
        var inEvents = false, cols: [String] = []
        var cues: [SubCue] = []
        for raw in t.components(separatedBy: "\n") {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("[") { inEvents = l.lowercased() == "[events]"; continue }
            guard inEvents else { continue }
            if l.lowercased().hasPrefix("format:") { cols = l.dropFirst(7).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }; continue }
            guard l.lowercased().hasPrefix("dialogue:"), !cols.isEmpty else { continue }
            let f = l.dropFirst(9).split(separator: ",", maxSplits: cols.count - 1, omittingEmptySubsequences: false).map { String($0) }
            guard f.count == cols.count, let si = cols.firstIndex(of: "start"), let ei = cols.firstIndex(of: "end"), let ti = cols.firstIndex(of: "text"),
                  let a = parseTime(f[si]), let b = parseTime(f[ei]), b > a else { continue }
            var text = f[ti]
            if text.contains("{\\p1") || text.contains("{\\p2") { continue }                 // dessin vectoriel, pas du texte
            text = text.replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\h", with: " ")
            text = text.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
            let name = cols.firstIndex(of: "name").map { f[$0].trimmingCharacters(in: .whitespaces) }
            let actor = (name?.isEmpty == false && name?.lowercased() != "default") ? name : nil
            cues.append(SubCue(start: a, end: b, lines: text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, actor: actor))
        }
        return cues.sorted { $0.start < $1.start }
    }

    // MARK: Nettoyage

    private static let notNames: Set<String> = [
        "rires", "rire", "musique", "applaudissements", "soupir", "soupirs", "silence", "bruit", "bruits", "cris", "fin", "sonnerie", "téléphone", "générique",
        "laughs", "laughter", "music", "sighs", "applause", "silence", "noise", "screams", "phone", "ringing", "risas", "música", "aplausos", "suspiros",
        "risate", "musica", "applausi", "sospiri",
    ]

    /// Des sous-titres bruts aux répliques : balises, didascalies, noms SDH, tirets de dialogue. Le temps d'un sous-titre à plusieurs répliques est réparti
    /// proportionnellement à la longueur de leur texte.
    static func dialogue(from cues: [SubCue]) -> [DialogueLine] {
        var out: [DialogueLine] = []
        for cue in cues {
            var turns: [[String]] = []          // chaque tour de parole = ses lignes
            var anyDash = false
            let cleaned = cue.lines.map { stripMarkup($0) }
            for l in cleaned { if dashPrefix(l) != nil { anyDash = true } }
            for l in cleaned {
                let (isDash, body) = anyDash ? (dashPrefix(l) != nil, dashPrefix(l) ?? l) : (false, l)
                if turns.isEmpty || isDash { turns.append([body]) } else { turns[turns.count - 1].append(body) }
            }
            var items: [(who: String?, text: String)] = []
            for turn in turns {
                let (who, text) = splitSpeaker(turn.joined(separator: " "))
                let t = DialogueText.sanitize(text)
                guard t.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
                items.append((who ?? cue.actor, t))
            }
            guard !items.isEmpty else { continue }
            let total = Double(items.reduce(0) { $0 + max($1.text.count, 1) })
            var t0 = cue.start
            for (k, it) in items.enumerated() {
                let share = Double(max(it.text.count, 1)) / total
                let t1 = k == items.count - 1 ? cue.end : min(t0 + (cue.end - cue.start) * share, cue.end)
                if t1 > t0 { out.append(DialogueLine(start: t0, end: t1, text: it.text, who: it.who.map(normalizeName))) }
                t0 = t1
            }
        }
        return out
    }

    /// Balises HTML / ASS, entités, notes de musique, didascalies entre parenthèses ou crochets (sauf un nom en tête, traité plus loin).
    static func stripMarkup(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: #"\{\\[^}]*\}"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        for (a, b) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&rsquo;", "’")] { s = s.replacingOccurrences(of: a, with: b) }
        if s.contains("♪") || s.contains("♫") || s.contains("♬") { return "" }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Tiret de dialogue en tête (« - Oui », « – Non », « — Peut-être »), rendu sans le tiret ; nil s'il n'y en a pas.
    static func dashPrefix(_ s: String) -> String? {
        guard let f = s.first, "-–—‐‑".contains(f) else { return nil }
        return s.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    /// Nom du locuteur en tête (« STEVE : texte », « [Steve] texte », « (Steve) texte ») et didascalies retirées. Rend (nom, texte).
    static func splitSpeaker(_ s: String) -> (String?, String) {
        var text = s.trimmingCharacters(in: .whitespaces)
        var who: String?
        // [Nom] ou (Nom) en tête, suivi de texte
        if let m = firstMatch(#"^[\[(]([^\])]{1,30})[\])]\s*:?\s*(.*)$"#, in: text, groups: 2) {
            let name = m[0].trimmingCharacters(in: .whitespaces), rest = m[1]
            if looksLikeName(name), !rest.isEmpty { who = name; text = rest }
        } else if let m = firstMatch(#"^([A-ZÀ-ÖØ-Þ][A-ZÀ-ÖØ-Þ0-9'’.\- ]{0,28}?)\s*:\s*(\S.*)$"#, in: text, groups: 2),
                  m[0].filter({ $0.isLetter }).count >= 2, !m[0].contains(where: { $0.isLowercase }), !notNames.contains(m[0].lowercased()) {
            who = m[0]; text = m[1]
        }
        // didascalies restantes : (soupire), [rires], (en riant)
        text = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        return (who, text.trimmingCharacters(in: .whitespaces))
    }

    private static func looksLikeName(_ n: String) -> Bool {
        guard let f = n.first, f.isUppercase, !n.contains(","), n.split(separator: " ").count <= 3, !notNames.contains(n.lowercased()) else { return false }
        return true
    }

    /// « STEVE » → « Steve » ; un nom déjà en casse mixte est gardé.
    static func normalizeName(_ n: String) -> String {
        let t = n.trimmingCharacters(in: .whitespaces)
        return t.contains(where: { $0.isLowercase }) ? t : t.capitalized
    }

    // MARK: Expressions régulières

    private static func firstMatch(_ pattern: String, in s: String) -> String? { firstMatch(pattern, in: s, groups: 1)?.first }

    private static func firstMatch(_ pattern: String, in s: String, groups: Int) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        var out: [String] = []
        for g in 1 ... groups {
            let r = m.range(at: g)
            out.append(r.location == NSNotFound ? "" : (Range(r, in: s).map { String(s[$0]) } ?? ""))
        }
        return out
    }
}
