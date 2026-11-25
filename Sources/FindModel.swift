// mSLICE — état de l'onglet « Trouver » pour un fichier : analyse (lancée à la demande, annulable, gardée), critères ET / SAUF, passages, morceaux à ajouter.
import AVFoundation
import AppKit
import Combine
import SwiftUI

/// Un passage sur la piste de résultats de la timeline.
struct LanePassage: Equatable { var start: Double; var end: Double; var excluded: Bool }

struct AddedInfo: Equatable { var count: Int; var seconds: Double }

struct FindSummary { var scenes: [SummaryRow] = [], sounds: [SummaryRow] = [] }

/// Un personnage reconnu, tel que le panneau l'affiche.
struct CharacterRow: Identifiable, Equatable {
    var id: Int32
    var name: String?
    var faces: Int
    var seconds: Double
    var appearances: Int
    var best: Int
    var title: String { name ?? L.t("find.chars.unnamed", Int(id) + 1) }
}

/// Une voix reconnue, telle que le panneau l'affiche.
struct VoiceRow: Identifiable, Equatable {
    var id: Int32
    var name: String?
    var seconds: Double
    var turns: Int
    var sample: Double
    var person: Int32?                        // personnage (visage) auquel la voix est liée
    var title: String { name ?? L.t("find.voices.unnamed", Int(id) + 1) }
}

/// Deux personnages qui ressemblent à la même personne : l'utilisateur confirme ou écarte.
struct MergeSuggestion: Identifiable, Equatable {
    var a: Int32, b: Int32
    var id: String { "\(a)-\(b)" }
}

/// Un protagoniste : un personnage (visage), une voix, ou les deux quand ils sont liés.
struct Protagonist: Identifiable, Equatable {
    var id: String                            // « p3 » (personnage 3, éventuellement avec sa voix) ou « v2 » (voix 2 sans visage)
    var person: Int32?
    var voice: Int32?
    var name: String?
    var faceSeconds: Double
    var voiceSeconds: Double
    var appearances: Int
    var best: Int                             // indice du plus beau visage (-1 : aucun)
    var sample: Double?                       // début d'un extrait de sa voix
    var number: Int
    var title: String { name ?? (person != nil ? L.t("find.chars.unnamed", number) : L.t("find.voices.unnamed", number)) }
    var canSeeAndAlone: Bool { person != nil }
    var canSpeak: Bool { voice != nil }
}

/// Quels moments garder pour les protagonistes choisis.
enum ProtoMode: String, CaseIterable { case visible, speaks, alone }
enum ProtoOut: String { case each, merged }

@MainActor
final class FindModel: ObservableObject {
    unowned let doc: Doc
    @Published private(set) var index: AnalysisIndex?
    @Published private(set) var summary = FindSummary()
    @Published private(set) var running = false
    @Published private(set) var failed = false
    @Published private(set) var progress = AnalysisProgress()
    @Published private(set) var startedAt = Date()
    @Published var terms: [FindTerm] = [] { didSet { if oldValue != terms { added = nil; recompute() } } }
    @Published var wholeShots = true { didSet { if oldValue != wholeShots { recompute() } } }
    @Published private(set) var result = FindResult()
    @Published var unchecked: Set<Int> = []
    @Published private(set) var lane: [LanePassage] = []
    @Published var added: AddedInfo?
    let thumbs = ThumbStore()
    private var finder: Finder?
    private var job: AnalysisJob?

    // Personnages (modèle optionnel) : index des visages, reconnaissance à la demande, corrections de l'utilisateur
    @Published private(set) var faces: FaceIndex?
    @Published private(set) var characters: [CharacterRow] = []
    @Published private(set) var recognizing = false
    @Published private(set) var recognizeFailed = false
    @Published private(set) var recognizeProgress = AnalysisProgress()
    @Published private(set) var recognizeStarted = Date()
    private var faceJob: AnalysisJob?

