// mSLICE — des résultats d'analyse aux morceaux : critères (scène, son), combinaisons ET / SAUF, lissage, plans entiers, marges.
//
// Tout se joue sur une grille de 0,5 s : chaque critère donne un score par case (confiance maximale des étiquettes de sa famille), seuillé en
// actif / inactif. Critères ET : intersection. Les trous de moins de 1,5 s sont comblés, les passages de moins de 1 s écartés, puis chaque
// passage est calé sur les coupures (« plans entiers ») ou élargi de 0,3 s. Les passages qui chevauchent un critère SAUF sont gardés dans la
// liste, marqués « écarté », mais n'entrent pas dans les morceaux. Les passages voisins (moins de 1,5 s) sont réunis en un seul morceau.
import Foundation

struct FindTerm: Hashable, Sendable {
    enum Kind: String, Sendable { case scene, sound, sceneLabel = "label", soundLabel = "sound_label", person, voice, speaks, alone }
    var kind: Kind
    var key: String
    var exclude = false
    var label: String? = nil            // nom affiché d'un personnage ou d'une voix (le nom peut changer sans que le critère change)

    var name: String {
        switch kind {
        case .scene: return L.t("scene." + key)
        case .sound: return L.t("sound." + key)
        case .sceneLabel, .soundLabel: return key.replacingOccurrences(of: "_", with: " ")
        case .person: return label ?? L.t("find.chars.unnamed", (Int(key) ?? 0) + 1)
        case .voice: return label ?? L.t("find.voices.unnamed", (Int(key) ?? 0) + 1)
        case .speaks: return L.t("find.mode.speaks", label ?? L.t("find.chars.unnamed", (Int(key) ?? 0) + 1))
        case .alone: return L.t("find.mode.alone", label ?? L.t("find.chars.unnamed", (Int(key) ?? 0) + 1))
        }
    }
    /// Critères qui se lisent dans l'image : sans vidéo, ils ne peuvent rien trouver.
    var needsVideo: Bool { kind == .scene || kind == .sceneLabel || kind == .person || kind == .alone }
    var isSound: Bool { kind == .sound || kind == .soundLabel }
    var symbol: String {
        switch kind {
        case .scene: return SceneFamilies.byID[key]?.symbol ?? "circle.dashed"
        case .sound: return SoundFamilies.byID[key]?.symbol ?? "circle.dashed"
        case .sceneLabel: return "photo"
        case .soundLabel: return "waveform"
        case .person: return "person.crop.circle"
        case .voice, .speaks: return "waveform"
        case .alone: return "person.crop.square"
        }
    }
    /// « scene:fire », « sound:laugh », « label:fireworks », « sound_label:gunshot_gunfire », « person:3 » (personnage numéro 3).
    var token: String { kind.rawValue + ":" + key }
    var identity: String { token + (exclude ? "!" : "") }

    static func parse(_ s: String, exclude: Bool = false) -> FindTerm? {
        let p = s.split(separator: ":", maxSplits: 1).map(String.init)
        guard p.count == 2, let k = Kind(rawValue: p[0].lowercased()), !p[1].isEmpty else { return nil }
        if k == .person || k == .voice || k == .speaks || k == .alone { guard let n = Int32(p[1].trimmingCharacters(in: .whitespaces)), n >= 0 else { return nil }; return FindTerm(kind: k, key: String(n), exclude: exclude) }
        return FindTerm(kind: k, key: p[1].lowercased(), exclude: exclude)
    }
}

struct FindQuery: Sendable {
    var terms: [FindTerm] = []
    var wholeShots = true
    var sceneMin = 0.35                 // confiance minimale d'une étiquette d'image
    var soundMin = 0.5                  // confiance minimale d'un son
    var minLength = 1.0, fillGap = 1.5, margin = 0.3, mergeGap = 1.5
    var positives: [FindTerm] { terms.filter { !$0.exclude } }
    var negatives: [FindTerm] { terms.filter { $0.exclude } }
}

struct Passage: Identifiable, Sendable, Equatable {
    var id: Int
    var start: Double, end: Double
    var excludedBy: String?             // nom du critère SAUF qui écarte ce passage
    var duration: Double { end - start }
}

