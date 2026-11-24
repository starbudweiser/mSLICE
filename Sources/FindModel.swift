// mSLICE — état de l'onglet « Trouver » pour un fichier : analyse (lancée à la demande, annulable, gardée), critères ET / SAUF, passages, morceaux à ajouter.
import AVFoundation
import AppKit
import Combine
import SwiftUI

/// Un passage sur la piste de résultats de la timeline.
struct LanePassage: Equatable { var start: Double; var end: Double; var excluded: Bool }

struct AddedInfo: Equatable { var count: Int; var seconds: Double }

struct FindSummary { var scenes: [SummaryRow] = [], sounds: [SummaryRow] = [] }

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

    init(doc: Doc) {
        self.doc = doc
        if let i = AnalysisStore.load(doc.info) { setIndex(i) }
    }

    var hasIndex: Bool { index != nil }

    private func setIndex(_ i: AnalysisIndex) {
        index = i
        let f = Finder(i)
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

    // MARK: Critères

    var positives: [FindTerm] { terms.filter { !$0.exclude } }
    var negatives: [FindTerm] { terms.filter { $0.exclude } }
    /// Critères dans l'ordre d'affichage : les ET d'abord, puis les SAUF.
    var ordered: [FindTerm] { positives + negatives }

    func add(_ t: FindTerm) {
        var t = t
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
    init() { cache.countLimit = 160 }

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

    func reset() { generator?.cancelAllCGImageGeneration(); generator = nil; preparing = nil; cache.removeAllObjects() }
}