    // Voix (second modèle optionnel) et protagonistes (personnage + voix)
    @Published private(set) var voices: VoiceIndex?
    @Published private(set) var voiceRows: [VoiceRow] = []
    @Published private(set) var protagonists: [Protagonist] = []
    @Published private(set) var suggestions: [MergeSuggestion] = []
    private var dismissedSuggestions: Set<String> = []
    @Published private(set) var recognizingVoices = false
    @Published private(set) var voicesFailed = false
    @Published private(set) var voicesProgress = AnalysisProgress()
    @Published private(set) var voicesStarted = Date()
    @Published var protoSel: [String] = [] { didSet { if oldValue != protoSel { added = nil; recompute() } } }
    @Published var protoMode: ProtoMode = .visible { didSet { if oldValue != protoMode { recompute() } } }
    @Published var protoOut: ProtoOut = .each
    @Published var protoWhole = false { didSet { if oldValue != protoWhole { recompute() } } }
    private var voiceJob: AnalysisJob?
    var listenHandler: ((Double) -> Void)?
    private static let saveQueue = DispatchQueue(label: "fr.stephan.mslice.faces.save", qos: .utility)

    init(doc: Doc) {
        self.doc = doc
        if let i = AnalysisStore.load(doc.info) { setIndex(i) }
        if let f = FaceStore.load(doc.info) { setFaces(f, keepTerms: true) }
        if let v = VoiceStore.load(doc.info) { setVoices(v, keepTerms: true) }
    }

    var hasIndex: Bool { index != nil }

    private func setIndex(_ i: AnalysisIndex) {
        index = i
        let f = Finder(i, faces: faces, voices: voices)
        finder = f
        summary = FindSummary(scenes: f.summary().scenes, sounds: f.summary().sounds)
        wholeShots = i.hasVideo
        terms = []
        recompute()
    }

    // MARK: Analyse

    func start() {
        guard !running else { return }
        running = true; failed = false; added = nil; startedAt = Date()
        progress = AnalysisProgress(hasVideo: !doc.info.isAudioOnly, hasAudio: doc.info.audio != nil)
        let job = AnalysisJob(); self.job = job
        let info = doc.info
        Task { [weak self] in
            let idx = await AnalysisRunner.run(info, job: job) { p in Task { @MainActor [weak self] in if self?.running == true { self?.progress = p } } }
            guard let self else { return }
            self.running = false; self.job = nil
            if let idx { self.setIndex(idx) } else if !job.cancelled { self.failed = true }
        }
    }

    func cancel() { job?.cancel() }

    /// Pour les agents : lance l'analyse (ou attend celle en cours) et rend le résultat.
    func analyzeAndWait(force: Bool) async -> AnalysisIndex? {
        if !running, force || index == nil { start() }
        while running { try? await Task.sleep(nanoseconds: 200_000_000) }
        return index
    }

    /// Temps restant estimé (secondes), d'après la progression ; nil tant qu'elle est trop faible.
    var remaining: Double? {
        let f = progress.fraction
        guard running, f > 0.05, !progress.paused else { return nil }
        return Date().timeIntervalSince(startedAt) * (1 - f) / f
    }

    // MARK: Personnages

    var modelReady: Bool { ModelFiles.isInstalled(ModelCatalog.characters) }

    /// Reconnaissance des personnages : même principe que l'analyse (processus séparé, annulable, en pause pendant la lecture et l'export).
    func recognize() {
        guard !recognizing, !running, doc.info.video != nil, modelReady else { return }
        recognizing = true; recognizeFailed = false; recognizeStarted = Date()
        recognizeProgress = AnalysisProgress(hasVideo: true, hasAudio: false)
        let job = AnalysisJob(); faceJob = job
        let info = doc.info
        Task { [weak self] in
            let f = await AnalysisRunner.runFaces(info, job: job) { p in Task { @MainActor [weak self] in if self?.recognizing == true { self?.recognizeProgress = p } } }
            guard let self else { return }
            self.recognizing = false; self.faceJob = nil
            if let f { self.setFaces(f, keepTerms: false) } else if !job.cancelled { self.recognizeFailed = true }
        }
    }

    func cancelRecognize() { faceJob?.cancel() }

