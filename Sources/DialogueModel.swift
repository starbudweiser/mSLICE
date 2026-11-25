// mSLICE — état de l'onglet « Dialogues » pour un fichier : choix de la source du texte (sous-titres intégrés, fichier à côté, transcription de macOS), extraction
// (annulable), liste des répliques (recherche, corrections, écoute) et piste sous la timeline. Les répliques sont gardées (`DialogueStore`).
import AppKit
import Combine
import SwiftUI

@MainActor
final class DialogueModel: ObservableObject {
    unowned let doc: Doc
    enum Phase { case source, extracting, list }
    enum Choice: Hashable { case subtitles(String), transcribe }

    @Published private(set) var data: DialogueSet?
    @Published private(set) var phase: Phase = .source
    @Published private(set) var sources: [SubtitleSource] = []
    @Published var choice: Choice = .transcribe
    @Published var language = "fr-FR"
    @Published private(set) var assets: TranscriptionSupport.AssetState = .unavailable
    @Published var askInstall = false                      // l'accord de l'utilisateur est demandé avant de télécharger les ressources de langue
    @Published private(set) var installing = false
    @Published private(set) var progress = 0.0
    @Published private(set) var step = ""                  // « sub », « speech » : étape en cours
    @Published private(set) var startedAt = Date()
    @Published private(set) var failure: String?           // clé de texte de l'erreur à afficher dans la source
    @Published var query = ""
    @Published var showDiscarded = false
    @Published var selected: UUID?
    @Published var editing: UUID?
    @Published var showLane = true
    @Published var filter: String?                         // nom du personnage dont on ne montre que les répliques
    private var findSink: AnyCancellable?
    private var job: AnalysisJob?
    private var listenToken = UUID()
    private var saveWork: DispatchWorkItem?

