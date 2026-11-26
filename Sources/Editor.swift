// mSLICE — un fichier ouvert (morceaux, bistouri I / O, annulation, mémoire de session) et l'état général de l'appli.
import AppKit
import Combine
import SwiftUI

@MainActor
final class Doc: ObservableObject, Identifiable {
    static let minLength = 0.05
    let id = UUID()
    let info: MediaInfo
    @Published var keyframes: [Double] = []
    @Published var segments: [Segment] = [] { didSet { scheduleSave(); onSegmentsChange?() } }
    @Published var selected: UUID?
    @Published var pendingIn: Double?
    @Published var baseName = "" { didSet { scheduleSave() } }        // nom de base des fichiers exportés ; vide : nom de l'original
    @Published var mergeName = "" { didSet { scheduleSave() } }       // nom du fichier fusionné ; vide : automatique
    @Published var exported = false
    @Published var loudness: LoudnessProfile?                     // niveau sonore du fichier, mesuré à la demande pour « blancs retirés » (une seule fois)
    @Published var silenceBusy = false
    @Published var silenceProgress = 0.0                          // 0…1 pendant la mesure du niveau sonore
    private var silenceTask: Task<Void, Never>?
    private var silenceCache: (intensity: Double, ranges: [(start: Double, end: Double)])?
    /// Silences pour l'intensité choisie (nil tant que le niveau sonore n'est pas mesuré) : recalculés à la volée quand le curseur bouge.
    var silences: [(start: Double, end: Double)]? {
        guard let l = loudness else { return nil }
        let i = AppModel.shared.opts.trimIntensity
        if let c = silenceCache, c.intensity == i { return c.ranges }
        let r = l.silences(intensity: i); silenceCache = (i, r); return r
    }
    /// Respiration gardée de chaque côté d'une coupe, selon l'intensité.
    var silenceKeep: Double { LoudnessProfile.params(AppModel.shared.opts.trimIntensity).keep }
    func tighten(_ segs: [Segment], inside: Bool) -> [Segment] {
        guard let s = silences else { return segs }
        return Silence.tighten(segs, silences: s, keep: silenceKeep, inside: inside)
    }
    @Published var viewStart = 0.0
    @Published var viewSpan: Double
    @Published var clean: CleanState = .none
    @Published var voiceOnly = false          // on écoute la piste « voix seules » (le lecteur la suit)
    private var cleanJob: AnalysisJob?
    let peaks = PeakStore()
    let strip: Filmstrip
    let cancel = CancelToken()
    var onSegmentsChange: (() -> Void)?
    /// Onglet « Trouver » : analyse du fichier, critères, passages (créé à la première demande).
    lazy var find = FindModel(doc: self)
    /// Onglet « Dialogues » : répliques du fichier (sous-titres ou transcription).
    lazy var dialogues = DialogueModel(doc: self)
    private var undoStack: [[Segment]] = []
    private var saveWork: DispatchWorkItem?

    var url: URL { info.url }
    var duration: Double { info.duration }
    var hasVideo: Bool { !info.isAudioOnly }
    var name: String { info.url.lastPathComponent }
    var kept: Double { segments.reduce(0) { $0 + $1.duration } }

    init(info: MediaInfo) {
        self.info = info; viewSpan = info.duration
        strip = Filmstrip(duration: info.duration)
        let session = SessionStore.load(info)
        segments = session.segments; baseName = session.baseName ?? ""; mergeName = session.mergeName ?? ""
        selected = segments.first?.id
        if CleanVoice.exists(info) { clean = .ready }
    }

    /// Peut-on isoler les voix de ce fichier (il a du son, macOS sait le faire) ?
    var canClean: Bool { info.audio != nil && CleanVoice.available }

    /// Fabrique la piste « voix seules » en arrière-plan ; `done(vrai)` à la fin. Sans effet si elle est prête ou en cours (alors `done` attend la fin).
    func buildClean(done: (@MainActor (Bool) -> Void)? = nil) {
        if clean == .ready { done?(true); return }
        guard canClean else { AppModel.shared.flash(L.t("clean.unavailable")); done?(false); return }
        if case .building = clean { return }
        let job = AnalysisJob(); cleanJob = job; clean = .building(0)
        Task {
            let ok = await CleanVoice.build(info, job: job) { p in Task { @MainActor [weak self] in if case .building = self?.clean { self?.clean = .building(p) } } }
            cleanJob = nil
            if ok { clean = .ready }
            else if job.cancelled { clean = .none }
            else { clean = .failed; AppModel.shared.flash(L.t("clean.failed")) }
            done?(ok)
        }
    }
    func cancelClean() { cleanJob?.cancel() }

