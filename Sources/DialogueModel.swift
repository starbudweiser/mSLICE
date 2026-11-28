// mSLICE — état de l'onglet « Dialogues » pour un fichier : choix de la source du texte (sous-titres intégrés, fichier à côté, transcription de macOS), extraction
// (annulable), liste des répliques (recherche, corrections, écoute) et piste sous la timeline. Les répliques sont gardées (`DialogueStore`).
import AppKit
import Combine
import SwiftUI

@MainActor
final class DialogueModel: ObservableObject {
    unowned let doc: Doc
    enum Phase { case source, extracting, list, send, sending, sent }
    enum Choice: Hashable { case subtitles(String), transcribe }

    @Published private(set) var data: DialogueSet? { didSet { colorOrder = nil } }
    private var playSink: AnyCancellable?
    private var colorOrder: [String: Int]?                  // nom → rang de première réplique, pour la couleur (recalculé quand les répliques ou les noms changent)
    @Published private(set) var phase: Phase = .source
    @Published private(set) var sources: [SubtitleSource] = []
    @Published var choice: Choice = .transcribe
    @Published var language = "fr-FR"
    private var languageChosen = false          // l'utilisateur a choisi la langue lui-même : plus de détection
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
    // Envoi à mCASTING
    @Published var cast = DialogueModel.loadCast()
    @Published var sendNames: [String: String] = [:]       // nom affiché → nom envoyé à mCASTING
    @Published private(set) var sendProgress = 0.0
    @Published private(set) var sendFailure: String?
    @Published private(set) var sendResult: CastingSend.Result?
    private var sendJob: AnalysisJob?
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
        playSink = AppModel.shared.player.$time.sink { [weak self] t in self?.follow(t) }
        if data?.kind == .transcript, data?.aligned != true { Task { [weak self] in await self?.alignTimings() } }              // anciennes transcriptions : recalées à l'ouverture
        findSink = doc.find.objectWillChange.sink { [weak self] _ in self?.colorOrder = nil; DispatchQueue.main.async { self?.objectWillChange.send(); self?.autoVote() } }      // un protagoniste renommé change les noms affichés
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
        refineSpeakers()
    }

    /// Affine l'attribution avec le vote de chaque réplique : empreintes de voix calculées à l'intérieur de la réplique, classées sur les profils des voix (`LineVoices`).
    /// Tourne en arrière-plan ; les noms des sous-titres et les choix manuels ne bougent pas.
    func refineSpeakers() {
        guard !voting else { pendingVote = true; return }
        voting = true
        Task { [weak self] in
            defer { if let self { self.voting = false; if self.pendingVote { self.pendingVote = false; self.refineSpeakers() } } }
            guard let self, let v = self.doc.find.voices, let lines = self.data?.lines else { return }
            let todo = lines.filter { !$0.discarded && $0.manual != true && $0.who == nil }
            // les répliques attribuées à la main à un protagoniste qui a une voix : références pour les profils
            let taught: [(line: DialogueLine, voice: Int32)] = lines.compactMap { l in
                guard !l.discarded, l.manual == true, let sp = l.speaker, let voice = self.doc.find.protagonist(sp)?.voice else { return nil }
                return (l, voice)
            }
            let votes = await LineVoices.votes(todo, taught: taught, info: self.doc.info, voices: v)
            guard !votes.isEmpty, self.data != nil else { return }
            self.mutate { Speakers.apply(&$0, candidates: self.doc.find.speakerCandidates(), votes: votes); $0.voted = true }
        }
    }
    private var pendingVote = false
    private var voting = false, triedVote = false
    /// Les répliques déjà là (ouverture d'un fichier analysé avant cette amélioration) sont affinées une fois, dès que les voix sont connues.
    private func autoVote() {
        guard let d = data, d.voted != true, !voting, !triedVote, doc.find.voices != nil, !doc.find.protagonists.isEmpty else { return }
        triedVote = true
        refineSpeakers()
    }

    func setSpeaker(_ id: UUID, protagonist: String?) {
        mutate { $0.setSpeaker(id, speaker: protagonist, name: nil) }
        if protagonist != nil { refineSpeakers() }                // la correction sert de référence : les autres répliques sont reclassées
    }
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
        if let i = doc.find.protagonists.firstIndex(where: { $0.title == n }) { return Self.palette[i % Self.palette.count] }        // une couleur par protagoniste, partout
        if colorOrder == nil {                                  // une seule passe sur les répliques (la timeline appelle ceci pour chacune à chaque dessin)
            var m: [String: Int] = [:]
            for l in data?.lines ?? [] { if let x = displayName(l), m[x] == nil { m[x] = m.count } }
            colorOrder = m
        }
        return Self.palette[(colorOrder?[n] ?? 0) % Self.palette.count]
    }
    func color(named n: String) -> Color { Color(nsColor: nsColor(named: n)) }
    func protagonist(named n: String) -> Protagonist? { protagonists.first { $0.title == n } }

    // MARK: Envoi à mCASTING

    private static func loadCast() -> CastingOptions {
        var o = CastingOptions(); let d = UserDefaults.standard
        if let k = d.string(forKey: "dlg.cast.kind") { o.kind = k }
        if d.object(forKey: "dlg.cast.audio") != nil { o.audio = d.bool(forKey: "dlg.cast.audio") }
        if d.object(forKey: "dlg.cast.isolate") != nil { o.isolate = d.bool(forKey: "dlg.cast.isolate") }
        if d.object(forKey: "dlg.cast.tags") != nil { o.tags = d.bool(forKey: "dlg.cast.tags") }
        return o
    }
    private func saveCast() {
        let d = UserDefaults.standard
        d.set(cast.kind, forKey: "dlg.cast.kind"); d.set(cast.audio, forKey: "dlg.cast.audio"); d.set(cast.isolate, forKey: "dlg.cast.isolate"); d.set(cast.tags, forKey: "dlg.cast.tags")
        mutate { $0.castTitle = cast.title; $0.castEpisode = cast.episode }
    }

    var castingAvailable: Bool { CastingSend.available }
    var voiceIsolationAvailable: Bool { VoiceIsolation.available }
    /// Répliques à envoyer : les non écartées, dans l'ordre du temps.
    var sendable: [DialogueLine] { (data?.lines ?? []).filter { !$0.discarded }.sorted { $0.start < $1.start } }

    func openSend() {
        guard hasLines else { return }
        if cast.title.isEmpty {
            if let t = data?.castTitle, !t.isEmpty { cast.title = t }
            else { cast.title = doc.info.url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ") }
        }
        if cast.episode.isEmpty { cast.episode = data?.castEpisode ?? "" }
        let l = (data?.language ?? language).prefix(2).lowercased()
        cast.lang = ["fr", "en", "es", "it", "de"].contains(String(l)) ? String(l) : "fr"
        if !voiceIsolationAvailable { cast.isolate = false }
        for n in speakerNames.map(\.name) where sendNames[n] == nil { sendNames[n] = n }
        sendFailure = nil
        phase = .send
    }

    func closeSend() { phase = .list }

    func send() {
        guard phase == .send, !sendable.isEmpty else { return }
        guard castingAvailable else { sendFailure = "dlg.send.nocasting"; return }
        saveCast()
        let lines = sendable.map { l -> CastingLine in
            let n = displayName(l).flatMap { sendNames[$0] ?? $0 }
            return CastingLine(start: l.start, end: l.end, text: l.text, character: n?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : n)
        }
        let job = AnalysisJob(); sendJob = job
        sendProgress = 0; sendFailure = nil; phase = .sending
        let info = doc.info, options = cast
        Task { [weak self] in
            do {
                let r = try await CastingSend.send(info, lines: lines, options: options, job: job) { p in Task { @MainActor [weak self] in self?.sendProgress = p } }
                self?.sendResult = r; self?.phase = .sent
            } catch {
                guard let self else { return }
                self.phase = .send
                if job.cancelled { return }
                switch error as? CastingSend.Failure {
                case .isolation?: self.sendFailure = "dlg.send.fail.isolation"
                case .ffmpeg?, .noAudio?: self.sendFailure = "dlg.send.fail.audio"
                default: self.sendFailure = "dlg.send.fail"
                }
            }
            self?.sendJob = nil
        }
    }

    func cancelSend() { sendJob?.cancel() }
    func finishSend() { sendResult = nil; phase = .list }
    func openCasting() {
        guard let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CastingSend.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Morceaux et fichiers

    @Published private(set) var exporting = false
    @Published private(set) var exportProgress = 0.0

    /// Les répliques visibles et non écartées (avec le filtre de personnage et la recherche), pour les morceaux et l'export.
    var chosen: [DialogueLine] { visible.filter { !$0.discarded }.sorted { $0.start < $1.start } }

    private func castingLines(_ lines: [DialogueLine]) -> [CastingLine] {
        lines.map { l in CastingLine(start: l.start, end: l.end, text: l.text, character: displayName(l)) }
    }

    /// Ajoute les répliques choisies aux morceaux du fichier (avec leurs marges), annulable par ⌘Z.
    func addToPieces() {
        let lines = chosen
        guard !lines.isEmpty else { return }
        let spans = CastingSend.spans(castingLines(lines), duration: doc.duration)
        doc.snapshot()
        for s in spans where s.end > s.start { doc.addSegment(s.start, s.end) }
        if let f = spans.first { doc.ensureVisible(f.start) }
        AppModel.shared.flash(L.n("dlg.pieces.added", lines.count))
    }

    /// Un WAV par réplique choisie et un SRT, dans un dossier à côté de la vidéo (voix seule si l'option est cochée dans l'écran d'envoi).
    func exportFiles() {
        let lines = chosen
        guard !lines.isEmpty, !exporting, doc.info.audio != nil else { return }
        exporting = true; exportProgress = 0
        let job = AnalysisJob(); sendJob = job
        let info = doc.info, isolate = cast.isolate && voiceIsolationAvailable, cl = castingLines(lines)
        Task { [weak self] in
            do {
                let folder = try await DialogueExport.write(info, lines: cl, isolate: isolate, job: job) { p in Task { @MainActor [weak self] in self?.exportProgress = p } }
                self?.exporting = false
                AppModel.shared.flash(L.n("dlg.export.done", lines.count, folder.lastPathComponent))
                if !AppModel.isSelfTest { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
            } catch {
                self?.exporting = false
                if !job.cancelled { AppModel.shared.flash(L.t("dlg.export.fail")) }
            }
            self?.sendJob = nil
        }
    }

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

    static func defaultLanguage(_ info: MediaInfo, trustTag: Bool = true) -> String {
        let map: [String: String] = ["fre": "fr-FR", "fra": "fr-FR", "fr": "fr-FR", "eng": "en-US", "en": "en-US", "spa": "es-ES", "es": "es-ES", "ita": "it-IT", "it": "it-IT", "ger": "de-DE", "deu": "de-DE", "de": "de-DE"]
        if trustTag, let l = info.audio?.lang.lowercased(), let m = map[l] { return m }
        let sys = (Locale.preferredLanguages.first ?? "en").prefix(2).lowercased()
        return map[String(sys)] ?? "en-US"
    }

    func refreshAssets() async { assets = await TranscriptionSupport.assetState(language) }

    func setLanguage(_ code: String) { language = code; languageChosen = true; Task { await refreshAssets() } }

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
                // Langue non choisie par l'utilisateur : la balise du fichier se trompe souvent (« eng » pour des paroles en français), on écoute un extrait.
                if !self.languageChosen {
                    self.begin(step: "speech")
                    let job = AnalysisJob(); self.job = job
                    let sys = (Locale.preferredLanguages.first ?? "en").prefix(2).lowercased()
                    let cands = [self.language, Self.defaultLanguage(self.doc.info, trustTag: false), "fr-FR", "en-US"] + TranscriptionSupport.languages.map(\.code).filter { $0.hasPrefix(sys) }
                    let guess = await Transcriber.detectLanguage(self.doc.info, candidates: cands, job: job)
                    self.job = nil
                    if job.cancelled { return }
                    if let guess { self.language = guess }
                    self.phase = .source
                }
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
        if kind == .transcript { Task { [weak self] in await self?.alignTimings(); self?.refineSpeakers() } }
        else { refineSpeakers() }
    }

    /// Recale les débuts et les fins sur la parole réelle (niveau sonore du fichier) : ce qu'on entend à la position d'une réplique est bien cette réplique.
    func alignTimings() async {
        guard var s = data, s.kind == .transcript, s.aligned != true, doc.info.audio != nil else { return }
        await doc.ensureSilences()
        guard let lp = doc.loudness, !lp.frameDB.isEmpty, var cur = data, cur == s || cur.lines.count == s.lines.count else { return }
        s = cur
        let order = s.lines.indices.sorted { s.lines[$0].start < s.lines[$1].start }
        let fixed = lp.align(order.map { (s.lines[$0].start, s.lines[$0].end) })
        for (k, i) in order.enumerated() { s.lines[i].start = fixed[k].start; s.lines[i].end = fixed[k].end }
        s.aligned = true
        cur = s; data = cur
        DialogueStore.save(cur, for: doc.info)
    }

    /// Pendant la lecture, la réplique choisie suit ce qu'on entend (sans déplacer la tête de lecture).
    private func follow(_ t: Double) {
        guard AppModel.shared.player.isPlaying, editing == nil, let lines = data?.lines else { return }
        guard let l = lines.first(where: { !$0.discarded && t >= $0.start && t < $0.end }), l.id != selected else { return }
        selected = l.id
    }

    private func fail(_ key: String) { failure = key; phase = .source }

    func cancel() {
        sendJob?.cancel()
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