    init(doc: Doc) {
        self.doc = doc
        sources = Subtitles.sources(for: doc.info)
        language = Self.defaultLanguage(doc.info)
        if let s = DialogueStore.load(doc.info), !s.lines.isEmpty { data = s; phase = .list }
        choice = sources.first.map { .subtitles($0.id) } ?? .transcribe
        Task { [weak self] in await self?.refreshAssets() }
        findSink = doc.find.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.objectWillChange.send() } }      // un protagoniste renommé change les noms affichés
    }

    // MARK: Personnages

    var protagonists: [Protagonist] { doc.find.protagonists }

    /// Nom affiché d'une réplique : celui des sous-titres, sinon celui du protagoniste attribué ; nil si personne.
    func displayName(_ l: DialogueLine) -> String? {
        if let w = l.who { return w }
        if let sp = l.speaker { return doc.find.protagonist(sp)?.title }
        return nil
    }

    /// Un nom qui n'est ni un nom de protagoniste ni un nom libre : « Personnage 3 » (sans nom donné).
    func isNamed(_ l: DialogueLine) -> Bool {
        if l.who != nil { return true }
        if let sp = l.speaker { return doc.find.protagonist(sp)?.name != nil }
        return false
    }

    /// Les personnages qui parlent, du plus bavard au moins bavard, avec leur nombre de répliques.
    var speakerNames: [(name: String, count: Int)] {
        var c: [String: Int] = [:]
        for l in data?.lines ?? [] where !l.discarded { if let n = displayName(l) { c[n, default: 0] += 1 } }
        return c.map { (name: $0.key, count: $0.value) }.sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }
    var unknownCount: Int { data?.lines.filter { !$0.discarded && displayName($0) == nil }.count ?? 0 }
    var hasProtagonists: Bool { !protagonists.isEmpty }

    /// Attribue les répliques d'après les protagonistes reconnus (visages + voix) ; les noms des sous-titres et les choix manuels ne bougent pas.
    func attribute() {
        mutate { Speakers.apply(&$0, candidates: doc.find.speakerCandidates()) }
    }

    func setSpeaker(_ id: UUID, protagonist: String?) { mutate { $0.setSpeaker(id, speaker: protagonist, name: nil) } }
    /// Nom tapé pour une réplique : si elle est attribuée à un protagoniste, c'est lui qui est renommé (même nom partout, onglet Trouver compris) ;
    /// sinon c'est un nom libre gardé dans la réplique.
    func setName(_ id: UUID, _ name: String) {
        let n = DialogueText.sanitize(name)
        guard !n.isEmpty else { return }
        if let l = data?.lines.first(where: { $0.id == id }), let sp = l.speaker, let p = doc.find.protagonist(sp) {
            if let person = p.person { doc.find.rename(person, to: n) }
            if let voice = p.voice { doc.find.renameVoice(voice, to: n) }
            mutate { if let i = $0.lines.firstIndex(where: { $0.id == id }) { $0.lines[i].manual = true } }
            return
        }
        mutate { $0.setSpeaker(id, speaker: nil, name: n) }
    }

    /// Couleur d'un personnage : la même sur la pastille, la pastille de filtre et la piste sous la timeline (selon l'ordre de première réplique).
    static let palette: [NSColor] = [0xf08a52, 0x0a84ff, 0x30d158, 0xbf5af2, 0xff375f, 0xffd60a, 0x64d2ff, 0xac8e68].map { Theme.rgb($0) }
    func nsColor(_ l: DialogueLine) -> NSColor {
        guard let n = displayName(l) else { return Theme.text2NS }
        return nsColor(named: n)
    }
    func nsColor(named n: String) -> NSColor {
        var order: [String] = []
        for l in data?.lines ?? [] { if let x = displayName(l), !order.contains(x) { order.append(x) } }
        return Self.palette[(order.firstIndex(of: n) ?? 0) % Self.palette.count]
    }
    func color(named n: String) -> Color { Color(nsColor: nsColor(named: n)) }
    func protagonist(named n: String) -> Protagonist? { protagonists.first { $0.title == n } }

    // MARK: Piste et liste

    var lane: [DialogueLine] { data?.lines ?? [] }
    var hasLines: Bool { !(data?.lines.isEmpty ?? true) }
    var laneVisible: Bool { showLane && hasLines }
    var canTranscribe: Bool { TranscriptionSupport.available && doc.info.audio != nil }
    var activeCount: Int { data?.lines.filter { !$0.discarded }.count ?? 0 }
    var discardedCount: Int { data?.lines.filter(\.discarded).count ?? 0 }

    /// Répliques affichées : filtre de recherche (sans tenir compte des majuscules ni des accents) et des écartées.
    var visible: [DialogueLine] {
        guard let lines = data?.lines else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        return lines.filter { l in
            (showDiscarded || !l.discarded) && (filter == nil || displayName(l) == filter) && (q.isEmpty || l.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                                                   || (displayName(l)?.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil))
        }
    }

    // MARK: Source

    static func defaultLanguage(_ info: MediaInfo) -> String {
        let map: [String: String] = ["fre": "fr-FR", "fra": "fr-FR", "fr": "fr-FR", "eng": "en-US", "en": "en-US", "spa": "es-ES", "es": "es-ES", "ita": "it-IT", "it": "it-IT", "ger": "de-DE", "deu": "de-DE", "de": "de-DE"]
        if let l = info.audio?.lang.lowercased(), let m = map[l] { return m }
        let sys = (Locale.preferredLanguages.first ?? "en").prefix(2).lowercased()
        return map[String(sys)] ?? "en-US"
    }

    func refreshAssets() async { assets = await TranscriptionSupport.assetState(language) }

    func setLanguage(_ code: String) { language = code; Task { await refreshAssets() } }

    func title(_ s: SubtitleSource) -> String {
        let lang = s.language.isEmpty ? "" : " · " + s.language
        switch s.origin {
        case .embedded: return L.t("dlg.src.embedded") + lang + (s.title.isEmpty ? "" : " · " + s.title)
        case .file(let u): return L.t("dlg.src.file", u.lastPathComponent)
        }
    }

    // MARK: Extraction

    func start() {
        guard phase != .extracting, !installing else { return }
        failure = nil
        switch choice {
        case .subtitles(let id):
            guard let src = sources.first(where: { $0.id == id }) else { return }
            begin(step: "sub")
            let info = doc.info
            Task { [weak self] in
                let lines = await Subtitles.load(src, info: info)
                guard let self, self.phase == .extracting else { return }
                if let lines { self.finish(lines, kind: .subtitles, detail: self.title(src), language: src.language) }
                else { self.fail("dlg.fail.subs") }
            }
        case .transcribe:
            guard canTranscribe else { fail("dlg.fail.unavailable"); return }
            Task { [weak self] in
                guard let self else { return }
                await self.refreshAssets()
                switch self.assets {
                case .installed: self.transcribe()
                case .needsDownload: self.askInstall = true
                default: self.fail("dlg.fail.language")
                }
            }
        }
    }

    /// L'utilisateur a accepté le téléchargement des ressources de langue d'Apple.
    func acceptInstall() {
        askInstall = false; installing = true
        let code = language
        Task { [weak self] in
            let ok = await TranscriptionSupport.install(code)
            guard let self else { return }
            self.installing = false
            await self.refreshAssets()
            if ok, self.assets == .installed { self.transcribe() } else { self.fail("dlg.fail.install") }
        }
    }

    private func transcribe() {
        begin(step: "speech")
        let job = AnalysisJob(); self.job = job
        let info = doc.info, lang = language
        Task { [weak self] in
            let lines = await AnalysisRunner.runDialogues(info, language: lang, job: job) { p in Task { @MainActor [weak self] in if self?.phase == .extracting { self?.progress = p.images } } }
            guard let self else { return }
            self.job = nil
            if job.cancelled { return }
            if let lines, !lines.isEmpty { self.finish(lines, kind: .transcript, detail: TranscriptionSupport.languages.first { $0.code == lang }?.label ?? lang, language: lang) }
            else { self.fail(lines == nil ? "dlg.fail.transcribe" : "dlg.fail.empty") }
        }
    }

    private func begin(step: String) {
        phase = .extracting; self.step = step; progress = 0; startedAt = Date()
    }

    private func finish(_ lines: [DialogueLine], kind: DialogueKind, detail: String, language: String) {
        var s = DialogueSet(duration: doc.duration, kind: kind, detail: detail, language: language)
        s.lines = lines.filter { $0.end > $0.start && $0.start < doc.duration + 1 }.map { var l = $0; l.end = min(l.end, doc.duration); return l }.filter { $0.end > $0.start }
        guard !s.lines.isEmpty else { fail("dlg.fail.empty"); return }
        Speakers.apply(&s, candidates: doc.find.speakerCandidates())
        data = s; selected = nil; editing = nil; query = ""; filter = nil; phase = .list
        DialogueStore.save(s, for: doc.info)
    }

    private func fail(_ key: String) { failure = key; phase = .source }

    func cancel() {
        job?.cancel(); job = nil
        if phase == .extracting { phase = data == nil ? .source : .list }
    }

    /// Retour au choix de la source (les répliques actuelles restent jusqu'à la prochaine extraction).
    func changeSource() { failure = nil; phase = .source }
    func backToList() { if hasLines { phase = .list } }

    /// Efface les répliques et leurs corrections.
    func clear() {
        data = nil; selected = nil; editing = nil; phase = .source
        DialogueStore.remove(doc.info)
    }

    // MARK: Sélection, écoute

    func select(_ id: UUID?, seek: Bool = true) {
        selected = id
        guard seek, let id, let l = data?.lines.first(where: { $0.id == id }) else { return }
        let p = AppModel.shared.player
        p.pause(); p.seek(l.start); doc.ensureVisible(l.start)
    }

    /// Joue la réplique choisie de son début à sa fin ; un second appel pendant l'écoute l'arrête. Faux s'il n'y en a pas.
    @discardableResult func listenSelected(player: PlayerModel) -> Bool {
        guard let id = selected, let l = data?.lines.first(where: { $0.id == id }) else { return false }
        if player.isPlaying { player.pause(); listenToken = UUID(); return true }
        listen(l, player: player)
        return true
    }

    func listen(_ l: DialogueLine, player: PlayerModel? = nil) {
        let p = player ?? AppModel.shared.player
        let token = UUID(); listenToken = token
        p.seek(l.start); doc.ensureVisible(l.start); p.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + l.duration + 0.1) { [weak self] in
            guard let self, self.listenToken == token else { return }
            p.pause()
        }
    }

    // MARK: Corrections

    private func mutate(_ change: (inout DialogueSet) -> Void) {
        guard var s = data else { return }
        change(&s); data = s
        saveWork?.cancel()
        let w = DispatchWorkItem { [info = doc.info] in DialogueStore.save(s, for: info) }
        saveWork = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    func setText(_ id: UUID, _ text: String) { mutate { $0.setText(id, text) } }
    func setDiscarded(_ id: UUID, _ v: Bool) { mutate { $0.setDiscarded(id, v) } }
    func split(_ id: UUID, at offset: Int) {
        mutate { if let n = $0.split(id, atOffset: offset) { selected = n } }
    }
}