    /// Pour les agents : reconnaît les personnages (ou attend la reconnaissance en cours) et rend l'index des visages ; nil si le modèle n'est pas installé.
    func recognizeAndWait() async -> FaceIndex? {
        if !recognizing, faces == nil { recognize() }
        while recognizing { try? await Task.sleep(nanoseconds: 200_000_000) }
        return faces
    }

    var recognizeRemaining: Double? {
        let f = recognizeProgress.fraction
        guard recognizing, f > 0.05, !recognizeProgress.paused else { return nil }
        return Date().timeIntervalSince(recognizeStarted) * (1 - f) / f
    }

    private func refreshCharacters() {
        guard let f = faces else { characters = []; return }
        characters = f.characters().map { CharacterRow(id: $0.id, name: f.names[$0.id], faces: $0.faces, seconds: $0.seconds, appearances: $0.appearances, best: $0.best) }
        refreshProtagonists()
        refreshSuggestions()
    }

    private func setFaces(_ f: FaceIndex, keepTerms: Bool) {
        faces = f
        refreshCharacters()
        refreshProtagonists()
        if let idx = index { finder = Finder(idx, faces: f, voices: voices) }
        if !keepTerms { terms.removeAll { $0.kind == .person || $0.kind == .alone || $0.kind == .speaks }; protoSel = [] }
        recompute()
    }

    /// Applique une correction de l'utilisateur, l'enregistre (en tâche de fond) et met à jour les critères qui citent des personnages.
    private func editFaces(remap: [Int32: Int32] = [:], _ change: (inout FaceIndex) -> Void) {
        guard var f = faces else { return }
        change(&f)
        faces = f; refreshCharacters()
        if let idx = index { finder = Finder(idx, faces: f, voices: voices) }
        var next: [FindTerm] = []
        for var term in terms {
            if term.kind == .person || term.kind == .alone || term.kind == .speaks, var g = Int32(term.key) {
                g = remap[g] ?? g
                guard !f.hidden.contains(g), f.group.contains(g) else { continue }
                term.key = String(g); term.label = f.names[g]
            }
            if !next.contains(where: { $0.token == term.token }) { next.append(term) }
        }
        let same = next == terms
        terms = next
        if same { recompute() }
        let info = doc.info
        Self.saveQueue.async { FaceStore.save(f, for: info) }
    }

    func rename(_ id: Int32, to name: String) { editFaces { $0.rename(id, to: name) } }
    func merge(_ from: Int32, into: Int32) { editFaces(remap: [from: into]) { $0.merge(from, into: into) } }
    func hide(_ id: Int32) { editFaces { $0.hide(id) } }
    /// Sépare un personnage en deux ; faux s'il n'a qu'un seul suivi (rien à séparer).
    @discardableResult func split(_ id: Int32) -> Bool { var done = false; editFaces { done = $0.split(id) != nil }; return done }
    func canSplit(_ id: Int32) -> Bool {
        guard let f = faces else { return false }
        return Set((0 ..< f.count).filter { f.group[$0] == id }.map { f.track[$0] }).count >= 2
    }

    /// Vignette du plus beau visage d'un personnage.
    func avatar(_ id: Int32) async -> NSImage? {
        guard let f = faces, let row = characters.first(where: { $0.id == id }), row.best < f.count else { return nil }
        let b = row.best
        return await thumbs.face(at: Double(f.t[b]), box: Array(f.box[4 * b ..< 4 * b + 4]), key: Int(id) &* 1_000_003 &+ b, of: doc.info)
    }

    func personTerm(_ id: Int32) -> FindTerm { FindTerm(kind: .person, key: String(id), exclude: false, label: faces?.names[id]) }

    // MARK: Voix et protagonistes

    var voiceModelReady: Bool { ModelFiles.isInstalled(ModelCatalog.voices) }