struct FindResult: Sendable {
    var passages: [Passage] = []
    var segments: [(start: Double, end: Double)] = []      // passages retenus, voisins réunis
    var keptSeconds: Double { segments.reduce(0) { $0 + ($1.end - $1.start) } }
}

struct SummaryRow: Identifiable, Sendable {
    var term: FindTerm
    var seconds: Double
    var count: Int
    var id: String { term.token }
}

final class Finder: @unchecked Sendable {
    let index: AnalysisIndex
    let grid: Double
    let cells: Int
    private let sceneFamilyOfLabel: [[Int]]
    private let soundFamilyOfLabel: [[Int]]
    private var sceneScores: [Float]            // familles × cases
    private var soundScores: [Float]
    let faces: FaceIndex?                       // personnages reconnus (modèle optionnel), nil sinon
    let voices: VoiceIndex?                     // voix reconnues (modèle optionnel), nil sinon
    private var personScores: [Int32: [Float]] = [:]
    private var voiceScores: [Int32: [Float]] = [:]
    private var aloneScores: [Int32: [Float]] = [:]

    init(_ index: AnalysisIndex, faces: FaceIndex? = nil, voices: VoiceIndex? = nil) {
        self.index = index
        self.faces = faces
        self.voices = voices
        grid = index.sceneStep
        cells = max(Int((index.duration / index.sceneStep).rounded(.up)), 1)
        sceneFamilyOfLabel = index.sceneLabels.map { SceneFamilies.ofLabel[$0] ?? [] }
        soundFamilyOfLabel = index.soundLabels.map { SoundFamilies.ofLabel[$0] ?? [] }
        sceneScores = [Float](repeating: 0, count: SceneFamilies.all.count * cells)
        soundScores = [Float](repeating: 0, count: SoundFamilies.all.count * cells)
        for s in 0 ..< min(index.sceneSamples, cells) {
            for e in Int(index.sceneOffsets[s]) ..< Int(index.sceneOffsets[s + 1]) {
                let c = Float(index.sceneConf[e]) / 255
                for f in sceneFamilyOfLabel[Int(index.sceneLabelIdx[e])] { let i = f * cells + s; if c > sceneScores[i] { sceneScores[i] = c } }
            }
        }
        for k in 0 ..< index.soundWindows {
            let (c0, c1) = soundCells(k)
            guard c0 < c1 else { continue }
            for e in Int(index.soundOffsets[k]) ..< Int(index.soundOffsets[k + 1]) {
                let c = Float(index.soundConf[e]) / 255
                for f in soundFamilyOfLabel[Int(index.soundLabelIdx[e])] { for cell in c0 ..< c1 { let i = f * cells + cell; if c > soundScores[i] { soundScores[i] = c } } }
            }
        }
    }

    /// Cases dont le centre tombe dans la zone « propre » de la fenêtre k (son centre, sur la largeur d'un pas) ; la première et la dernière s'étendent aux bords.
    private func soundCells(_ k: Int) -> (Int, Int) {
        let w = index.soundWindow, hop = index.soundHop
        var a = Double(index.soundStarts[k]) + (w - hop) / 2, b = Double(index.soundStarts[k]) + (w + hop) / 2
        if k == 0 { a = 0 }
        if k == index.soundWindows - 1 { b = index.duration + grid }
        let c0 = max(Int((a / grid - 0.5).rounded(.up)), 0), c1 = min(Int((b / grid - 0.5).rounded(.up)), cells)
        return (c0, c1)
    }

    // MARK: Scores et activité

