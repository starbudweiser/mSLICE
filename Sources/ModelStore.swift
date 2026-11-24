// mSLICE — modèles externes OPTIONNELS, jamais embarqués : téléchargés à la demande, avec l'accord de l'utilisateur, empreinte SHA-256 vérifiée,
// supprimables à tout moment. Premier usage prévu : la reconnaissance des personnages (macOS n'expose aucune identité de visage).
//
// Règles : HTTPS seulement (HTTP uniquement vers cette machine, pour les essais) ; taille plafonnée à 1,5 fois la taille annoncée ;
// le fichier n'est installé que si l'empreinte correspond exactement ; installation atomique ; rien n'est envoyé hors du Mac
// (la requête ne contient que l'adresse du modèle). Tant qu'aucun modèle n'a été retenu (licence, taille, qualité à valider), `url` reste nil
// et l'interface le dit au lieu de proposer un téléchargement.
import CryptoKit
import Foundation

struct ModelSpec: Identifiable, Sendable {
    let id: String
    let sizeMB: Int
    let url: URL?                 // nil : modèle pas encore retenu
    let sha256: String?           // hexadécimal minuscule
    let license: String
    var available: Bool { url != nil && sha256 != nil }
}

enum ModelCatalog {
    /// Identité des personnages. Pistes à départager par essai (étape « Essai des modèles ») : DINOv2-S (Apache 2.0) pour les personnages et créatures,
    /// ou un modèle de visage sous licence compatible. Les modèles de visage courants (InsightFace, ArcFace) sont non commerciaux : exclus.
    static let characters = ModelSpec(id: "characters", sizeMB: 100, url: nil, sha256: nil, license: "Apache 2.0 (à confirmer)")
    static let all = [characters]
}

@MainActor
final class ModelStore: ObservableObject {
    static let shared = ModelStore()
    enum State: Equatable { case notInstalled, downloading(Double), installed, failed(String) }

    @Published private(set) var states: [String: State] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    nonisolated static var dir: URL {
        let d = Env.supportDir.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    nonisolated static func folder(_ spec: ModelSpec) -> URL { dir.appendingPathComponent(spec.id, isDirectory: true) }
    nonisolated static func file(_ spec: ModelSpec) -> URL { folder(spec).appendingPathComponent("model.bin") }
    nonisolated private static func manifest(_ spec: ModelSpec) -> URL { folder(spec).appendingPathComponent("manifest.json") }

    /// Installé = fichier présent, de la taille notée à l'installation, avec l'empreinte attendue au manifeste. Avant de CHARGER un modèle, `verified` recalcule son empreinte.
    func state(_ spec: ModelSpec) -> State {
        if let s = states[spec.id] { if case .installed = s, !Self.isInstalled(spec) { return .notInstalled }; return s }
        return Self.isInstalled(spec) ? .installed : .notInstalled
    }
    nonisolated static func isInstalled(_ spec: ModelSpec) -> Bool {
        guard let want = spec.sha256, FileManager.default.fileExists(atPath: file(spec).path),
              let d = try? Data(contentsOf: manifest(spec)), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], o["sha256"] as? String == want,
              let size = (try? FileManager.default.attributesOfItem(atPath: file(spec).path)[.size] as? Int64), (o["size"] as? NSNumber)?.int64Value == size else { return false }
        return true
    }

    /// Recalcule l'empreinte du fichier installé : à faire avant d'utiliser le modèle (un fichier remplacé ou corrompu n'est jamais chargé).
    nonisolated static func verified(_ spec: ModelSpec) -> Bool {
        guard isInstalled(spec), let want = spec.sha256, let got = try? hash(of: file(spec)) else { return false }
        return got == want.lowercased()
    }

    /// Adresse acceptée : HTTPS, ou HTTP vers cette machine (essais).
    nonisolated static func allowed(_ u: URL) -> Bool {
        if u.scheme == "https" { return true }
        return u.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(u.host ?? "")
    }

    func install(_ spec: ModelSpec) {
        guard tasks[spec.id] == nil, let url = spec.url, let want = spec.sha256, Self.allowed(url) else { states[spec.id] = .failed("unavailable"); return }
        states[spec.id] = .downloading(0)
        let id = spec.id, expected = Int64(spec.sizeMB) * 1_048_576
        tasks[id] = Task { [weak self] in
            let result = await Self.download(url, expected: expected, sha256: want, spec: spec) { p in Task { @MainActor in if case .downloading = self?.states[id] { self?.states[id] = .downloading(p) } } }
            guard let self else { return }
            self.tasks[id] = nil
            switch result {
            case .success: self.states[id] = .installed
            case .failure(let e): self.states[id] = (e is CancellationError) ? .notInstalled : .failed(e.localizedDescription)
            }
        }
    }