    /// Reconnaissance des voix : même principe que celle des visages (processus séparé, annulable, en pause pendant la lecture et l'export).
    func recognizeVoices() {
        guard !recognizingVoices, !running, doc.info.audio != nil, voiceModelReady else { return }
        recognizingVoices = true; voicesFailed = false; voicesStarted = Date()
        voicesProgress = AnalysisProgress(hasVideo: true, hasAudio: false)
        let job = AnalysisJob(); voiceJob = job
        let info = doc.info
        Task { [weak self] in
            let v = await AnalysisRunner.runVoices(info, job: job) { p in Task { @MainActor [weak self] in if self?.recognizingVoices == true { self?.voicesProgress = p } } }
            guard let self else { return }
            self.recognizingVoices = false; self.voiceJob = nil
            if let v { self.setVoices(v, keepTerms: false) } else if !job.cancelled { self.voicesFailed = true }
        }
    }

    func cancelRecognizeVoices() { voiceJob?.cancel() }

    /// Pour les agents : reconnaît les voix (ou attend la reconnaissance en cours) ; nil si le modèle n'est pas installé.
    func recognizeVoicesAndWait() async -> VoiceIndex? {
        if !recognizingVoices, voices == nil { recognizeVoices() }
        while recognizingVoices { try? await Task.sleep(nanoseconds: 200_000_000) }
        return voices
    }

    var voicesRemaining: Double? {
        let f = voicesProgress.fraction
        guard recognizingVoices, f > 0.05, !voicesProgress.paused else { return nil }
        return Date().timeIntervalSince(voicesStarted) * (1 - f) / f
    }

    private func setVoices(_ v: VoiceIndex, keepTerms: Bool) {
        voices = v
        refreshProtagonists()
        if let idx = index { finder = Finder(idx, faces: faces, voices: v) }
        if !keepTerms { terms.removeAll { $0.kind == .voice || $0.kind == .speaks }; protoSel = [] }
        recompute()
    }

    private func editVoices(remap: [Int32: Int32] = [:], _ change: (inout VoiceIndex) -> Void) {
        guard var v = voices else { return }
        change(&v)
        voices = v; refreshProtagonists()
        if let idx = index { finder = Finder(idx, faces: faces, voices: v) }
        var next: [FindTerm] = []
        for var term in terms {
            if term.kind == .voice, var g = Int32(term.key) {
                g = remap[g] ?? g
                guard !v.hidden.contains(g), v.group.contains(g) else { continue }
                term.key = String(g); term.label = v.names[g]
            }
            if !next.contains(where: { $0.token == term.token }) { next.append(term) }
        }
        let same = next == terms
        terms = next
        protoSel = protoSel.filter { id in protagonists.contains { $0.id == id } }
        if same { recompute() }
        let info = doc.info
        Self.saveQueue.async { VoiceStore.save(v, for: info) }
    }

    func renameVoice(_ id: Int32, to name: String) { editVoices { $0.rename(id, to: name) } }
    func mergeVoice(_ from: Int32, into: Int32) { editVoices(remap: [from: into]) { $0.merge(from, into: into) } }
    func hideVoice(_ id: Int32) { editVoices { $0.hide(id) } }
    func linkVoice(_ id: Int32, to person: Int32?) { editVoices { v in
        if let person { for (k, p) in v.link where p == person && k != id { v.link[k] = nil } }
        v.setLink(id, to: person)
    } }

    /// Les protagonistes : chaque personnage (visage) avec la voix qui lui est liée, puis les voix sans visage.
    private func refreshProtagonists() {
        var out: [Protagonist] = []
        let stats = Dictionary(uniqueKeysWithValues: (voices?.voices() ?? []).map { ($0.id, $0) })
        var used = Set<Int32>()
        voiceRows = (voices?.voices() ?? []).map { VoiceRow(id: $0.id, name: voices?.names[$0.id], seconds: $0.seconds, turns: $0.turns, sample: $0.sample, person: voices?.link[$0.id]) }
        for c in characters {
            let v = voices.flatMap { vi in vi.link.filter { $0.value == c.id && !vi.hidden.contains($0.key) && stats[$0.key] != nil }.map(\.key).min() }
            if let v { used.insert(v) }
            out.append(Protagonist(id: "p\(c.id)", person: c.id, voice: v, name: c.name ?? v.flatMap { voices?.names[$0] }, faceSeconds: c.seconds, voiceSeconds: v.flatMap { stats[$0]?.seconds } ?? 0,
                                   appearances: c.appearances, best: c.best, sample: v.flatMap { stats[$0]?.sample }, number: Int(c.id) + 1))
        }
        for r in voiceRows where !used.contains(r.id) {
            out.append(Protagonist(id: "v\(r.id)", person: nil, voice: r.id, name: r.name, faceSeconds: 0, voiceSeconds: r.seconds, appearances: r.turns, best: -1, sample: r.sample, number: Int(r.id) + 1))
        }
        protagonists = out
        protoSel = protoSel.filter { id in out.contains { $0.id == id } }
    }

