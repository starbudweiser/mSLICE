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
    private static let saveQueue = DispatchQueue(label: "fr.stephan.mslice.faces.save", qos: .utility)

    init(doc: Doc) {
        self.doc = doc
        if let i = AnalysisStore.load(doc.info) { setIndex(i) }
        if let f = FaceStore.load(doc.info) { setFaces(f, keepTerms: true) }
    }

    var hasIndex: Bool { index != nil }

    private func setIndex(_ i: AnalysisIndex) {
        index = i
        let f = Finder(i, faces: faces)
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
    }

    private func setFaces(_ f: FaceIndex, keepTerms: Bool) {
        faces = f
        refreshCharacters()
        if let idx = index { finder = Finder(idx, faces: f) }
        if !keepTerms { terms.removeAll { $0.kind == .person } }
        recompute()
    }

    /// Applique une correction de l'utilisateur, l'enregistre (en tâche de fond) et met à jour les critères qui citent des personnages.
    private func editFaces(remap: [Int32: Int32] = [:], _ change: (inout FaceIndex) -> Void) {
        guard var f = faces else { return }
        change(&f)
        faces = f; refreshCharacters()
        if let idx = index { finder = Finder(idx, faces: f) }
        var next: [FindTerm] = []
        for var term in terms {
            if term.kind == .person, var g = Int32(term.key) {
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

    // MARK: Critères

    var positives: [FindTerm] { terms.filter { !$0.exclude } }
    var negatives: [FindTerm] { terms.filter { $0.exclude } }
    /// Critères dans l'ordre d'affichage : les ET d'abord, puis les SAUF.
    var ordered: [FindTerm] { positives + negatives }

    func add(_ t: FindTerm) {
        var t = t
        if t.kind == .person, t.label == nil, let id = Int32(t.key) { t.label = faces?.names[id] }       // le nom donné suit le critère
        if let i = terms.firstIndex(where: { $0.token == t.token }) { terms[i].exclude = t.exclude; return }
        if terms.isEmpty { t.exclude = false }
        terms.append(t)
    }
    func remove(_ t: FindTerm) { terms.removeAll { $0.token == t.token } }
    func flip(_ t: FindTerm) { if let i = terms.firstIndex(where: { $0.token == t.token }) { terms[i].exclude.toggle() } }
    func clear() { terms = [] }

    private func recompute() {
        guard let finder, !terms.isEmpty else { result = FindResult(); lane = []; unchecked = []; return }
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