    func loadBackground() {
        let strip = self.strip, cancel = self.cancel
        Task.detached(priority: .utility) { [info] in
            let k = Probe.keyframes(info)
            await MainActor.run { self.keyframes = k }
            await strip.load(info, keyframes: k, cancel: cancel)       // les vignettes dépendent de la densité des images clés
        }
        Task { await PeakLoader.load(info, into: peaks, cancel: cancel) }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [info, segments, baseName, mergeName] in SessionStore.save(info, SessionStore.Session(segments: segments, baseName: baseName, mergeName: mergeName)) }
        saveWork = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    // MARK: Bistouri

    func snapshot() { undoStack.append(segments); if undoStack.count > 100 { undoStack.removeFirst() } }
    func undo() { guard let s = undoStack.popLast() else { return }; segments = s; if let sel = selected, !s.contains(where: { $0.id == sel }) { selected = s.first?.id } }
    var canUndo: Bool { !undoStack.isEmpty }

    func segment(at t: Double) -> Segment? { segments.first { t >= $0.start - 0.0005 && t <= $0.end + 0.0005 } }

    /// Entrée : à l'intérieur d'un morceau, déplace son début ; sinon, pose l'entrée d'un nouveau morceau.
    /// `snap` : en copie directe, l'entrée se cale sur l'image clé qui précède (le début réel du morceau).
    func markIn(at t: Double, snap: Bool) {
        let a = snap && hasVideo ? Planner.effectiveStart(t, keyframes: keyframes, passthrough: true, hasVideo: true) : t
        if let s = segment(at: t), let i = segments.firstIndex(of: s) {
            guard a < s.end - Doc.minLength else { NSSound.beep(); return }
            let lo = i > 0 ? segments[i - 1].end : 0
            snapshot(); segments[i].start = max(a, lo); selected = s.id
        } else { pendingIn = a }
    }

    /// Sortie : crée le morceau (entrée posée avant), ou déplace la fin du morceau où l'on se trouve.
    func markOut(at t: Double) {
        if let p = pendingIn {
            guard t > p + Doc.minLength else { NSSound.beep(); return }
            snapshot(); addSegment(p, t); pendingIn = nil
        } else if let s = segment(at: t), let i = segments.firstIndex(of: s) {
            guard t > s.start + Doc.minLength else { NSSound.beep(); return }
            let hi = i + 1 < segments.count ? segments[i + 1].start : duration
            snapshot(); segments[i].end = min(t, hi); selected = s.id
        } else {
            let start = segments.last(where: { $0.end <= t })?.end ?? 0
            guard t > start + Doc.minLength else { NSSound.beep(); return }
            snapshot(); addSegment(start, t)
        }
    }

    /// Ajoute un morceau ; ceux qui le chevauchent sont fusionnés avec lui.
    func addSegment(_ a: Double, _ b: Double, who: String? = nil) {
        var lo = max(0, min(a, b)), hi = min(duration, max(a, b))
        let overlapping = segments.filter { $0.start <= hi && $0.end >= lo }
        for s in overlapping { lo = min(lo, s.start); hi = max(hi, s.end) }
        var list = segments.filter { s in !overlapping.contains(where: { $0.id == s.id }) }
        let new = Segment(start: lo, end: hi, who: who ?? overlapping.compactMap(\.who).first)
        list.append(new); list.sort { $0.start < $1.start }
        segments = list; selected = new.id
    }

    /// Couleur d'un morceau : celle de son protagoniste (la même que dans les dialogues), orange pour un morceau posé à la main.
    func colorNS(of s: Segment) -> NSColor {
        guard let w = s.who, let i = find.protagonists.firstIndex(where: { $0.id == w }) else { return Theme.segNS }
        return DialogueModel.palette[i % DialogueModel.palette.count]
    }
    func color(of s: Segment) -> Color { Color(nsColor: colorNS(of: s)) }

    /// Calcule les silences une fois (une seule recherche à la fois).
    /// Capture (--trim-demo v) : la recherche des blancs reste figée à v (0…1) pour contrôler la barre de progression.
    nonisolated(unsafe) static var demoProgress: Double?

