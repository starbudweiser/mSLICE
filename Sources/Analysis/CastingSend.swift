// mSLICE — envoi des répliques à mCASTING : un paquet `mcasting-inbox/1` (même contrat que mTALKIE, voir mCASTING/docs/INBOX.md) déposé dans
// `~/Library/Application Support/mCASTING/Inbox/` : écrit sous un nom caché puis renommé, jamais lu à moitié. `kind: lines`, source `series` / `film` / `other`,
// une réplique = texte, personnage, langue, durée, étiquettes, audio AAC (marges −0,15 / +0,25 s, canal du centre des fichiers 5.1, voix seule en option).
// Sans interface : partagé avec `mslice-mcp`.
import AppKit
import Foundation

struct CastingLine: Sendable {
    var start: Double, end: Double
    var text: String
    var character: String?
}

struct CastingOptions: Sendable {
    var kind = "series"                    // series, film, other
    var title = ""
    var episode = ""
    var lang = "fr"
    var audio = true
    var isolate = false                    // voix seule
    var tags = true                        // étiquettes automatiques d'après le texte
}

enum CastingSend {
    static let bundleID = "fr.stephan.mcasting"
    static let marginBefore = 0.15, marginAfter = 0.25

    /// Dossier de données de mCASTING : `MCASTING_HOME` (essais) ; l'édition de développement de mSLICE écrit dans celle de mCASTING si elle existe.
    static var home: URL {
        if let p = ProcessInfo.processInfo.environment["MCASTING_HOME"] { return URL(fileURLWithPath: p) }
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        if Env.isDev, FileManager.default.fileExists(atPath: base.appendingPathComponent("mCASTING-dev").path) { return base.appendingPathComponent("mCASTING-dev") }
        return base.appendingPathComponent("mCASTING")
    }
    static var inbox: URL { home.appendingPathComponent("Inbox") }
    /// mCASTING est-il présent (dossier de données déjà créé, ou appli installée) ?
    static var available: Bool { FileManager.default.fileExists(atPath: home.path) || NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }

    // MARK: Identifiants et durées

