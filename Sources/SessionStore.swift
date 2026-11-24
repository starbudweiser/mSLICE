// mSLICE — noyau sans interface (partagé avec l'exécutable MCP) : environnement et mémoire des morceaux de chaque fichier.
import CryptoKit
import Foundation

enum Env {
    /// Édition de développement (identifiant de paquet en « .dev ») : données et réglages séparés. Dans `mslice-mcp`, le paquet est celui de l'appli qui le contient.
    static let isDev = bundleID.hasSuffix(".dev")
    static let bundleID: String = {
        if let id = Bundle.main.bundleIdentifier, id.hasPrefix("fr.stephan.mslice") { return id }
        let plist = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")       // exécutable installé dans Contents/MacOS
        if let d = try? Data(contentsOf: plist), let o = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any], let id = o["CFBundleIdentifier"] as? String { return id }
        return "fr.stephan.mslice"
    }()
    static var supportDir: URL {
        let d = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/\(isDev ? "mSLICE DEV" : "mSLICE")", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    /// Lecture d'un réglage de l'appli (même domaine que `UserDefaults.standard` de l'appli), utilisable depuis `mslice-mcp`.
    static func pref(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, bundleID as CFString) }
}

/// Mémoire des morceaux de chaque fichier, restaurés à sa réouverture.
enum SessionStore {
    static var dir: URL {
        if let t = ProcessInfo.processInfo.environment["MSLICE_SESSION_DIR"] { try? FileManager.default.createDirectory(atPath: t, withIntermediateDirectories: true); return URL(fileURLWithPath: t, isDirectory: true) }
        let d = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/\(Env.isDev ? "mSLICE DEV" : "mSLICE")/sessions", isDirectory: true)
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

