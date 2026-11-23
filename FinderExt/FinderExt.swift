// mSLICE — extension Finder : entrées « Extraire des morceaux avec mSLICE… » et « Élaguer début et fin avec mSLICE… » dans le clic droit
// sur un fichier audio ou vidéo. Elle transmet les chemins à l'appli par mslice://. Sandboxée, elle ne lit aucun fichier.
import Cocoa
import FinderSync
import UniformTypeIdentifiers

@objc(FinderExtSync)
final class FinderExtSync: FIFinderSync {
    private static let extensions: Set<String> = ["mov", "mp4", "m4v", "mkv", "avi", "webm", "mxf", "mts", "m2ts", "ts", "mpg", "mpeg", "flv", "wmv", "3gp", "ogv", "mj2", "dv",
                                                  "wav", "aif", "aiff", "mp3", "m4a", "aac", "flac", "ogg", "oga", "opus", "wma", "caf", "ac3", "eac3", "amr", "mka"]

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]      // tous les volumes
    }

    private func isMedia(_ u: URL) -> Bool {
        if FinderExtSync.extensions.contains(u.pathExtension.lowercased()) { return true }
        guard let t = UTType(filenameExtension: u.pathExtension) else { return false }
        return t.conforms(to: .audiovisualContent) || t.conforms(to: .movie) || t.conforms(to: .audio)
    }

    private func title(_ key: String) -> String {
        let lang = Locale.preferredLanguages.lazy.map { String($0.prefix(2)) }.first { ["fr", "en", "es", "it"].contains($0) } ?? "en"
        let t: [String: [String: String]] = [
            "extract": ["fr": "Extraire des morceaux avec mSLICE…", "en": "Extract pieces with mSLICE…", "es": "Extraer fragmentos con mSLICE…", "it": "Estrai parti con mSLICE…"],
            "trim": ["fr": "Élaguer début et fin avec mSLICE…", "en": "Trim start and end with mSLICE…", "es": "Recortar inicio y final con mSLICE…", "it": "Taglia inizio e fine con mSLICE…"],
        ]
        return t[key]?[lang] ?? t[key]?["en"] ?? key
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems, let items = FIFinderSyncController.default().selectedItemURLs(), !items.isEmpty, items.allSatisfy(isMedia) else { return nil }
        let m = NSMenu(title: "")
        m.addItem(NSMenuItem(title: title("extract"), action: #selector(extract(_:)), keyEquivalent: ""))
        m.addItem(NSMenuItem(title: title("trim"), action: #selector(trim(_:)), keyEquivalent: ""))
        return m
    }

    @objc func extract(_ sender: AnyObject?) { send("open") }
    @objc func trim(_ sender: AnyObject?) { send("trim") }

    private func send(_ host: String) {
        let files = FIFinderSyncController.default().selectedItemURLs() ?? []
        var c = URLComponents(); c.scheme = Bundle.main.object(forInfoDictionaryKey: "MSLICEScheme") as? String ?? "mslice"; c.host = host
        c.queryItems = files.map { URLQueryItem(name: "f", value: $0.path) }
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
}