    func scores(_ t: FindTerm) -> [Float] {
        switch t.kind {
        case .scene:
            guard let f = SceneFamilies.all.firstIndex(where: { $0.id == t.key }) else { return [] }
            return Array(sceneScores[f * cells ..< (f + 1) * cells])
        case .sound:
            guard let f = SoundFamilies.all.firstIndex(where: { $0.id == t.key }) else { return [] }
            return Array(soundScores[f * cells ..< (f + 1) * cells])
        case .sceneLabel:
            guard let li = index.sceneLabels.firstIndex(of: t.key) else { return [] }
            var out = [Float](repeating: 0, count: cells)
            for s in 0 ..< min(index.sceneSamples, cells) {
                for e in Int(index.sceneOffsets[s]) ..< Int(index.sceneOffsets[s + 1]) where Int(index.sceneLabelIdx[e]) == li { out[s] = max(out[s], Float(index.sceneConf[e]) / 255) }
            }
            return out
        case .soundLabel:
            guard let li = index.soundLabels.firstIndex(of: t.key) else { return [] }
            var out = [Float](repeating: 0, count: cells)
            for k in 0 ..< index.soundWindows {
                let (c0, c1) = soundCells(k)
                for e in Int(index.soundOffsets[k]) ..< Int(index.soundOffsets[k + 1]) where Int(index.soundLabelIdx[e]) == li { for c in c0 ..< c1 { out[c] = max(out[c], Float(index.soundConf[e]) / 255) } }
            }
            return out
        case .person:
            guard let faces, let g = Int32(t.key), g >= 0 else { return [] }
            if let c = personScores[g] { return c }
            var out = [Float](repeating: 0, count: cells)
            for iv in faces.intervals(of: g) {
                let c0 = max(Int((iv.start / grid).rounded(.down)), 0), c1 = min(Int((iv.end / grid).rounded(.up)), cells)
                if c0 < c1 { for c in c0 ..< c1 { out[c] = 1 } }
            }
            personScores[g] = out
            return out
        case .voice:
            guard let voices, let g = Int32(t.key), g >= 0 else { return [] }
            return voiceCells(g, voices)
        case .speaks:
            // le personnage parle : la voix qui lui est liée (la liaison vient de l'analyse ou de l'utilisateur)
            guard let voices, let p = Int32(t.key), p >= 0 else { return [] }
            var out = [Float](repeating: 0, count: cells)
            for (v, person) in voices.link where person == p && !voices.hidden.contains(v) { let c = voiceCells(v, voices); for i in 0 ..< cells where c[i] > out[i] { out[i] = c[i] } }
            return out
        case .alone:
            // le personnage est le seul visage à l'écran (les visages sans personnage compris : ils comptent comme d'autres personnes)
            guard let faces, let g = Int32(t.key), g >= 0 else { return [] }
            if let c = aloneScores[g] { return c }
            var out = scores(FindTerm(kind: .person, key: t.key))
            var other = [Float](repeating: 0, count: cells)
            for i in 0 ..< faces.count where faces.group[i] != g {
                let c0 = max(Int(((Double(faces.t[i]) - faces.step / 2) / grid).rounded(.down)), 0), c1 = min(Int(((Double(faces.t[i]) + faces.step / 2) / grid).rounded(.up)), cells)
                if c0 < c1 { for c in c0 ..< c1 { other[c] = 1 } }
            }
            for c in 0 ..< cells where other[c] > 0 { out[c] = 0 }
            aloneScores[g] = out
            return out
        }
    }

    private func voiceCells(_ g: Int32, _ voices: VoiceIndex) -> [Float] {
        if let c = voiceScores[g] { return c }
        var out = [Float](repeating: 0, count: cells)
        for iv in voices.intervals(of: g) {
            let c0 = max(Int((iv.start / grid).rounded(.down)), 0), c1 = min(Int((iv.end / grid).rounded(.up)), cells)
            if c0 < c1 { for c in c0 ..< c1 { out[c] = 1 } }
        }
        voiceScores[g] = out
        return out
    }

    /// Le critère existe-t-il dans cet index ? (famille connue, étiquette brute présente)
    func knows(_ t: FindTerm) -> Bool {
        switch t.kind {
        case .scene: return SceneFamilies.byID[t.key] != nil
        case .sound: return SoundFamilies.byID[t.key] != nil
        case .sceneLabel: return index.sceneLabels.contains(t.key)
        case .soundLabel: return index.soundLabels.contains(t.key)
        case .person, .speaks, .alone:
            guard let faces, let g = Int32(t.key) else { return false }
            if t.kind == .speaks, !(voices?.link.values.contains(g) ?? false) { return false }
            return !faces.hidden.contains(g) && faces.group.contains(g)
        case .voice: if let voices, let g = Int32(t.key) { return !voices.hidden.contains(g) && voices.group.contains(g) }; return false
        }
    }

