// mSLICE — un fichier ouvert (morceaux, bistouri I / O, annulation, mémoire de session) et l'état général de l'appli.
import AppKit
import CryptoKit
import SwiftUI

/// Mémoire des morceaux de chaque fichier, restaurés à sa réouverture.
enum SessionStore {
    static var dir: URL {
        if let t = ProcessInfo.processInfo.environment["MSLICE_SESSION_DIR"] { try? FileManager.default.createDirectory(atPath: t, withIntermediateDirectories: true); return URL(fileURLWithPath: t, isDirectory: true) }
        let d = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/\(AppModel.isDev ? "mSLICE DEV" : "mSLICE")/sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func key(_ info: MediaInfo) -> String {
        let mtime = (try? info.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        return SHA256.hash(data: Data("\(info.url.path)|\(info.size)|\(mtime)".utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }
    struct Session: Codable { var segments: [Segment] = []; var baseName: String?; var mergeName: String? }
    static func load(_ info: MediaInfo) -> Session {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(key(info) + ".json")) else { return Session() }
        var s = (try? JSONDecoder().decode(Session.self, from: d)) ?? Session(segments: (try? JSONDecoder().decode([Segment].self, from: d)) ?? [])   // anciens fichiers : liste seule
        s.segments = s.segments.filter { $0.end > $0.start && $0.start >= 0 && $0.end <= info.duration + 0.5 }
        return s
    }
    static func save(_ info: MediaInfo, _ s: Session) {
        let f = dir.appendingPathComponent(key(info) + ".json")
        if s.segments.isEmpty && (s.baseName ?? "").isEmpty && (s.mergeName ?? "").isEmpty { try? FileManager.default.removeItem(at: f); return }
        try? JSONEncoder().encode(s).write(to: f, options: .atomic)
    }
}

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
    @Published var viewStart = 0.0
    @Published var viewSpan: Double
    let peaks = PeakStore()
    let strip: Filmstrip
    let cancel = CancelToken()
    var onSegmentsChange: (() -> Void)?
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
    }

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
    func addSegment(_ a: Double, _ b: Double) {
        var lo = max(0, min(a, b)), hi = min(duration, max(a, b))
        let overlapping = segments.filter { $0.start <= hi && $0.end >= lo }
        for s in overlapping { lo = min(lo, s.start); hi = max(hi, s.end) }
        var list = segments.filter { s in !overlapping.contains(where: { $0.id == s.id }) }
        let new = Segment(start: lo, end: hi)
        list.append(new); list.sort { $0.start < $1.start }
        segments = list; selected = new.id
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

enum Sheet: Equatable { case none, export, done }

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let isDev = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    /// Lancé par un essai automatique (`--selftest-*`) : jamais de Finder qui s'ouvre, jamais de fichier mis à la corbeille.
    static let isSelfTest = CommandLine.arguments.contains { $0.hasPrefix("--selftest") }

    @Published var docs: [Doc] = []
    @Published var current: Doc?
    @Published var sheet: Sheet = .none
    @Published var run: ExportRun?
    @Published var toast: String?
    @Published var loading = 0
    @Published var opts: ExportOptions { didSet { if let d = try? JSONEncoder().encode(opts) { UserDefaults.standard.set(d, forKey: "export.opts") } } }
    @Published var snap = true
    @Published var showShortcuts = false
    let player = PlayerModel()
    weak var mainWindow: NSWindow?
    var testMode = false          // essais sans fenêtre : les touches simulées sont acceptées sans fenêtre active

    init() {
        if let d = UserDefaults.standard.data(forKey: "export.opts"), let o = try? JSONDecoder().decode(ExportOptions.self, from: d) { opts = o } else { opts = ExportOptions() }
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
        Task { await player.load(d.info) }
    }

    func close(_ d: Doc) {
        d.cancel.cancel()
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

    var canExport: Bool { current.map { !$0.segments.isEmpty } ?? false && sheet == .none }

    func exportNow() {
        guard let d = current, !d.segments.isEmpty, sheet == .none else { return }
        var o = opts
        // La copie directe n'est possible que si les codecs entrent dans le conteneur choisi.
        if o.passthrough, !Planner.canCopy(info: d.info, to: o.format) { flash(L.t("err.cantcopy")); return }
        if o.passthrough, !d.info.isAudioOnly, o.resolvedFormat(for: d.info).isAudio, d.info.audio == nil { flash(L.t("err.noaudio")); return }
        if !o.passthrough, o.format == .same { o.format = d.info.isAudioOnly ? .m4a : .mp4 }
        let outs = Planner.outputs(info: d.info, segments: d.segments, opts: o, keyframes: d.keyframes, base: d.baseName, mergeName: d.mergeName)
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

    func cancelExport() { run?.cancel.cancel() }
    func closeSheet() { sheet = .none; run = nil }
    func trashOriginal() { if let u = current?.url { NSWorkspace.shared.recycle([u]) { _, _ in }; current.map { close($0) } ; closeSheet() } }
    func reveal() { if let r = run?.results, !r.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(r) } }

    // MARK: Clavier

    func handleKey(_ e: NSEvent) -> Bool {
        if !testMode { guard let win = NSApp.keyWindow, win === mainWindow, !(win.firstResponder is NSText) else { return false } }
        if sheet != .none {
            if e.keyCode == 53 { if sheet == .export { cancelExport() } else { closeSheet() }; return true }
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
        case 49: player.togglePlay(); return true
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
