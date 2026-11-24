// mSLICE — index des visages d'un fichier : un enregistrement par visage reconnu (instant, boîte, empreinte), regroupés en personnages.
// Gardé sur disque à côté de l'index d'analyse (même clé, extension .msfaces), versionné, lié au modèle qui a calculé les empreintes.
//
// Format : liste de propriétés binaire contenant des blocs d'octets compacts. Les empreintes (512 valeurs normalisées) sont quantifiées sur 8 bits avec un
// facteur par visage : ≈ 0,5 Ko par visage. Aucune image n'est conservée : les vignettes des personnages sont recalculées à la demande depuis la vidéo.
// Les corrections de l'utilisateur (nom, fusion, séparation, personnage écarté) modifient seulement `group`, `names` et `hidden`.
import Foundation

struct FaceIndex: Sendable {
    static let currentVersion = 1
    static let dim = 512

    var version = FaceIndex.currentVersion
    var duration: Double
    var created = Date()
    var seconds = 0.0                      // temps de calcul
    var modelSHA = ""                      // empreinte de l'archive du modèle qui a calculé les empreintes
    var step = 1.0                         // pas d'échantillonnage des images (s)

    // un visage par entrée, triés par instant
    var t: [Float] = []                    // instant (s)
    var box: [Float] = []                  // 4 par visage : x, y, largeur, hauteur (0…1, origine en haut à gauche, image à l'endroit)
    var px: [Float] = []                   // hauteur du visage en pixels de l'image analysée (qualité)
    var track: [Int32] = []                // suivi de visage : mêmes personnes sur des images voisines d'un même plan
    var group: [Int32] = []                // personnage (≥ 0) ; -1 : pas un personnage (visage isolé)
    var emb: [Int8] = []                   // 512 par visage
    var embScale: [Float] = []             // facteur de déquantification par visage

    var names: [Int32: String] = [:]       // nom donné par l'utilisateur
    var hidden: Set<Int32> = []            // personnages écartés par l'utilisateur
    var nextGroup: Int32 = 0               // prochain identifiant libre

    var count: Int { t.count }

    /// Empreinte normalisée du visage i.
    func vector(_ i: Int) -> [Float] {
        let s = embScale[i], o = i * FaceIndex.dim
        return (0 ..< FaceIndex.dim).map { Float(emb[o + $0]) * s }
    }

    static func quantize(_ v: [Float]) -> (q: [Int8], scale: Float) {
        let m = max(v.map { abs($0) }.max() ?? 0, 1e-9)
        let s = m / 127
        return (v.map { Int8(max(-127, min(127, ($0 / s).rounded()))) }, s)
    }

    // MARK: Personnages

    struct Stats: Identifiable, Sendable {
        var id: Int32
        var faces: Int
        var seconds: Double
        var appearances: Int
        var best: Int                      // indice du plus beau visage (le plus grand), pour la vignette
    }

    /// Personnages visibles (ni écartés ni isolés), du plus présent au moins présent.
    func characters() -> [Stats] {
        var byGroup: [Int32: [Int]] = [:]
        for i in 0 ..< count where group[i] >= 0 && !hidden.contains(group[i]) { byGroup[group[i], default: []].append(i) }
        return byGroup.map { g, idx in
            let iv = intervals(of: g)
            let best = idx.max { px[$0] < px[$1] } ?? idx[0]
            return Stats(id: g, faces: idx.count, seconds: iv.reduce(0) { $0 + $1.end - $1.start }, appearances: Self.merge(iv, gap: 4).count, best: best)
        }.sorted { ($0.seconds, $1.id) > ($1.seconds, $0.id) }
    }

    /// Plages pendant lesquelles le personnage est à l'écran : chaque visage couvre un pas d'échantillonnage autour de son instant ; deux visages
    /// d'un même suivi (même plan) se rejoignent si l'écart est inférieur à 2,5 pas.
    func intervals(of g: Int32) -> [(start: Double, end: Double)] {
        let idx = (0 ..< count).filter { group[$0] == g }
        var out: [(start: Double, end: Double)] = []
        var prev: Int?
        for i in idx {
            let t0 = Double(t[i]) - step / 2, t1 = Double(t[i]) + step / 2
            if let p = prev, track[p] == track[i], Double(t[i]) - Double(t[p]) <= 2.5 * step, !out.isEmpty { out[out.count - 1].end = max(out[out.count - 1].end, t1) }
            else { out.append((max(t0, 0), min(t1, duration))) }
            prev = i
        }
        return Self.merge(out, gap: 0.0001)
    }

    static func merge(_ iv: [(start: Double, end: Double)], gap: Double) -> [(start: Double, end: Double)] {
        var out: [(start: Double, end: Double)] = []
        for x in iv.sorted(by: { $0.start < $1.start }) {
            if let l = out.last, x.start - l.end <= gap { out[out.count - 1].end = max(l.end, x.end) } else { out.append(x) }
        }
        return out
    }

    func name(of g: Int32) -> String? { names[g] }

    // MARK: Corrections de l'utilisateur