    func active(_ t: FindTerm, _ q: FindQuery) -> [Bool] {
        let thr = Float(t.isSound ? q.soundMin : q.sceneMin)
        let s = scores(t)
        return s.isEmpty ? [Bool](repeating: false, count: cells) : s.map { $0 >= thr }
    }

    /// Passages d'une suite de cases actives : trous comblés, passages trop courts écartés ; en secondes.
    func intervals(_ act: [Bool], _ q: FindQuery) -> [(start: Double, end: Double)] {
        var runs: [(Int, Int)] = []
        var i = 0
        while i < act.count {
            if act[i] { var j = i; while j < act.count, act[j] { j += 1 }; runs.append((i, j)); i = j } else { i += 1 }
        }
        let gap = Int((q.fillGap / grid).rounded(.down))
        var merged: [(Int, Int)] = []
        for r in runs { if let l = merged.last, r.0 - l.1 <= gap { merged[merged.count - 1].1 = r.1 } else { merged.append(r) } }
        return merged.filter { Double($0.1 - $0.0) * grid >= q.minLength - 1e-9 }.map { (Double($0.0) * grid, min(Double($0.1) * grid, index.duration)) }
    }

    // MARK: Requête

    func run(_ q: FindQuery) -> FindResult {
        let pos = q.positives
        guard !pos.isEmpty else { return FindResult() }
        var act = [Bool](repeating: true, count: cells)
        for t in pos { let a = active(t, q); for i in 0 ..< cells { act[i] = act[i] && a[i] } }
        var raw = intervals(act, q)
        if q.wholeShots && index.hasVideo {
            raw = raw.map { (index.shot(at: $0.start + 0.001).start, index.shot(at: max($0.end - 0.001, $0.start)).end) }
        } else {
            raw = raw.map { (max($0.start - q.margin, 0), min($0.end + q.margin, index.duration)) }
        }
        var passages: [(Double, Double)] = []
        for r in raw.sorted(by: { $0.0 < $1.0 }) { if let l = passages.last, r.0 <= l.1 { passages[passages.count - 1].1 = max(l.1, r.1) } else { passages.append(r) } }

        let negs = q.negatives.map { ($0.name, intervals(active($0, q), q)) }
        var out: [Passage] = []
        for (n, p) in passages.enumerated() {
            var by: String?
            for (name, iv) in negs {
                let overlap = iv.reduce(0.0) { $0 + max(0, min($1.end, p.1) - max($1.start, p.0)) }
                if overlap >= 0.5 { by = name; break }
            }
            out.append(Passage(id: n, start: p.0, end: p.1, excludedBy: by))
        }
        var segs: [(start: Double, end: Double)] = []
        for p in out where p.excludedBy == nil {
            if let l = segs.last, p.start - l.end < q.mergeGap { segs[segs.count - 1].end = max(l.end, p.end) } else { segs.append((p.start, p.end)) }
        }
        return FindResult(passages: out, segments: segs)
    }

    // MARK: Résumé (listes de l'onglet)

    func summary(_ q: FindQuery = FindQuery(), minSeconds: Double = 2) -> (scenes: [SummaryRow], sounds: [SummaryRow]) {
        func rows(_ kind: FindTerm.Kind, _ fams: [Family], _ scores: [Float], _ thr: Float) -> [SummaryRow] {
            var out: [SummaryRow] = []
            for (f, fam) in fams.enumerated() {
                let act = scores[f * cells ..< (f + 1) * cells].map { $0 >= thr }
                let iv = intervals(Array(act), q)
                let total = iv.reduce(0.0) { $0 + ($1.end - $1.start) }
                if total >= minSeconds { out.append(SummaryRow(term: FindTerm(kind: kind, key: fam.id), seconds: total, count: iv.count)) }
            }
            return out.sorted { $0.seconds > $1.seconds }
        }
        return (index.hasVideo ? rows(.scene, SceneFamilies.all, sceneScores, Float(q.sceneMin)) : [],
                index.hasAudio ? rows(.sound, SoundFamilies.all, soundScores, Float(q.soundMin)) : [])
    }
}