    func ensureSilences() async {
        if loudness != nil || info.audio == nil { return }
        if let v = Doc.demoProgress { silenceBusy = true; silenceProgress = v; return }
        if let t = silenceTask { await t.value; return }                     // une mesure est en cours : on l'attend (jamais deux, jamais de boucle)
        silenceBusy = true; silenceProgress = 0
        let t = Task { @MainActor [weak self] in
            guard let self else { return }
            let l = await LoudnessProfile.measure(self.info) { p in Task { @MainActor [weak self] in self?.silenceProgress = p } }
            self.loudness = l ?? LoudnessProfile(frameDB: [], duration: self.info.duration)
            self.silenceProgress = 1; self.silenceBusy = false; self.silenceTask = nil
        }
        silenceTask = t
        await t.value
    }
    /// Morceaux à exporter : ceux de la timeline, resserrés sur la parole si « blancs retirés » est choisi et les silences connus.
    func exportSegments(_ o: ExportOptions) -> [Segment] {
        guard o.trimSilence, let sil = silences else { return segments }
        _ = sil; return tighten(segments, inside: o.merge)
    }

    /// Retire les blancs des morceaux posés (début, fin et intérieur), annulable avec ⌘Z. Renvoie la durée gagnée ; nil s'il n'y a rien à faire (pas de son, pas de morceau).
    func trimPiecesSilence() async -> Double? {
        guard info.audio != nil, !segments.isEmpty else { return nil }
        await ensureSilences()
        guard let sil = silences else { return nil }
        let before = segments.reduce(0) { $0 + $1.duration }
        _ = sil
        let t = tighten(segments, inside: true)
        let gain = before - t.reduce(0) { $0 + $1.duration }
        guard !t.isEmpty, gain > 0.05 else { return 0 }
        snapshot(); segments = t; selected = t.first?.id
        return gain
    }

    func deleteSelected() {
        guard let sel = selected, let i = segments.firstIndex(where: { $0.id == sel }) else { return }
        snapshot(); segments.remove(at: i)
        selected = segments.indices.contains(i) ? segments[i].id : segments.last?.id
    }
    func delete(_ id: UUID) { selected = id; deleteSelected() }

    /// Glissement d'une poignée de la timeline (le début se cale sur les images clés si `snap`).
    func moveEdge(_ id: UUID, start: Bool, to t: Double, snap: Bool) {
        guard let i = segments.firstIndex(where: { $0.id == id }) else { return }
        let minL = Doc.minLength
        if start {
            var a = snap && hasVideo ? Planner.effectiveStart(t, keyframes: keyframes, passthrough: true, hasVideo: true) : t
            a = min(max(a, i > 0 ? segments[i - 1].end : 0), segments[i].end - minL)
            segments[i].start = a
        } else {
            let hi = i + 1 < segments.count ? segments[i + 1].start : duration
            segments[i].end = min(max(t, segments[i].start + minL), hi)
        }
    }

    func selectAdjacent(_ delta: Int, from t: Double) {
        guard !segments.isEmpty else { return }
        let cur = segments.firstIndex { $0.id == selected } ?? segments.lastIndex { $0.start <= t } ?? 0
        selected = segments[min(max(cur + delta, 0), segments.count - 1)].id
    }

    // MARK: Vue (zoom / défilement)

    func clampView() {
        viewSpan = min(max(viewSpan, min(2, duration)), duration)
        viewStart = min(max(viewStart, 0), max(duration - viewSpan, 0))
    }
    func zoom(by factor: Double, around t: Double) {
        let ratio = viewSpan > 0 ? (t - viewStart) / viewSpan : 0.5
        viewSpan /= factor; clampView()
        viewStart = t - ratio * viewSpan; clampView()
    }
    func ensureVisible(_ t: Double) {
        if t < viewStart || t > viewStart + viewSpan { viewStart = t - viewSpan * 0.1; clampView() }
    }
}

enum Sheet: Equatable { case none, export, done, options }

/// Ce qu'on s'apprête à exporter : la feuille d'options est la même pour les morceaux et pour les personnes choisies ; `run` lance l'export une fois validée.
struct ExportRequest {
    enum Kind { case pieces, people(FindModel) }
    var kind: Kind
    var count: Int                      // nombre de fichiers annoncé
    var run: @MainActor () -> Void
}