    /// Nom vide : le personnage redevient anonyme. Les noms sont nettoyés (pas de caractères de contrôle, 40 caractères au plus).
    mutating func rename(_ g: Int32, to raw: String) {
        let s = String(raw.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.map(Character.init)).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { names[g] = nil } else { names[g] = String(s.prefix(40)) }
    }

    /// Réunit `from` dans `into` : le nom de `into` est gardé, à défaut celui de `from`.
    mutating func merge(_ from: Int32, into: Int32) {
        guard from != into else { return }
        for i in 0 ..< count where group[i] == from { group[i] = into }
        if names[into] == nil, let n = names[from] { names[into] = n }
        names[from] = nil; hidden.remove(from)
    }

    mutating func hide(_ g: Int32) { hidden.insert(g) }

    /// Sépare un personnage en deux : la plus petite moitié reçoit un nouvel identifiant (rendu), nil si le personnage n'a qu'un seul suivi.
    mutating func split(_ g: Int32) -> Int32? {
        guard let moved = FaceClustering.splitInTwo(self, group: g), !moved.isEmpty else { return nil }
        let id = nextGroup; nextGroup += 1
        for i in moved { group[i] = id }
        return id
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

extension FaceIndex {
    private struct Stored: Codable {
        var version: Int, duration: Double, created: Date, seconds: Double, modelSHA: String, step: Double
        var t: Data, box: Data, px: Data, track: Data, group: Data, emb: Data, embScale: Data
        var nameKeys: Data, nameValues: [String], hidden: Data, nextGroup: Int32
    }

    func serialized() -> Data? {
        let keys = names.keys.sorted()
        let s = Stored(version: version, duration: duration, created: created, seconds: seconds, modelSHA: modelSHA, step: step,
                       t: pack(t), box: pack(box), px: pack(px), track: pack(track), group: pack(group), emb: pack(emb), embScale: pack(embScale),
                       nameKeys: pack(keys), nameValues: keys.map { names[$0] ?? "" }, hidden: pack(hidden.sorted()), nextGroup: nextGroup)
        let enc = PropertyListEncoder(); enc.outputFormat = .binary
        return try? enc.encode(s)
    }

    /// nil si le fichier est illisible, d'une autre version ou incohérent : un fichier trafiqué ne doit jamais faire planter les requêtes.
    init?(serialized d: Data) {
        guard let s = try? PropertyListDecoder().decode(Stored.self, from: d), s.version == FaceIndex.currentVersion else { return nil }
        self.init(duration: s.duration)
        version = s.version; created = s.created; seconds = s.seconds; modelSHA = s.modelSHA; step = s.step
        t = unpack(s.t, as: Float.self); box = unpack(s.box, as: Float.self); px = unpack(s.px, as: Float.self)
        track = unpack(s.track, as: Int32.self); group = unpack(s.group, as: Int32.self)
        emb = unpack(s.emb, as: Int8.self); embScale = unpack(s.embScale, as: Float.self)
        let keys = unpack(s.nameKeys, as: Int32.self)
        hidden = Set(unpack(s.hidden, as: Int32.self)); nextGroup = s.nextGroup
        guard keys.count == s.nameValues.count, keys.count <= 5000 else { return nil }
        for (k, v) in zip(keys, s.nameValues) { names[k] = v }
        let n = t.count
        guard duration.isFinite, duration >= 0, step > 0, step <= 60, n <= 200_000,
              box.count == 4 * n, px.count == n, track.count == n, group.count == n, emb.count == FaceIndex.dim * n, embScale.count == n,
              t.allSatisfy({ $0.isFinite && $0 >= -1 && Double($0) <= duration + 5 }), zip(t, t.dropFirst()).allSatisfy({ $0 <= $1 }),
              box.allSatisfy({ $0.isFinite && $0 >= -0.5 && $0 <= 1.5 }), px.allSatisfy({ $0.isFinite && $0 >= 0 }),
              embScale.allSatisfy({ $0.isFinite && $0 >= 0 }),
              nextGroup >= 0, group.allSatisfy({ $0 >= -1 && $0 < nextGroup }), names.keys.allSatisfy({ $0 >= 0 && $0 < nextGroup }),
              names.values.allSatisfy({ $0.count <= 80 && !$0.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }) else { return nil }
    }
}

// MARK: Stockage

enum FaceStore {
    static func url(_ info: MediaInfo) -> URL { AnalysisStore.dir.appendingPathComponent(SessionStore.key(info) + ".msfaces") }

    /// nil si absent, illisible, d'un autre fichier, ou calculé avec un autre modèle que celui du catalogue.
    static func load(_ info: MediaInfo) -> FaceIndex? {
        guard let d = try? Data(contentsOf: url(info)), let i = FaceIndex(serialized: d), abs(i.duration - info.duration) < 1, i.modelSHA == (ModelCatalog.characters.sha256 ?? "") else { return nil }
        return i
    }
    @discardableResult static func save(_ index: FaceIndex, for info: MediaInfo) -> Bool {
        guard let d = index.serialized() else { return false }
        do { try d.write(to: url(info), options: .atomic); return true } catch { return false }
    }
    static func remove(_ info: MediaInfo) { try? FileManager.default.removeItem(at: url(info)) }
}