    private func refreshSuggestions() {
        guard let f = faces else { suggestions = []; return }
        suggestions = FaceClustering.suggestions(f).map { MergeSuggestion(a: $0.a, b: $0.b) }.filter { !dismissedSuggestions.contains($0.id) }
    }
    func dismiss(_ s: MergeSuggestion) { dismissedSuggestions.insert(s.id); suggestions.removeAll { $0.id == s.id } }
    /// Réunit les deux personnages d'une suggestion (le plus présent garde son identifiant).
    func accept(_ s: MergeSuggestion) {
        let sa = characters.first { $0.id == s.a }?.seconds ?? 0, sb = characters.first { $0.id == s.b }?.seconds ?? 0
        let (keep, drop) = sa >= sb ? (s.a, s.b) : (s.b, s.a)
        merge(drop, into: keep)
    }

    /// Les protagonistes comme plages de temps (visage à l'écran, voix qui parle), pour attribuer les répliques (`Speakers`).
    func speakerCandidates() -> [SpeakerCandidate] {
        protagonists.map { p in
            SpeakerCandidate(id: p.id, voice: p.voice.flatMap { voices?.intervals(of: $0) } ?? [], face: p.person.flatMap { faces?.intervals(of: $0) } ?? [])
        }
    }

    func protagonist(_ id: String) -> Protagonist? { protagonists.first { $0.id == id } }

    /// Le critère qui donne les moments d'un protagoniste selon le mode ; nil si ce mode ne s'applique pas à lui (voix sans visage : « parle » seulement).
    func protoTerm(_ p: Protagonist, _ mode: ProtoMode) -> FindTerm? {
        switch mode {
        case .visible: return p.person.map { FindTerm(kind: .person, key: String($0), label: p.name) }
        case .alone: return p.person.map { FindTerm(kind: .alone, key: String($0), label: p.name) }
        case .speaks:
            if let person = p.person { return p.voice == nil ? nil : FindTerm(kind: .speaks, key: String(person), label: p.name) }
            return p.voice.map { FindTerm(kind: .voice, key: String($0), label: p.name) }
        }
    }

    /// Les modes disponibles pour tous les protagonistes choisis.
    var availableModes: [ProtoMode] {
        let chosen = protoSel.compactMap { protagonist($0) }
        return ProtoMode.allCases.filter { m in chosen.allSatisfy { protoTerm($0, m) != nil } }
    }

    /// Moments gardés par protagoniste choisi (mode courant), dans l'ordre de la sélection.
    var protoPieces: [(id: String, name: String, segments: [(start: Double, end: Double)])] {
        guard let finder else { return [] }
        let whole = protoWhole && (index?.hasVideo ?? false)
        return protoSel.compactMap { id in
            guard let p = protagonist(id), let t = protoTerm(p, protoMode) else { return nil }
            var q = FindQuery(terms: [t]); q.wholeShots = whole
            return (id, p.title, finder.run(q).segments)
        }
    }

    /// Tous les moments choisis, fusionnés (un seul fichier ou ajout aux morceaux).
    var protoUnion: [(start: Double, end: Double)] {
        var out: [(start: Double, end: Double)] = []
        for s in protoPieces.flatMap(\.segments).sorted(by: { $0.start < $1.start }) {
            if let l = out.last, s.start <= l.end { out[out.count - 1].end = max(l.end, s.end) } else { out.append(s) }
        }
        return out
    }

    func toggleProto(_ id: String) {
        if let i = protoSel.firstIndex(of: id) { protoSel.remove(at: i) } else { protoSel.append(id) }
        if !availableModes.contains(protoMode), let m = availableModes.first { protoMode = m }
    }
    func clearProtos() { protoSel = [] }