/// Piste « voix seules » d'un fichier (voir `CleanVoice`) : absente, en calcul (0…1), prête ou en échec.
enum CleanState: Equatable { case none, building(Double), ready, failed }

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let isDev = Env.isDev
    /// Lancé par un essai automatique (`--selftest-*`) : jamais de Finder qui s'ouvre, jamais de fichier mis à la corbeille.
    static let isSelfTest = CommandLine.arguments.contains { $0.hasPrefix("--selftest") }

    @Published var docs: [Doc] = []
    @Published var current: Doc?
    @Published var sheet: Sheet = .none
    @Published var request: ExportRequest?
    @Published var run: ExportRun?
    @Published var toast: String?
    @Published var loading = 0
    @Published var opts: ExportOptions { didSet { if let d = try? JSONEncoder().encode(opts) { UserDefaults.standard.set(d, forKey: "export.opts") }; UserDefaults.standard.set(opts.trimIntensity, forKey: "trim.intensity") } }
    @Published var snap = true
    @Published var showShortcuts = false
    let player = PlayerModel()
    weak var mainWindow: NSWindow?
    var testMode = false          // essais sans fenêtre : les touches simulées sont acceptées sans fenêtre active
    private var gateSink: AnyCancellable?

    init() {
        if let d = UserDefaults.standard.data(forKey: "export.opts"), let o = try? JSONDecoder().decode(ExportOptions.self, from: d) { opts = o } else { opts = ExportOptions() }
        if UserDefaults.standard.object(forKey: "trim.intensity") != nil { opts.trimIntensity = min(max(UserDefaults.standard.double(forKey: "trim.intensity"), 0), 1) }
        // L'analyse cède le processeur à la lecture et à l'export, puis reprend toute seule.
        gateSink = Publishers.CombineLatest(player.$isPlaying, $sheet).sink { playing, sheet in AnalysisGate.shared.paused = playing || sheet == .export }
    }

    // MARK: Ouverture

    func open(_ urls: [URL]) {
        var firstNew: Doc?
        for u in urls {
            if let d = docs.first(where: { $0.url == u }) { firstNew = firstNew ?? d; continue }
            loading += 1
            Task {
                let info = await Task.detached { Probe.read(u) }.value
                loading -= 1
                guard let info else { flash(L.t("err.unsupported", u.lastPathComponent)); return }
                let d = Doc(info: info)
                docs.append(d); d.loadBackground()
                if current == nil || urls.count == 1 || u == urls.first { select(d) }
            }
        }
        if let d = firstNew { select(d) }
    }

    func select(_ d: Doc) {
        guard current !== d else { return }
        current = d
        Task {
            await player.load(d.info)
            if d.voiceOnly, current === d { await player.setVoiceOnly(true, info: d.info) }       // le choix suit le fichier quand on revient dessus
        }
    }

    /// Écoute la piste « voix seules » (la fabrique d'abord si besoin) ou revient au son d'origine.
    func setVoiceOnly(_ on: Bool, for d: Doc) {
        if !on { d.voiceOnly = false; if current === d { Task { await player.setVoiceOnly(false, info: d.info) } }; return }
        d.buildClean { [weak self, weak d] ok in
            guard ok, let self, let d else { return }
            d.voiceOnly = true
            if self.current === d { Task { await self.player.setVoiceOnly(true, info: d.info) } }
        }
    }

    func close(_ d: Doc) {
        d.cancel.cancel(); d.find.cancel(); d.dialogues.cancel(); d.cancelClean()
        docs.removeAll { $0 === d }
        if current === d { current = nil; player.pause(); if let n = docs.first { select(n) } }
    }

    func chooseFiles() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = false
        p.allowedContentTypes = [.audiovisualContent, .movie, .audio]
        if p.runModal() == .OK { open(p.urls) }
    }

    func flash(_ s: String) {
        toast = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in if self?.toast == s { self?.toast = nil } }
    }

    // MARK: Export

    var canExport: Bool {
        guard let d = current, !d.segments.isEmpty, sheet == .none else { return false }
        return !(opts.voiceOnly && d.info.audio != nil && d.clean != .ready)          // « voix seules » : on attend la fin du calcul de la piste
    }

    /// Options d'un export de `d` : « voix seules » seulement si le fichier a du son et si la piste est prête (sinon on la lance et on renonce).
    private func exportOptions(for d: Doc, voice: Bool = false) -> ExportOptions? {
        var o = opts
        if voice { o.voiceOnly = true }
        if o.voiceOnly {
            if d.info.audio == nil { o.voiceOnly = false }
            else if d.clean != .ready { d.buildClean(); flash(L.t("clean.notready")); return nil }
        }
        return o
    }

    func exportNow() {
        guard let d = current, !d.segments.isEmpty, sheet == .none, var o = exportOptions(for: d) else { return }
        if o.trimSilence, d.info.audio != nil, d.silences == nil {                      // les blancs ne sont pas encore cherchés : on les cherche, puis l'export repart
            flash(L.t("exp.silence.busy")); Task { await d.ensureSilences(); self.exportNow() }; return
        }
        if o.trimSilence, d.silences != nil, !d.info.isAudioOnly { o.passthrough = false }     // coupes au plus juste : recompression
        // La copie directe n'est possible que si les codecs entrent dans le conteneur choisi (l'audio refait par « voix seules » n'est pas copié).
        if o.passthrough, !Planner.canCopy(info: d.info, to: o.format), !o.voiceOnly { flash(L.t("err.cantcopy")); return }
        if o.passthrough, !d.info.isAudioOnly, o.resolvedFormat(for: d.info).isAudio, d.info.audio == nil { flash(L.t("err.noaudio")); return }
        if !o.passthrough, o.format == .same { o.format = d.info.isAudioOnly ? .m4a : .mp4 }
        let outs = Planner.outputs(info: d.info, segments: d.exportSegments(o), opts: o, keyframes: d.keyframes, base: d.baseName, mergeName: d.mergeName)
        startExport(d, outs, o)
    }

    /// Exporte directement des groupes de moments choisis dans l'onglet Trouver (un fichier par groupe, chacun fusionné), sans toucher aux morceaux du fichier.
    func exportGroups(_ groups: [(name: String, segments: [(start: Double, end: Double)])], voice: Bool = false, names: [String: String] = [:]) {
        guard let d = current, sheet == .none, groups.contains(where: { !$0.segments.isEmpty }), var o = exportOptions(for: d, voice: voice) else { return }
        var groups = groups
        if o.trimSilence, d.info.audio != nil {                                          // « blancs retirés » : chaque groupe resserré sur la parole
            guard let sil = d.silences else { flash(L.t("exp.silence.busy")); Task { await d.ensureSilences(); self.exportGroups(groups, voice: voice, names: names) }; return }
            _ = sil; groups = groups.map { g in (g.name, d.tighten(g.segments.map { Segment(start: $0.start, end: $0.end) }, inside: true).map { (start: $0.start, end: $0.end) }) }
            if !d.info.isAudioOnly { o.passthrough = false }
        }
        o.merge = true
        if o.passthrough, !Planner.canCopy(info: d.info, to: o.format), !o.voiceOnly { flash(L.t("err.cantcopy")); return }
        if o.passthrough, !d.info.isAudioOnly, o.resolvedFormat(for: d.info).isAudio, d.info.audio == nil { flash(L.t("err.noaudio")); return }
        if !o.passthrough, o.format == .same { o.format = d.info.isAudioOnly ? .m4a : .mp4 }
        let base = Planner.sanitize(d.baseName.isEmpty ? d.info.url.deletingPathExtension().lastPathComponent : d.baseName)
        var outs: [OutputItem] = []
        for g in groups where !g.segments.isEmpty {
            outs += Planner.outputs(info: d.info, segments: g.segments.map { Segment(start: $0.start, end: $0.end) }, opts: o, keyframes: d.keyframes, base: d.baseName, mergeName: names[g.name].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? "\(base) – \(g.name)")
        }
        startExport(d, outs, o)
    }

    /// Le fichier entier en « voix seules », sans passer par des morceaux (la piste est fabriquée d'abord si besoin, puis l'export part tout seul).
    func exportWholeClean() {
        guard let d = current, sheet == .none, d.canClean else { return }
        let go = { [weak self, weak d] in
            guard let self, let d, self.current === d else { return }
            self.exportGroups([(name: L.t("clean.suffix"), segments: [(start: 0, end: d.duration)])], voice: true)
        }
        if d.clean == .ready { go() } else { d.buildClean { ok in if ok { go() } } }
    }

    private func startExport(_ d: Doc, _ outs: [OutputItem], _ o: ExportOptions) {
        let r = ExportRun(); run = r; sheet = .export
        player.pause()
        r.start(info: d.info, outputs: outs, opts: o, keyframes: d.keyframes) { [weak self, weak d] in
            guard let self else { return }
            if r.error == nil && !r.cancelled {
                d?.exported = true
                self.sheet = .done
                if !AppModel.isSelfTest, UserDefaults.standard.object(forKey: "revealAfter") == nil || UserDefaults.standard.bool(forKey: "revealAfter") { NSWorkspace.shared.activateFileViewerSelecting(r.results.prefix(1).map { $0 }) }
                if !AppModel.isSelfTest, UserDefaults.standard.bool(forKey: "trashAfter"), let url = d?.url { NSWorkspace.shared.recycle([url]) { _, _ in } }
            } else if r.cancelled { self.sheet = .none }
        }
    }

    /// Ouvre la feuille d'options d'export (ni lancement ni écrasement : tout part du bouton « Exporter » de la feuille).
    func requestExport(_ r: ExportRequest) {
        guard sheet == .none, current != nil else { return }
        request = r; sheet = .options
    }
    /// Les morceaux de la timeline.
    func requestPiecesExport() {
        guard let d = current, !d.segments.isEmpty else { return }
        requestExport(ExportRequest(kind: .pieces, count: Planner.outputs(info: d.info, segments: d.segments, opts: opts, keyframes: d.keyframes, base: d.baseName, mergeName: d.mergeName).count, run: { [weak self] in self?.exportNow() }))
    }
    func cancelOptions() { if sheet == .options { sheet = .none; request = nil } }
    func confirmExport() {
        guard sheet == .options, let r = request else { return }
        sheet = .none; request = nil
        r.run()
    }

    func cancelExport() { run?.cancel.cancel() }
    func closeSheet() { sheet = .none; run = nil }
    func trashOriginal() { if let u = current?.url { NSWorkspace.shared.recycle([u]) { _, _ in }; current.map { close($0) } ; closeSheet() } }
    func reveal() { if let r = run?.results, !r.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(r) } }

    // MARK: Clavier

    func handleKey(_ e: NSEvent) -> Bool {
        if !testMode { guard let win = NSApp.keyWindow, win === mainWindow, !(win.firstResponder is NSText) else { return false } }
        if sheet != .none {
            if e.keyCode == 53 { if sheet == .export { cancelExport() } else if sheet == .options { cancelOptions() } else { closeSheet() }; return true }
            return false
        }
        guard let d = current else { return false }
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let ch = (e.charactersIgnoringModifiers ?? "").lowercased()
        let t = player.time
        if mods.contains(.command) || mods.contains(.control) { return false }
        switch e.keyCode {
        case 123, 124:   // ← →
            let dir = e.keyCode == 123 ? -1 : 1
            if mods.contains(.shift) { player.pause(); player.seek(t + Double(dir)) } else { player.step(frames: dir) }
            d.ensureVisible(player.time); return true
        case 126: if let k = Planner.keyframe(after: t, in: d.keyframes) { player.pause(); player.seek(k); d.ensureVisible(k) }; return true
        case 125: if let k = Planner.keyframe(before: t, in: d.keyframes) { player.pause(); player.seek(k); d.ensureVisible(k) }; return true
        case 51, 117: d.deleteSelected(); return true
        case 115: player.seek(0); d.ensureVisible(0); return true
        case 119: player.seek(d.duration); d.ensureVisible(d.duration); return true
        case 49:
            if UserDefaults.standard.integer(forKey: "rightTab") == 3, d.dialogues.listenSelected(player: player) { return true }       // onglet Dialogues : espace écoute la réplique choisie
            player.togglePlay(); return true
        default: break
        }
        switch ch {
        case "i": d.markIn(at: t, snap: snap && opts.passthrough); return true
        case "o": d.markOut(at: t); return true
        case "j", "k", "l": player.jkl(ch); return true
        case "[": d.selectAdjacent(-1, from: t); if let s = d.segments.first(where: { $0.id == d.selected }) { player.seek(s.start) }; return true
        case "]": d.selectAdjacent(1, from: t); if let s = d.segments.first(where: { $0.id == d.selected }) { player.seek(s.start) }; return true
        default: return false
        }
    }
}
