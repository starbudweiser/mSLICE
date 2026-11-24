// mSLICE — modèles externes OPTIONNELS, jamais embarqués : téléchargés à la demande, avec l'accord de l'utilisateur, empreinte SHA-256 vérifiée,
// supprimables à tout moment. Premier usage : la reconnaissance des personnages (macOS n'expose aucune identité de visage).
// Le catalogue et les fichiers installés sont dans `Analysis/ModelFiles.swift` (partagé avec le processus d'analyse).
//
// Règles : HTTPS seulement (HTTP uniquement vers cette machine, pour les essais) ; taille plafonnée à 1,5 fois la taille annoncée ;
// le fichier n'est installé que si l'empreinte correspond exactement ; installation atomique ; rien n'est envoyé hors du Mac
// (la requête ne contient que l'adresse du modèle).
//
// Archive Core ML : après le contrôle de l'empreinte, la liste des entrées est vérifiée (pas de chemin absolu ni de « .. », taille décompressée plafonnée),
// l'archive est décompressée dans un dossier de travail, aucun lien symbolique n'est toléré, le modèle est compilé, et seuls le modèle compilé, la licence
// et la notice sont gardés. L'empreinte de l'arbre compilé est notée au manifeste et recalculée avant chaque usage.
import CoreML
import CryptoKit
import Foundation

@MainActor
final class ModelStore: ObservableObject {
    static let shared = ModelStore()
    enum State: Equatable { case notInstalled, downloading(Double), installed, failed(String) }

    @Published private(set) var states: [String: State] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    func state(_ spec: ModelSpec) -> State {
        if let s = states[spec.id] { if case .installed = s, !ModelFiles.isInstalled(spec) { return .notInstalled }; return s }
        return ModelFiles.isInstalled(spec) ? .installed : .notInstalled
    }