    /// Ajoute les moments des protagonistes choisis aux morceaux du fichier (annulable par ⌘Z).
    func addProtosToPieces() {
        let list = protoUnion
        guard !list.isEmpty else { return }
        doc.snapshot()
        for s in list { doc.addSegment(s.start, s.end) }
        added = AddedInfo(count: list.count, seconds: list.reduce(0) { $0 + ($1.end - $1.start) })
        protoSel = []
        if let f = list.first { doc.ensureVisible(f.start) }
    }

    /// Écoute un extrait de voix (la lecture s'arrête seule après quelques secondes).
    func listen(at t: Double?) { if let t { listenHandler?(t) } }

    /// Les groupes à exporter : un par protagoniste choisi, ou un seul avec tous leurs moments réunis.
    func exportGroups(each: Bool) -> [(name: String, segments: [(start: Double, end: Double)])] {
        let pieces = protoPieces.filter { !$0.segments.isEmpty }
        if each { return pieces.map { ($0.name, $0.segments) } }
        let u = protoUnion
        return u.isEmpty ? [] : [(pieces.map(\.name).joined(separator: " + "), u)]
    }

    /// Image du plus beau visage d'un protagoniste.
    func avatar(of p: Protagonist) async -> NSImage? { p.person == nil ? nil : await avatar(p.person!) }

    // MARK: Critères

    var positives: [FindTerm] { terms.filter { !$0.exclude } }
    var negatives: [FindTerm] { terms.filter { $0.exclude } }
    /// Critères dans l'ordre d'affichage : les ET d'abord, puis les SAUF.
    var ordered: [FindTerm] { positives + negatives }

    func add(_ t: FindTerm) {
        var t = t
        if t.kind == .person || t.kind == .alone || t.kind == .speaks, t.label == nil, let id = Int32(t.key) { t.label = faces?.names[id] }       // le nom donné suit le critère
        if t.kind == .voice, t.label == nil, let id = Int32(t.key) { t.label = voices?.names[id] }
        protoSel = []
        if let i = terms.firstIndex(where: { $0.token == t.token }) { terms[i].exclude = t.exclude; return }
        if terms.isEmpty { t.exclude = false }
        terms.append(t)
    }
    func remove(_ t: FindTerm) { terms.removeAll { $0.token == t.token } }
    func flip(_ t: FindTerm) { if let i = terms.firstIndex(where: { $0.token == t.token }) { terms[i].exclude.toggle() } }
    func clear() { terms = [] }

    private func recompute() {
        guard let finder, !terms.isEmpty else {
            result = FindResult(); unchecked = []
            lane = protoSel.isEmpty ? [] : protoUnion.map { LanePassage(start: $0.start, end: $0.end, excluded: false) }
            return
        }
        var q = FindQuery(terms: terms); q.wholeShots = wholeShots && (index?.hasVideo ?? false)
        result = finder.run(q)
        unchecked = []
        lane = result.passages.map { LanePassage(start: $0.start, end: $0.end, excluded: $0.excludedBy != nil) }
    }

    // MARK: Passages et morceaux

    func isChecked(_ p: Passage) -> Bool { p.excludedBy == nil && !unchecked.contains(p.id) }
    func toggle(_ p: Passage) { guard p.excludedBy == nil else { return }; if unchecked.contains(p.id) { unchecked.remove(p.id) } else { unchecked.insert(p.id) } }
    var allChecked: Bool { !result.passages.contains { $0.excludedBy == nil && unchecked.contains($0.id) } }
    func setAll(_ on: Bool) { unchecked = on ? [] : Set(result.passages.filter { $0.excludedBy == nil }.map(\.id)) }
    var keptCount: Int { result.passages.filter { $0.excludedBy == nil }.count }

    /// Passages cochés, voisins (moins de 1,5 s) réunis : ce qui sera ajouté.
    var pieces: [(start: Double, end: Double)] {
        var out: [(start: Double, end: Double)] = []
        for p in result.passages where isChecked(p) {
            if let l = out.last, p.start - l.end < FindQuery().mergeGap { out[out.count - 1].end = max(l.end, p.end) } else { out.append((p.start, p.end)) }
        }
        return out
    }

