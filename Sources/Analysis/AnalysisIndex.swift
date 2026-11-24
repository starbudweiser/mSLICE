// mSLICE — index d'analyse d'un fichier : plans, étiquettes de scène, sons. Gardé sur disque (même clé que les sessions), versionné.
//
// Format : liste de propriétés binaire contenant des blocs d'octets compacts (≈ 10 Ko par minute de vidéo). Aucune image n'est conservée.
// Si la version change (nouvelles familles, nouveau seuil de calcul), l'ancien index est ignoré et le fichier peut être réanalysé.
import Foundation

struct AnalysisIndex: Sendable {
    static let currentVersion = 1

    var version = AnalysisIndex.currentVersion
    var duration: Double
    var created = Date()
    var seconds = 0.0                      // temps de calcul
    var hasVideo = false
    var hasAudio = false

    /// Instants de coupure (début de chaque plan sauf le premier).
    var cuts: [Double] = []

    /// Images : un échantillon tous les `sceneStep` secondes ; chacun garde ses meilleures étiquettes (identifiant Vision, confiance 0…255).
    var sceneStep = 0.5
    var sceneLabels: [String] = []
    var sceneOffsets: [Int32] = [0]        // nombre d'échantillons + 1
    var sceneLabelIdx: [UInt16] = []
    var sceneConf: [UInt8] = []

    /// Sons : une fenêtre de `soundWindow` secondes tous les `soundHop` secondes.
    var soundWindow = 1.5
    var soundHop = 0.5
    var soundLabels: [String] = []
    var soundStarts: [Float] = []
    var soundOffsets: [Int32] = [0]
    var soundLabelIdx: [UInt16] = []
    var soundConf: [UInt8] = []

    var sceneSamples: Int { max(sceneOffsets.count - 1, 0) }
    var soundWindows: Int { max(soundOffsets.count - 1, 0) }
    var shotCount: Int { hasVideo ? cuts.count + 1 : 0 }

    /// Début et fin du plan qui contient `t`.
    func shot(at t: Double) -> (start: Double, end: Double) {
        var lo = 0, hi = cuts.count
        while lo < hi { let m = (lo + hi) / 2; if cuts[m] <= t { lo = m + 1 } else { hi = m } }
        return (lo > 0 ? cuts[lo - 1] : 0, lo < cuts.count ? cuts[lo] : duration)
    }
}

// MARK: Sérialisation

private func pack<T>(_ a: [T]) -> Data { a.withUnsafeBytes { Data($0) } }
private func unpack<T>(_ d: Data, as: T.Type) -> [T] {
    let n = d.count / MemoryLayout<T>.stride
    return [T](unsafeUninitializedCapacity: n) { buf, count in
        _ = d.withUnsafeBytes { raw in raw.copyBytes(to: UnsafeMutableRawBufferPointer(buf)) }
        count = n
    }
}

extension AnalysisIndex {
    private struct Stored: Codable {
        var version: Int, duration: Double, created: Date, seconds: Double, hasVideo: Bool, hasAudio: Bool
        var cuts: Data
        var sceneStep: Double, sceneLabels: [String], sceneOffsets: Data, sceneLabelIdx: Data, sceneConf: Data
        var soundWindow: Double, soundHop: Double, soundLabels: [String], soundStarts: Data, soundOffsets: Data, soundLabelIdx: Data, soundConf: Data
    }

    func serialized() -> Data? {
        let s = Stored(version: version, duration: duration, created: created, seconds: seconds, hasVideo: hasVideo, hasAudio: hasAudio, cuts: pack(cuts),
                       sceneStep: sceneStep, sceneLabels: sceneLabels, sceneOffsets: pack(sceneOffsets), sceneLabelIdx: pack(sceneLabelIdx), sceneConf: pack(sceneConf),
                       soundWindow: soundWindow, soundHop: soundHop, soundLabels: soundLabels, soundStarts: pack(soundStarts), soundOffsets: pack(soundOffsets),
                       soundLabelIdx: pack(soundLabelIdx), soundConf: pack(soundConf))
        let enc = PropertyListEncoder(); enc.outputFormat = .binary
        return try? enc.encode(s)
    }

    /// nil si le fichier est illisible, d'une autre version ou incohérent.
    init?(serialized d: Data) {
        guard let s = try? PropertyListDecoder().decode(Stored.self, from: d), s.version == AnalysisIndex.currentVersion else { return nil }
        self.init(duration: s.duration)
        version = s.version; created = s.created; seconds = s.seconds; hasVideo = s.hasVideo; hasAudio = s.hasAudio
        cuts = unpack(s.cuts, as: Double.self)
        sceneStep = s.sceneStep; sceneLabels = s.sceneLabels; sceneOffsets = unpack(s.sceneOffsets, as: Int32.self)
        sceneLabelIdx = unpack(s.sceneLabelIdx, as: UInt16.self); sceneConf = unpack(s.sceneConf, as: UInt8.self)
        soundWindow = s.soundWindow; soundHop = s.soundHop; soundLabels = s.soundLabels; soundStarts = unpack(s.soundStarts, as: Float.self)
        soundOffsets = unpack(s.soundOffsets, as: Int32.self); soundLabelIdx = unpack(s.soundLabelIdx, as: UInt16.self); soundConf = unpack(s.soundConf, as: UInt8.self)
        // cohérence : un index tronqué ou trafiqué ne doit jamais faire planter les requêtes
        guard sceneStep > 0, soundHop > 0, soundWindow > 0, sceneOffsets.first == 0, soundOffsets.first == 0,
              Int(sceneOffsets.last ?? 0) == sceneLabelIdx.count, sceneLabelIdx.count == sceneConf.count,
              Int(soundOffsets.last ?? 0) == soundLabelIdx.count, soundLabelIdx.count == soundConf.count, soundStarts.count + 1 == soundOffsets.count,
              zip(sceneOffsets, sceneOffsets.dropFirst()).allSatisfy({ $0 <= $1 }), zip(soundOffsets, soundOffsets.dropFirst()).allSatisfy({ $0 <= $1 }),
              sceneLabelIdx.allSatisfy({ Int($0) < sceneLabels.count }), soundLabelIdx.allSatisfy({ Int($0) < soundLabels.count }) else { return nil }
    }
}

// MARK: Stockage

enum AnalysisStore {
    /// `MSLICE_INDEX_DIR` redirige le dossier (essais).
    static var dir: URL {
        let d: URL
        if let t = ProcessInfo.processInfo.environment["MSLICE_INDEX_DIR"] { d = URL(fileURLWithPath: t, isDirectory: true) }
        else { d = Env.supportDir.appendingPathComponent("index", isDirectory: true) }
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ info: MediaInfo) -> URL { dir.appendingPathComponent(SessionStore.key(info) + ".msidx") }

    static func load(_ info: MediaInfo) -> AnalysisIndex? {
        guard let d = try? Data(contentsOf: url(info)), let i = AnalysisIndex(serialized: d), abs(i.duration - info.duration) < 1 else { return nil }
        return i
    }
    @discardableResult static func save(_ index: AnalysisIndex, for info: MediaInfo) -> Bool {
        guard let d = index.serialized() else { return false }
        do { try d.write(to: url(info), options: .atomic); return true } catch { return false }
    }
    static func remove(_ info: MediaInfo) { try? FileManager.default.removeItem(at: url(info)) }
}