    func cancel(_ spec: ModelSpec) { tasks[spec.id]?.cancel() }

    func remove(_ spec: ModelSpec) {
        tasks[spec.id]?.cancel()
        try? FileManager.default.removeItem(at: Self.folder(spec))
        states[spec.id] = .notInstalled
    }

    private struct Rejected: LocalizedError { let errorDescription: String? }

    /// Téléchargement par le système (fichier temporaire), plafonné en taille, annulable ; l'empreinte est calculée ensuite par morceaux.
    private final class Fetcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let cap: Int64
        let progress: @Sendable (Double) -> Void
        var cont: CheckedContinuation<URL, Error>?
        var session: URLSession?
        var task: URLSessionDownloadTask?
        private let lock = NSLock()
        private var done = false
        init(cap: Int64, progress: @escaping @Sendable (Double) -> Void) { self.cap = cap; self.progress = progress }

        private func finish(_ r: Result<URL, Error>) {
            lock.lock(); if done { lock.unlock(); return }; done = true; let c = cont; cont = nil; lock.unlock()
            session?.invalidateAndCancel()
            switch r { case .success(let u): c?.resume(returning: u); case .failure(let e): c?.resume(throwing: e) }
        }
        func start(_ url: URL) async throws -> URL {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
                    cont = c
                    let cfg = URLSessionConfiguration.ephemeral
                    cfg.httpCookieStorage = nil; cfg.urlCredentialStorage = nil; cfg.timeoutIntervalForRequest = 30
                    let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
                    session = s
                    var req = URLRequest(url: url); req.httpShouldHandleCookies = false
                    let t = s.downloadTask(with: req); task = t; t.resume()
                }
            } onCancel: { self.finish(.failure(CancellationError())) }
        }
        func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData n: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
            if w > cap || e > cap { finish(.failure(Rejected(errorDescription: "size"))); return }
            if e > 0 { progress(min(Double(w) / Double(e), 1)) }
        }
        func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            if let h = t.response as? HTTPURLResponse, !(200 ..< 300).contains(h.statusCode) { finish(.failure(Rejected(errorDescription: "HTTP \(h.statusCode)"))); return }
            let keep = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-model-\(UUID().uuidString)")
            do { try FileManager.default.moveItem(at: location, to: keep); finish(.success(keep)) } catch { finish(.failure(error)) }
        }
        func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError error: Error?) { if let error { finish(.failure(error)) } }
    }

    nonisolated static func hash(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hasher = SHA256()
        while let d = try h.read(upToCount: 1 << 20), !d.isEmpty { hasher.update(data: d) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Télécharge, vérifie l'empreinte, n'installe qu'un fichier conforme.
    nonisolated private static func download(_ url: URL, expected: Int64, sha256 want: String, spec: ModelSpec, progress: @escaping @Sendable (Double) -> Void) async -> Result<Void, Error> {
        let fm = FileManager.default
        let folder = ModelStore.folder(spec)
        let part = folder.appendingPathExtension("part")
        var temp: URL?
        defer { if let temp { try? fm.removeItem(at: temp) }; try? fm.removeItem(at: part) }
        do {
            temp = try await Fetcher(cap: expected * 3 / 2, progress: progress).start(url)
            guard let temp else { throw Rejected(errorDescription: "download") }
            guard try hash(of: temp) == want.lowercased() else { throw Rejected(errorDescription: "checksum") }
            try? fm.removeItem(at: part)
            try fm.createDirectory(at: part, withIntermediateDirectories: true)
            try fm.moveItem(at: temp, to: part.appendingPathComponent("model.bin"))
            let size = (try fm.attributesOfItem(atPath: part.appendingPathComponent("model.bin").path)[.size] as? Int64) ?? 0
            let manifest = try JSONSerialization.data(withJSONObject: ["id": spec.id, "sha256": want, "size": size, "installed": ISO8601DateFormatter().string(from: Date()), "license": spec.license])
            try manifest.write(to: part.appendingPathComponent("manifest.json"))
            try? fm.removeItem(at: folder)
            try fm.moveItem(at: part, to: folder)
            progress(1)
            return .success(())
        } catch { return .failure(error) }
    }
}