    /// Ajoute les morceaux aux morceaux du fichier (annulable par ⌘Z), vide la sélection et affiche la confirmation.
    func addToPieces() {
        let list = pieces
        guard !list.isEmpty else { return }
        doc.snapshot()
        for s in list { doc.addSegment(s.start, s.end) }
        let info = AddedInfo(count: list.count, seconds: list.reduce(0) { $0 + ($1.end - $1.start) })
        terms = []
        added = info
        if let f = list.first { doc.ensureVisible(f.start) }
    }
}

/// Vignettes des passages : générées à la demande à 128×72, gardées en petit nombre, libérées quand on quitte l'onglet.
@MainActor
final class ThumbStore {
    private var generator: AVAssetImageGenerator?
    private var preparing: Task<Void, Never>?
    private let cache = NSCache<NSNumber, NSImage>()
    private let faceCache = NSCache<NSNumber, NSImage>()
    private var faceGenerator: AVAssetImageGenerator?
    private var facePreparing: Task<Void, Never>?
    init() { cache.countLimit = 160; faceCache.countLimit = 64 }

    /// Vignette ronde d'un personnage : le visage (boîte normalisée, origine en haut à gauche) recadré en carré avec de la marge, à 112 px.
    func face(at t: Double, box: [Float], key: Int, of info: MediaInfo) async -> NSImage? {
        let k = NSNumber(value: key)
        if let c = faceCache.object(forKey: k) { return c }
        guard box.count == 4 else { return nil }
        if faceGenerator == nil {
            if facePreparing == nil {
                facePreparing = Task { @MainActor in
                    let url = await Proxies.playableURL(info)
                    let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                    g.appliesPreferredTrackTransform = true
                    g.maximumSize = CGSize(width: 1280, height: 720)
                    g.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600); g.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
                    self.faceGenerator = g
                }
            }
            await facePreparing?.value
        }
        guard let g = faceGenerator, let cg = try? await g.image(at: CMTime(seconds: t, preferredTimescale: 600)).image else { return nil }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let bw = CGFloat(box[2]) * W, bh = CGFloat(box[3]) * H
        let side = min(max(bw, bh) * 1.7, min(W, H))
        var x = (CGFloat(box[0]) + CGFloat(box[2]) / 2) * W - side / 2, y = (CGFloat(box[1]) + CGFloat(box[3]) / 2) * H - side / 2
        x = min(max(x, 0), W - side); y = min(max(y, 0), H - side)
        guard side >= 8, let crop = cg.cropping(to: CGRect(x: x, y: y, width: side, height: side)),
              let ctx = CGContext(data: nil, width: 112, height: 112, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 112, height: 112))
        guard let small = ctx.makeImage() else { return nil }
        let img = NSImage(cgImage: small, size: NSSize(width: 54, height: 54))
        faceCache.setObject(img, forKey: k)
        return img
    }

    func image(_ t: Double, of info: MediaInfo) async -> NSImage? {
        let key = NSNumber(value: Int((t * 10).rounded()))
        if let c = cache.object(forKey: key) { return c }
        if generator == nil {
            if preparing == nil {
                preparing = Task { @MainActor in
                    let url = await Proxies.playableURL(info)
                    let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                    g.appliesPreferredTrackTransform = true
                    g.maximumSize = CGSize(width: 256, height: 144)
                    g.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600); g.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
                    self.generator = g
                }
            }
            await preparing?.value
        }
        guard let g = generator, let cg = try? await g.image(at: CMTime(seconds: t, preferredTimescale: 600)).image else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: 128, height: 72))
        cache.setObject(img, forKey: key)
        return img
    }

    func reset() {
        generator?.cancelAllCGImageGeneration(); generator = nil; preparing = nil; cache.removeAllObjects()
        faceGenerator?.cancelAllCGImageGeneration(); faceGenerator = nil; facePreparing = nil; faceCache.removeAllObjects()
    }
}