    func install(_ spec: ModelSpec) {
        guard tasks[spec.id] == nil, let url = spec.url, let want = spec.sha256, ModelFiles.allowed(url) else { states[spec.id] = .failed("unavailable"); return }
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
        try? FileManager.default.removeItem(at: ModelFiles.folder(spec))
        states[spec.id] = .notInstalled
    }

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
            if w > cap || e > cap { finish(.failure(ModelRejected(errorDescription: "size"))); return }
            if e > 0 { progress(min(Double(w) / Double(e), 1)) }
        }
        func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            if let h = t.response as? HTTPURLResponse, !(200 ..< 300).contains(h.statusCode) { finish(.failure(ModelRejected(errorDescription: "HTTP \(h.statusCode)"))); return }
            let keep = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-model-\(UUID().uuidString)")
            do { try FileManager.default.moveItem(at: location, to: keep); finish(.success(keep)) } catch { finish(.failure(error)) }
        }
        func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError error: Error?) { if let error { finish(.failure(error)) } }
    }

    // MARK: Archive Core ML

    /// Lance un utilitaire système et rend sa sortie (courte).
    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ModelRejected(errorDescription: "archive") }
        return String(decoding: data, as: UTF8.self)
    }

    /// Contrôle la liste des entrées avant toute extraction, puis décompresse et refuse tout lien symbolique.
    nonisolated static func extract(zip: URL, into dest: URL, maxBytes: Int64 = 600 << 20) throws {
        let names = try run("/usr/bin/unzip", ["-Z1", zip.path]).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !names.isEmpty, names.count <= 400 else { throw ModelRejected(errorDescription: "archive") }
        for n in names {
            let bad = n.hasPrefix("/") || n.contains("\\") || n.split(separator: "/").contains("..") || n.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
            if bad { throw ModelRejected(errorDescription: "archive path") }
        }
        let totals = try run("/usr/bin/unzip", ["-Zt", zip.path])
        guard let r = totals.range(of: #"[0-9]+(?= bytes uncompressed)"#, options: .regularExpression), let total = Int64(totals[r]), total <= maxBytes else { throw ModelRejected(errorDescription: "archive size") }
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        _ = try run("/usr/bin/ditto", ["-x", "-k", zip.path, dest.path])
        _ = try ModelFiles.treeHash(of: dest)           // lève si un lien symbolique ou un fichier spécial s'y trouve
    }

    nonisolated private static func compile(_ package: URL, to dst: URL) async throws {
        let tmp = try await MLModel.compileModel(at: package)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.moveItem(at: tmp, to: dst)
    }

    /// Installe une archive Core ML déjà vérifiée (empreinte) : décompression contrôlée, compilation, licence et notice, manifeste.
    nonisolated private static func installArchive(zip: URL, into part: URL, spec: ModelSpec, sha: String) async throws {
        let fm = FileManager.default
        let payload = part.appendingPathComponent("payload", isDirectory: true)
        try extract(zip: zip, into: payload)
        let top = try fm.contentsOfDirectory(atPath: payload.path)
        let packages = top.filter { $0.hasSuffix(".mlpackage") }
        guard packages.count == 1 else { throw ModelRejected(errorDescription: "package") }
        try await compile(payload.appendingPathComponent(packages[0]), to: part.appendingPathComponent("model.mlmodelc"))
        for note in ["LICENSE.txt", "NOTICE.txt"] where top.contains(note) {
            let src = payload.appendingPathComponent(note)
            if let a = try? fm.attributesOfItem(atPath: src.path), a[.type] as? FileAttributeType == .typeRegular, (a[.size] as? Int64 ?? 0) < (1 << 20) { try? fm.copyItem(at: src, to: part.appendingPathComponent(note)) }
        }
        try? fm.removeItem(at: payload)
        let size = (try fm.attributesOfItem(atPath: zip.path)[.size] as? Int64) ?? 0
        let tree = try ModelFiles.treeHash(of: part.appendingPathComponent("model.mlmodelc"))
        let manifest = try JSONSerialization.data(withJSONObject: ["id": spec.id, "sha256": sha, "size": size, "tree": tree, "installed": ISO8601DateFormatter().string(from: Date()), "license": spec.license])
        try manifest.write(to: part.appendingPathComponent("manifest.json"))
    }

    /// Télécharge, vérifie l'empreinte, n'installe qu'un fichier conforme.
    nonisolated private static func download(_ url: URL, expected: Int64, sha256 want: String, spec: ModelSpec, progress: @escaping @Sendable (Double) -> Void) async -> Result<Void, Error> {
        var temp: URL?
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
        do {
            temp = try await Fetcher(cap: expected * 3 / 2, progress: progress).start(url)
            guard let temp else { throw ModelRejected(errorDescription: "download") }
            try await installFile(temp, spec: spec, sha256: want)
            progress(1)
            return .success(())
        } catch { return .failure(error) }
    }

    /// Installe un fichier déjà téléchargé : empreinte vérifiée d'abord, installation atomique (dossier de travail puis déplacement). Pour un fichier
    /// unique, `temp` est déplacé ; pour une archive Core ML, il est lu seulement (l'appelant le supprime).
    nonisolated static func installFile(_ temp: URL, spec: ModelSpec, sha256 want: String) async throws {
        let fm = FileManager.default
        let folder = ModelFiles.folder(spec)
        let part = folder.appendingPathExtension("part")
        defer { try? fm.removeItem(at: part) }
        guard try ModelFiles.hash(of: temp) == want.lowercased() else { throw ModelRejected(errorDescription: "checksum") }
        try? fm.removeItem(at: part)
        try fm.createDirectory(at: part, withIntermediateDirectories: true)
        switch spec.kind {
        case .file:
            try fm.moveItem(at: temp, to: part.appendingPathComponent("model.bin"))
            let size = (try fm.attributesOfItem(atPath: part.appendingPathComponent("model.bin").path)[.size] as? Int64) ?? 0
            let manifest = try JSONSerialization.data(withJSONObject: ["id": spec.id, "sha256": want, "size": size, "installed": ISO8601DateFormatter().string(from: Date()), "license": spec.license])
            try manifest.write(to: part.appendingPathComponent("manifest.json"))
        case .coreMLArchive:
            try await installArchive(zip: temp, into: part, spec: spec, sha: want)
        }
        try? fm.removeItem(at: folder)
        try fm.moveItem(at: part, to: folder)
    }
}
