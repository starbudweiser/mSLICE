// mSLICE — répliques d'un fichier (onglet « Dialogues ») : une réplique = un début, une fin, un texte, éventuellement le nom écrit dans les sous-titres
// (« STEVE : … »), un drapeau « écartée » et un drapeau « corrigée ». Gardées à côté de l'index d'analyse (même clé, extension .msdialog), versionnées.
// Sans interface : partagé avec `mslice-mcp`.
import Foundation

struct DialogueLine: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
    var who: String?                       // nom donné par les sous-titres (SDH, acteur ASS, balise <v> WebVTT)
    var discarded = false
    var corrected = false
    var duration: Double { max(end - start, 0) }
}

/// D'où vient le texte : sous-titres (intégrés ou fichier) ou transcription de macOS.
enum DialogueKind: String, Codable, Sendable { case subtitles, transcript }

struct DialogueSet: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version = DialogueSet.currentVersion
    var duration: Double
    var created = Date()
    var kind: DialogueKind
    var detail = ""                        // piste ou fichier choisi, ou langue de la transcription
    var language = ""
    var lines: [DialogueLine] = []

    var active: [DialogueLine] { lines.filter { !$0.discarded } }

    // MARK: Corrections (logique pure, essayée par `--selftest-dialogues`)

    mutating func setText(_ id: UUID, _ raw: String) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        let t = DialogueText.sanitize(raw)
        guard !t.isEmpty, t != lines[i].text else { return }
        lines[i].text = t; lines[i].corrected = true
    }

    mutating func setDiscarded(_ id: UUID, _ value: Bool) {
        if let i = lines.firstIndex(where: { $0.id == id }) { lines[i].discarded = value }
    }

    /// Coupe une réplique en deux à la position `offset` (caractères) du texte ; le temps est réparti proportionnellement. Rend l'identifiant de la seconde moitié.
    @discardableResult mutating func split(_ id: UUID, atOffset offset: Int) -> UUID? {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return nil }
        let chars = Array(lines[i].text)
        guard offset > 0, offset < chars.count else { return nil }
        let a = String(chars[..<offset]).trimmingCharacters(in: .whitespacesAndNewlines)
        let b = String(chars[offset...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty else { return nil }
        let l = lines[i]
        let share = Double(a.count) / Double(a.count + b.count)
        let mid = l.start + (l.end - l.start) * share
        var first = l; first.text = a; first.end = mid; first.corrected = true
        var second = l; second.id = UUID(); second.text = b; second.start = mid; second.corrected = true
        lines[i] = first; lines.insert(second, at: i + 1)
        return second.id
    }
}

enum DialogueText {
    /// Texte d'une réplique : sans caractères de contrôle, espaces réduits, 600 caractères au plus.
    static func sanitize(_ s: String) -> String {
        let clean = String(String.UnicodeScalarView(s.unicodeScalars.map { $0.value < 32 || $0.value == 127 ? " " : $0 }))
        let squeezed = clean.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return String(squeezed.prefix(600))
    }
}

enum DialogueStore {
    static func url(_ info: MediaInfo) -> URL { AnalysisStore.dir.appendingPathComponent(SessionStore.key(info) + ".msdialog") }

    /// nil si absent, illisible, d'une autre version ou d'un autre fichier (durée) ; les réplique incohérentes sont retirées.
    static func load(_ info: MediaInfo) -> DialogueSet? {
        guard let d = try? Data(contentsOf: url(info)), var s = try? PropertyListDecoder().decode(DialogueSet.self, from: d),
              s.version == DialogueSet.currentVersion, abs(s.duration - info.duration) < 1 else { return nil }
        s.lines = s.lines.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && !$0.text.isEmpty }
        return s
    }

    @discardableResult static func save(_ set: DialogueSet, for info: MediaInfo) -> Bool {
        let enc = PropertyListEncoder(); enc.outputFormat = .binary
        guard let d = try? enc.encode(set) else { return false }
        do { try d.write(to: url(info), options: .atomic); return true } catch { return false }
    }

    static func remove(_ info: MediaInfo) { try? FileManager.default.removeItem(at: url(info)) }

    /// Résultat brut d'une transcription, écrit par le processus séparé (`mslice-mcp --dialogues`) puis relu et supprimé par l'appli.
    static func rawURL(_ info: MediaInfo) -> URL { AnalysisStore.dir.appendingPathComponent(SessionStore.key(info) + ".mstranscript") }
}
