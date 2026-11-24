// mSLICE — modèles externes OPTIONNELS : catalogue et fichiers installés. Partagé avec le processus d'analyse (`mslice-mcp`), qui doit retrouver
// et VÉRIFIER le modèle sans dépendre de l'interface. Le téléchargement et l'installation sont dans `ModelStore.swift` (appli seulement).
//
// Un modèle est soit un fichier unique (`model.bin`), soit une archive Core ML (zip d'un `.mlpackage`) décompressée puis compilée à l'installation :
// il reste alors `model.mlmodelc`, la licence et la notice. Le manifeste (`manifest.json`) note l'empreinte SHA-256 de l'archive téléchargée et, pour
// une archive Core ML, l'empreinte de l'arbre de fichiers compilé : avant de CHARGER un modèle, `verified` la recalcule.
import CryptoKit
import Foundation

struct ModelSpec: Identifiable, Sendable {
    enum Kind: Sendable { case file, coreMLArchive }
    let id: String
    let sizeMB: Int
    let url: URL?                 // nil : modèle pas encore retenu
    let sha256: String?           // hexadécimal minuscule
    let license: String
    var kind: Kind = .file
    var available: Bool { url != nil && sha256 != nil }
}

enum ModelCatalog {
    /// Personnages (visages) : AuraFace-v1 de fal.ai (ArcFace ResNet-100, Apache 2.0), converti en Core ML 8 bits, hébergé dans une release du dépôt
    /// public `starbudweiser/mSLICE-models`. Le fichier ne change plus : toute nouvelle conversion = nouvelle release et nouvelle empreinte.
    static let characters = ModelSpec(
        id: "characters", sizeMB: 60,
        url: URL(string: "https://github.com/starbudweiser/mSLICE-models/releases/download/characters-auraface-1/AuraFace-CoreML-8bit.zip"),
        sha256: "2c1d331d88b4b7544a5835b810e6ca7203fcfc7d04b0be614787b4012331277b",
        license: "Apache 2.0 (AuraFace, fal.ai)", kind: .coreMLArchive)
    static let all = [characters]
}

struct ModelRejected: LocalizedError { let errorDescription: String? }

enum ModelFiles {
    /// `MSLICE_MODEL_DIR` redirige le dossier (essais).
    static var dir: URL {
        let d: URL
        if let t = ProcessInfo.processInfo.environment["MSLICE_MODEL_DIR"] { d = URL(fileURLWithPath: t, isDirectory: true) }
        else { d = Env.supportDir.appendingPathComponent("models", isDirectory: true) }
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func folder(_ spec: ModelSpec) -> URL { dir.appendingPathComponent(spec.id, isDirectory: true) }
    static func file(_ spec: ModelSpec) -> URL { folder(spec).appendingPathComponent("model.bin") }
    static func compiled(_ spec: ModelSpec) -> URL { folder(spec).appendingPathComponent("model.mlmodelc", isDirectory: true) }
    static func manifestURL(_ spec: ModelSpec) -> URL { folder(spec).appendingPathComponent("manifest.json") }

    static func manifest(_ spec: ModelSpec) -> [String: Any]? {
        guard let d = try? Data(contentsOf: manifestURL(spec)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// Installé = présent, conforme au catalogue (empreinte de l'archive) et à la taille notée à l'installation. Avant de CHARGER un modèle, `verified` recalcule l'empreinte.
    static func isInstalled(_ spec: ModelSpec) -> Bool {
        guard let want = spec.sha256, let o = manifest(spec), o["sha256"] as? String == want else { return false }
        let fm = FileManager.default
        switch spec.kind {
        case .file:
            guard fm.fileExists(atPath: file(spec).path), let size = (try? fm.attributesOfItem(atPath: file(spec).path)[.size] as? Int64), (o["size"] as? NSNumber)?.int64Value == size else { return false }
            return true
        case .coreMLArchive:
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: compiled(spec).path, isDirectory: &isDir) && isDir.boolValue && ((o["tree"] as? String)?.count == 64)
        }
    }

    /// Recalcule l'empreinte du modèle installé : à faire avant de l'utiliser (un fichier remplacé ou corrompu n'est jamais chargé).
    static func verified(_ spec: ModelSpec) -> Bool {
        guard isInstalled(spec), let want = spec.sha256, let o = manifest(spec) else { return false }
        switch spec.kind {
        case .file: return (try? hash(of: file(spec))) == want.lowercased()
        case .coreMLArchive: return (try? treeHash(of: compiled(spec))) == (o["tree"] as? String)
        }
    }

    /// Adresse acceptée : HTTPS, ou HTTP vers cette machine (essais).
    static func allowed(_ u: URL) -> Bool {
        if u.scheme == "https" { return true }
        return u.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(u.host ?? "")
    }

    static func hash(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hasher = SHA256()
        while let d = try h.read(upToCount: 1 << 20), !d.isEmpty { hasher.update(data: d) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Empreinte d'un dossier : chemins relatifs triés, tailles et contenus. Refuse tout ce qui n'est ni fichier ni dossier (liens symboliques compris).
    static func treeHash(of root: URL) throws -> String {
        let fm = FileManager.default
        var files: [String] = []
        func walk(_ rel: String) throws {
            let dir = rel.isEmpty ? root.path : root.path + "/" + rel
            for name in try fm.contentsOfDirectory(atPath: dir).sorted() {
                let r = rel.isEmpty ? name : rel + "/" + name
                switch try fm.attributesOfItem(atPath: root.path + "/" + r)[.type] as? FileAttributeType {
                case .typeDirectory: try walk(r)
                case .typeRegular: files.append(r)
                default: throw ModelRejected(errorDescription: "entry type")
                }
            }
        }
        try walk("")
        var hasher = SHA256()
        for r in files {
            let u = root.appendingPathComponent(r)
            let size = (try fm.attributesOfItem(atPath: u.path)[.size] as? UInt64) ?? 0
            hasher.update(data: Data(r.utf8)); hasher.update(data: Data([0]))
            withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
            let h = try FileHandle(forReadingFrom: u); defer { try? h.close() }
            while let d = try h.read(upToCount: 1 << 20), !d.isEmpty { hasher.update(data: d) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
