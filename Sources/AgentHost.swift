// mSLICE — l'appli ouverte vue par les agents : fichiers ouverts, morceaux en direct, ouverture, tête de lecture ; et la prise locale
// par laquelle `mslice-mcp` (ou tout programme de l'utilisateur) lui transmet des appels d'outils.
import AppKit
import Foundation

@MainActor
final class AppAgentHost: AgentHost {
    static let shared = AppAgentHost()
    private var model: AppModel { AppModel.shared }

    private func doc(_ url: URL) -> Doc? { model.docs.first { $0.url.standardizedFileURL.path == url.standardizedFileURL.path } }

    func openFiles() -> [URL] { model.docs.map(\.url) }
    func currentFile() -> URL? { model.current?.url }
    func playhead() -> Double? { model.current == nil ? nil : model.player.time }
    func segments(of url: URL) -> [Segment]? { doc(url)?.segments }
    func setSegments(_ segs: [Segment], of url: URL) -> Bool {
        guard let d = doc(url) else { return false }
        d.snapshot(); d.segments = segs; d.selected = segs.first?.id; d.pendingIn = nil
        if let f = segs.first { d.ensureVisible(f.start) }
        return true
    }
    func open(_ url: URL) { model.open([url]) }      // sans activer l'appli : silencieux
    func seek(_ t: Double) { model.player.pause(); model.player.seek(t); model.current?.ensureVisible(t) }
    func notify(_ text: String) { model.flash(text) }
    func userExportFolder() -> String? { model.opts.folder }
    func analyze(_ url: URL, force: Bool) async -> AnalysisIndex? { await doc(url)?.find.analyzeAndWait(force: force) }
    func recognize(_ url: URL) async -> FaceIndex? { await doc(url)?.find.recognizeAndWait() }
    func recognizeVoices(_ url: URL) async -> VoiceIndex? { await doc(url)?.find.recognizeVoicesAndWait() }
    func editVoice(_ id: Int32, name: String?, person: Int32?, of url: URL) -> Bool {
        guard let d = doc(url), d.find.voices != nil else { return false }
        if let name { d.find.renameVoice(id, to: name) }
        if let person { d.find.linkVoice(id, to: person >= 0 ? person : nil) }
        return true
    }
    func renameSubject(_ id: Int32, to name: String, of url: URL) -> Bool {
        guard let d = doc(url), d.find.faces != nil else { return false }
        d.find.rename(id, to: name); return true
    }
}

/// Prise Unix locale : une ligne JSON par appel `{tool, args, client}`, une ligne de réponse `{content, isError}`.
final class AgentServer: @unchecked Sendable {
    static let shared = AgentServer()
    private var listenFD: Int32 = -1
    private let active = NSLock()
    private var connections = 0

    func start() {
        guard listenFD < 0 else { return }
        let path = AgentBridge.socketPath
        guard var addr = AgentBridge.address(path) else { return }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        let bound = withUnsafePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0, listen(fd, 8) == 0 else { close(fd); return }
        chmod(path, 0o600)
        listenFD = fd
        Thread.detachNewThread { [self] in
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { if errno == EINTR { continue }; break }
                var on: Int32 = 1; setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                active.lock(); let tooMany = connections >= 8; if !tooMany { connections += 1 }; active.unlock()
                if tooMany { close(c); continue }                          // au plus 8 clients à la fois
                Thread.detachNewThread { self.serve(c); self.active.lock(); self.connections -= 1; self.active.unlock() }
            }
        }
    }

    func stop() { if listenFD >= 0 { close(listenFD); listenFD = -1; unlink(AgentBridge.socketPath) } }

    private final class Box: @unchecked Sendable { var out = ToolOutput.text("internal error", error: true) }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        var carry = Data()
        while let line = AgentBridge.readLine(fd, carry: &carry) {
            guard let req = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let tool = req["tool"] as? String else { continue }
            let args = req["args"] as? [String: Any] ?? [:], client = req["client"] as? String ?? "agent"
            let box = Box(), sem = DispatchSemaphore(value: 0)
            Task { @MainActor in box.out = await Agent.run(tool, args, host: AppAgentHost.shared, client: client); sem.signal() }
            sem.wait()
            let resp: [String: Any] = ["content": box.out.content, "isError": box.out.isError]
            guard JSONSerialization.isValidJSONObject(resp), var d = try? JSONSerialization.data(withJSONObject: resp) else { continue }
            d.append(10)
            if !AgentBridge.writeAll(fd, d) { break }
        }
    }
}