    /// « Stranger Things · Saison 4 » → « stranger-things-saison-4 » (lettres et chiffres, sans accents).
    static func slug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var out = "", dash = false
        for ch in folded { if ch.isASCII, ch.isLetter || ch.isNumber { out.append(ch); dash = false } else if !dash, !out.isEmpty { out.append("-"); dash = true } }
        while out.hasSuffix("-") { out.removeLast() }
        return String(out.prefix(60))
    }

    /// Plage audio de chaque réplique : marges avant et après, sans empiéter sur la réplique voisine ni sortir du fichier.
    static func spans(_ lines: [CastingLine], duration: Double) -> [(start: Double, end: Double)] {
        lines.indices.map { i in
            let l = lines[i]
            var a = l.start - marginBefore, b = l.end + marginAfter
            if i > 0 { a = l.start - min(marginBefore, max(l.start - lines[i - 1].end, 0) / 2) }       // la marge se partage avec la réplique d'avant
            if i + 1 < lines.count { b = l.end + min(marginAfter, max(lines[i + 1].start - l.end, 0) / 2) }
            return (max(a, 0), min(b, duration))
        }
    }

    // MARK: Étiquettes automatiques (d'après le texte ; mêmes règles que mTALKIE)

    static func autoTags(_ text: String) -> [String] {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        var out: [String] = []
        let words = Set(t.split { !$0.isLetter && $0 != "'" }.map(String.init))
        if t.range(of: #"\b(ha){2,}|\b(he){2,}|\b(hi){2,}|\bmwa|\bbwa|\blol\b"#, options: .regularExpression) != nil { out.append("laugh") }
        let letters = t.filter(\.isLetter)
        if letters.count <= 12, t.contains("!"), letters.count >= 1,
           t.range(of: #"^(a+h+|o+h+|a+r+g+h*|a+i+e+|ouch|ouille|aï+e|yaa+h?|no+!|n+o+n+|wa+h|e+e+k|ugh|ayy+)"#, options: .regularExpression) != nil { out.append("scream") }
        let insults = ["idiot", "fool", "stupid", "moron", "coward", "imbécile", "idiote", "crétin", "abruti", "lâche", "imbecil", "estúpido", "cobarde", "stupido", "codardo", "scemo", "connard", "salaud", "gros"]
        if !words.isDisjoint(with: insults) || t.contains("you fight like") || t.contains("tu te bats comme") { out.append("insult") }
        let greet = ["hello", "hi", "hey", "greetings", "howdy", "bonjour", "salut", "bonsoir", "hola", "buenas", "ciao", "salve", "buongiorno"]
        if let first = t.split(whereSeparator: { !$0.isLetter }).first, greet.contains(String(first)) { out.append("greeting") }
        if t.hasSuffix("?") || t.contains("? ") { out.append("question") }
        let threat = ["kill", "die", "destroy", "revenge", "doom", "tuer", "mourir", "détruire", "vengeance", "matar", "morir", "venganza", "uccidere", "morire", "vendetta", "frapper"]
        if !words.isDisjoint(with: threat) { out.append("threat") }
        if t.hasSuffix("!") && !out.contains("scream") { out.append("exclamation") }
        return out
    }

    // MARK: Paquet

    struct Source: Encodable { var kind: String; var title: String; var id: String }
    struct LinePart: Encodable { var key: String; var text: String; var character: String?; var lang: String?; var duration: Double; var tags: [String]?; var audio: String? }
    struct Manifest: Encodable { var format = "mcasting-inbox/1"; var kind = "lines"; var origin: [String: String]; var source: Source; var lines: [LinePart] }

    struct Result: Sendable { var count: Int; var perCharacter: [(name: String, count: Int)]; var package: URL; var sourceID: String; var withAudio: Int }
    enum Failure: Error { case noCasting, noAudio, isolation, ffmpeg, cancelled, write }

    static func sourceTitle(_ o: CastingOptions) -> String { o.episode.trimmingCharacters(in: .whitespaces).isEmpty ? o.title : o.title + " · " + o.episode }

    /// Fabrique le paquet et le publie. `progress` : 0…1.
    static func send(_ info: MediaInfo, lines: [CastingLine], options o: CastingOptions, job: AnalysisJob, progress: @escaping @Sendable (Double) -> Void) async throws -> Result {
        guard !lines.isEmpty else { throw Failure.write }
        let fm = FileManager.default
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let sid = slug(sourceTitle(o)).isEmpty ? "mslice" : slug(sourceTitle(o))
        let tmp = inbox.appendingPathComponent(".lines-\(sid)-\(stamp).tmp")
        try? fm.removeItem(at: tmp)
        try fm.createDirectory(at: tmp.appendingPathComponent("audio"), withIntermediateDirectories: true)
        let work = fm.temporaryDirectory.appendingPathComponent("mslice-cast-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        do {
            var parts: [LinePart] = []
            let spans = spans(lines, duration: info.duration)
            var source = info.url, mono = false              // `mono` : source déjà en mono (voix seule)
            let wantAudio = o.audio && info.audio != nil
            if wantAudio, o.isolate {
                guard VoiceIsolation.available, let ff = Tools.ffmpeg else { throw Failure.isolation }
                let wav = work.appendingPathComponent("full.wav"), iso = work.appendingPathComponent("voice.wav")
                let r = await Run.exec(ff, ["-v", "error", "-y", "-nostdin", "-i", info.url.path, "-map", "0:a:0", "-vn"] + downmix(info) + ["-ar", "48000", "-c:a", "pcm_s16le", wav.path])
                guard r.status == 0 else { throw Failure.ffmpeg }
                if job.cancelled { throw Failure.cancelled }
                progress(0.05)
                guard await VoiceIsolation.run(input: wav, output: iso, job: job, progress: { progress(0.05 + 0.45 * $0) }) else { throw job.cancelled ? Failure.cancelled : Failure.isolation }
                source = iso; mono = true
            }
            let base = o.isolate && wantAudio ? 0.5 : 0.0
            // coupe l'audio de chaque réplique (quatre ffmpeg à la fois)
            var audioFiles = [String?](repeating: nil, count: lines.count)
            if wantAudio {
                guard let ff = Tools.ffmpeg else { throw Failure.ffmpeg }
                let filter = mono ? ["-ac", "1"] : downmix(info)
                var next = 0, finished = 0
                try await withThrowingTaskGroup(of: (Int, Bool).self) { g in
                    func add(_ i: Int) {
                        g.addTask {
                            let rel = "audio/\(sid)-\(String(format: "%04d", i + 1)).aac"
                            let a = spans[i]
                            let r = await Run.exec(ff, ["-v", "error", "-y", "-nostdin", "-ss", String(format: "%.3f", a.start), "-t", String(format: "%.3f", max(a.end - a.start, 0.05)), "-i", source.path, "-map", "0:a:0", "-vn"]
                                                   + filter + ["-ar", "22050", "-c:a", "aac", "-b:a", "32k", "-f", "adts", tmp.appendingPathComponent(rel).path])
                            return (i, r.status == 0)
                        }
                    }
                    while next < min(4, lines.count) { add(next); next += 1 }
                    while let (i, ok) = try await g.next() {
                        if ok { audioFiles[i] = "audio/\(sid)-\(String(format: "%04d", i + 1)).aac" }
                        finished += 1
                        progress(base + (1 - base) * Double(finished) / Double(lines.count))
                        if job.cancelled { g.cancelAll(); throw Failure.cancelled }
                        if next < lines.count { add(next); next += 1 }
                    }
                }
            }
            if job.cancelled { throw Failure.cancelled }
            for (i, l) in lines.enumerated() {
                let tg = o.tags ? autoTags(l.text) : []
                parts.append(LinePart(key: "\(sid)-\(String(format: "%04d", i + 1))", text: l.text, character: l.character, lang: o.lang.isEmpty ? nil : o.lang,
                                      duration: ((audioFiles[i] != nil ? spans[i].end - spans[i].start : l.end - l.start) * 100).rounded() / 100, tags: tg.isEmpty ? nil : tg, audio: audioFiles[i]))
            }
            let m = Manifest(origin: ["app": "mSLICE", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"],
                             source: Source(kind: o.kind, title: sourceTitle(o), id: sid), lines: parts)
            let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try e.encode(m).write(to: tmp.appendingPathComponent("manifest.json"))
            let final = inbox.appendingPathComponent("lines-\(sid)-\(stamp)")
            try? fm.removeItem(at: final)
            try fm.moveItem(at: tmp, to: final)
            var per: [String: Int] = [:]
            for l in lines { per[l.character ?? "", default: 0] += 1 }
            let sorted = per.filter { !$0.key.isEmpty }.map { (name: $0.key, count: $0.value) }.sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            return Result(count: parts.count, perCharacter: sorted, package: final, sourceID: sid, withAudio: audioFiles.compactMap { $0 }.count)
        } catch { try? fm.removeItem(at: tmp); throw error }
    }

    /// Réduction à une voix : le canal du centre des fichiers 5.1 (les dialogues y sont), sinon mélange en mono.
    static func downmix(_ info: MediaInfo) -> [String] {
        (info.audio?.channels ?? 2) >= 6 ? ["-af", "pan=mono|c0=FC"] : ["-ac", "1"]
    }
}
