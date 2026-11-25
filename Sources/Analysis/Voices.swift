// mSLICE — index des voix d'un fichier : une empreinte (CAM++, 512 valeurs) par fenêtre de parole de 1,515 s, toutes les 0,75 s, regroupées en voix.
// Gardé sur disque à côté de l'index d'analyse (même clé, extension .msvoices), versionné, lié au modèle qui a calculé les empreintes. Aucun son n'est conservé.
//
// Les corrections de l'utilisateur (nom, fusion, voix écartée, voix liée à un visage) modifient seulement `group`, `names`, `hidden` et `link`.
import Accelerate
import Foundation

struct VoiceIndex: Sendable {
    static let currentVersion = 1
    static let dim = 512
    static let window = Double(VoiceFeatures.windowSamples) / VoiceFeatures.rate        // 1,515 s
    static let hop = 0.75

    var version = VoiceIndex.currentVersion
    var duration: Double
    var created = Date()
    var seconds = 0.0
    var modelSHA = ""

    var t: [Float] = []                    // début de chaque fenêtre (s)
    var emb: [Int8] = []                   // 512 par fenêtre
    var embScale: [Float] = []
    var group: [Int32] = []                // voix (≥ 0) ; -1 : trop peu de parole pour être une voix
    var names: [Int32: String] = [:]
    var hidden: Set<Int32> = []
    var link: [Int32: Int32] = [:]         // voix → personnage (groupe de visages) ; automatique, corrigeable
    var nextGroup: Int32 = 0

    var count: Int { t.count }

    func vector(_ i: Int) -> [Float] {
        let s = embScale[i], o = i * VoiceIndex.dim
        return (0 ..< VoiceIndex.dim).map { Float(emb[o + $0]) * s }
    }
    static func quantize(_ v: [Float]) -> (q: [Int8], scale: Float) { FaceIndex.quantize(v) }

    // MARK: Voix

    struct Stats: Identifiable, Sendable {
        var id: Int32
        var windows: Int
        var seconds: Double
        var turns: Int                     // prises de parole (plages séparées de plus de 2 s)
        var sample: Double                 // début d'un bon extrait à écouter
    }

    /// Voix visibles (ni écartées ni isolées), de la plus présente à la moins présente.
    func voices() -> [Stats] {
        var by: [Int32: [Int]] = [:]
        for i in 0 ..< count where group[i] >= 0 && !hidden.contains(group[i]) { by[group[i], default: []].append(i) }
        return by.map { g, idx in
            let iv = intervals(of: g)
            return Stats(id: g, windows: idx.count, seconds: iv.reduce(0) { $0 + $1.end - $1.start }, turns: FaceIndex.merge(iv, gap: 2).count, sample: sampleStart(idx))
        }.sorted { ($0.seconds, $1.id) > ($1.seconds, $0.id) }
    }

    /// Un extrait représentatif : la fenêtre la plus proche du centre de la voix, dont les voisines sont de la même voix.
    private func sampleStart(_ idx: [Int]) -> Double {
        var sum = [Float](repeating: 0, count: VoiceIndex.dim)
        for i in idx { vDSP_vadd(sum, 1, vector(i), 1, &sum, 1, vDSP_Length(VoiceIndex.dim)) }
        var best = idx[0], bs: Float = -2
        for i in idx {
            var d: Float = 0; vDSP_dotpr(sum, 1, vector(i), 1, &d, vDSP_Length(VoiceIndex.dim))
            let neighbours = idx.filter { abs(t[$0] - t[i]) < 2.5 }.count
            let s = d / Float(idx.count) + 0.02 * Float(neighbours)
            if s > bs { bs = s; best = i }
        }
        return Double(t[best])
    }

    /// Plages pendant lesquelles la voix parle : chaque fenêtre « possède » le pas de 0,75 s autour de son centre ; les fenêtres voisines se rejoignent.
    func intervals(of g: Int32) -> [(start: Double, end: Double)] {
        var out: [(start: Double, end: Double)] = []
        for i in 0 ..< count where group[i] == g {
            let c = Double(t[i]) + VoiceIndex.window / 2
            out.append((max(c - VoiceIndex.hop / 2, 0), min(c + VoiceIndex.hop / 2, duration)))
        }
        return FaceIndex.merge(out, gap: 0.2)
    }

    func name(of g: Int32) -> String? { names[g] }

    // MARK: Corrections de l'utilisateur

    mutating func rename(_ g: Int32, to raw: String) {
        let s = String(raw.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.map(Character.init)).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { names[g] = nil } else { names[g] = String(s.prefix(40)) }
    }
    mutating func merge(_ from: Int32, into: Int32) {
        guard from != into else { return }
        for i in 0 ..< count where group[i] == from { group[i] = into }
        if names[into] == nil, let n = names[from] { names[into] = n }
        if link[into] == nil, let l = link[from] { link[into] = l }
        names[from] = nil; hidden.remove(from); link[from] = nil
    }
    mutating func hide(_ g: Int32) { hidden.insert(g) }
    mutating func setLink(_ g: Int32, to person: Int32?) { link[g] = person }
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

extension VoiceIndex {
    private struct Stored: Codable {
        var version: Int, duration: Double, created: Date, seconds: Double, modelSHA: String
        var t: Data, emb: Data, embScale: Data, group: Data
        var nameKeys: Data, nameValues: [String], hidden: Data, linkKeys: Data, linkValues: Data, nextGroup: Int32
    }

    func serialized() -> Data? {
        let keys = names.keys.sorted(), lk = link.keys.sorted()
        let s = Stored(version: version, duration: duration, created: created, seconds: seconds, modelSHA: modelSHA,
                       t: pack(t), emb: pack(emb), embScale: pack(embScale), group: pack(group),
                       nameKeys: pack(keys), nameValues: keys.map { names[$0] ?? "" }, hidden: pack(hidden.sorted()),
                       linkKeys: pack(lk), linkValues: pack(lk.map { link[$0] ?? -1 }), nextGroup: nextGroup)
        let enc = PropertyListEncoder(); enc.outputFormat = .binary
        return try? enc.encode(s)
    }

    /// nil si le fichier est illisible, d'une autre version ou incohérent.
    init?(serialized d: Data) {
        guard let s = try? PropertyListDecoder().decode(Stored.self, from: d), s.version == VoiceIndex.currentVersion else { return nil }
        self.init(duration: s.duration)
        version = s.version; created = s.created; seconds = s.seconds; modelSHA = s.modelSHA
        t = unpack(s.t, as: Float.self); emb = unpack(s.emb, as: Int8.self); embScale = unpack(s.embScale, as: Float.self); group = unpack(s.group, as: Int32.self)
        let keys = unpack(s.nameKeys, as: Int32.self), lk = unpack(s.linkKeys, as: Int32.self), lv = unpack(s.linkValues, as: Int32.self)
        hidden = Set(unpack(s.hidden, as: Int32.self)); nextGroup = s.nextGroup
        guard keys.count == s.nameValues.count, keys.count <= 5000, lk.count == lv.count, lk.count <= 5000 else { return nil }
        for (k, v) in zip(keys, s.nameValues) { names[k] = v }
        for (k, v) in zip(lk, lv) where v >= 0 { link[k] = v }
        let n = t.count
        guard duration.isFinite, duration >= 0, n <= 200_000,
              emb.count == VoiceIndex.dim * n, embScale.count == n, group.count == n,
              t.allSatisfy({ $0.isFinite && $0 >= -1 && Double($0) <= duration + 5 }), zip(t, t.dropFirst()).allSatisfy({ $0 <= $1 }),
              embScale.allSatisfy({ $0.isFinite && $0 >= 0 }),
              nextGroup >= 0, group.allSatisfy({ $0 >= -1 && $0 < nextGroup }), names.keys.allSatisfy({ $0 >= 0 && $0 < nextGroup }),
              names.values.allSatisfy({ $0.count <= 80 && !$0.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }) else { return nil }
    }
}

// MARK: Stockage

enum VoiceStore {
    static func url(_ info: MediaInfo) -> URL { AnalysisStore.dir.appendingPathComponent(SessionStore.key(info) + ".msvoices") }

    /// nil si absent, illisible, d'un autre fichier, ou calculé avec un autre modèle que celui du catalogue.
    static func load(_ info: MediaInfo) -> VoiceIndex? {
        guard let d = try? Data(contentsOf: url(info)), let i = VoiceIndex(serialized: d), abs(i.duration - info.duration) < 1, i.modelSHA == (ModelCatalog.voices.sha256 ?? "") else { return nil }
        return i
    }
    @discardableResult static func save(_ index: VoiceIndex, for info: MediaInfo) -> Bool {
        guard let d = index.serialized() else { return false }
        do { try d.write(to: url(info), options: .atomic); return true } catch { return false }
    }
    static func remove(_ info: MediaInfo) { try? FileManager.default.removeItem(at: url(info)) }
}

// MARK: Regroupement

/// Des fenêtres aux voix : les fenêtres voisines qui se ressemblent forment des blocs (une prise de parole d'une même personne), puis liaison moyenne
/// (UPGMA) entre blocs. Réglages mesurés à l'essai (CAM++ : similarité moyenne 0,45 pour une même voix, 0,16 à 0,18 pour des voix différentes) ;
/// une voix doit totaliser au moins `minSeconds` de parole.
enum VoiceClustering {
    static let blockSimilarity: Float = 0.45         // deux fenêtres voisines sont du même bloc au-dessus de cette ressemblance (moyenne du bloc)
    static let linkSimilarity: Float = 0.30
    static let minSeconds = 4.0
    static let maxBlocks = 3000

    private struct Block { var windows: [Int]; var sum: [Float]; var alive = true }

    static func cluster(_ v: VoiceIndex, threshold: Float = linkSimilarity) -> [Int32] {
        let n = v.count, dim = VoiceIndex.dim
        guard n > 0 else { return [] }
        var blocks: [Block] = []
        for i in 0 ..< n {
            let e = v.vector(i)
            if var b = blocks.last, Double(v.t[i] - v.t[b.windows.last!]) <= VoiceIndex.hop * 1.5 {
                var d: Float = 0; vDSP_dotpr(b.sum, 1, e, 1, &d, vDSP_Length(dim))
                if d / Float(b.windows.count) >= blockSimilarity {
                    b.windows.append(i); vDSP_vadd(b.sum, 1, e, 1, &b.sum, 1, vDSP_Length(dim)); blocks[blocks.count - 1] = b; continue
                }
            }
            blocks.append(Block(windows: [i], sum: e))
        }
        var rest: [Block] = []
        if blocks.count > maxBlocks { blocks.sort { $0.windows.count > $1.windows.count }; rest = Array(blocks[maxBlocks...]); blocks = Array(blocks[..<maxBlocks]) }
        link(&blocks, threshold: threshold)
        for r in rest {
            var best: Float = -2, bi = -1
            for (i, k) in blocks.enumerated() where k.alive {
                var d: Float = 0; vDSP_dotpr(k.sum, 1, r.sum, 1, &d, vDSP_Length(dim))
                let s = d / (Float(k.windows.count) * Float(r.windows.count)); if s > best { best = s; bi = i }
            }
            if bi >= 0, best >= threshold { blocks[bi].windows += r.windows; vDSP_vadd(blocks[bi].sum, 1, r.sum, 1, &blocks[bi].sum, 1, vDSP_Length(dim)) }
        }
        var group = [Int32](repeating: -1, count: n)
        var next: Int32 = 0
        let need = Int((minSeconds / VoiceIndex.hop).rounded(.up))
        for b in blocks.filter({ $0.alive && $0.windows.count >= need }).sorted(by: { ($0.windows.count, $1.windows[0]) > ($1.windows.count, $0.windows[0]) }) {
            for i in b.windows { group[i] = next }
            next += 1
        }
        return group
    }

    private static func link(_ cl: inout [Block], threshold: Float) {
        let c = cl.count, dim = VoiceIndex.dim
        guard c > 1 else { return }
        var m = [Float](repeating: -2, count: c * c)
        var sums = [Float](repeating: 0, count: c * dim)
        for (i, k) in cl.enumerated() { sums.replaceSubrange(i * dim ..< (i + 1) * dim, with: k.sum) }
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(c), Int32(c), Int32(dim), 1, sums, Int32(dim), sums, Int32(dim), 0, &m, Int32(c))
        for i in 0 ..< c { for j in 0 ..< c { m[i * c + j] = i == j ? -2 : m[i * c + j] / Float(cl[i].windows.count * cl[j].windows.count) } }
        var nn = [Int](repeating: -1, count: c), nnS = [Float](repeating: -2, count: c)
        func rescan(_ i: Int) {
            var best: Float = -2, bj = -1
            for j in 0 ..< c where cl[j].alive && j != i { let s = m[i * c + j]; if s > best { best = s; bj = j } }
            nn[i] = bj; nnS[i] = best
        }
        for i in 0 ..< c { rescan(i) }
        while true {
            var bi = -1; var bs: Float = -2
            for i in 0 ..< c where cl[i].alive && nnS[i] > bs { bs = nnS[i]; bi = i }
            guard bi >= 0, bs >= threshold else { break }
            let a = bi, b = nn[bi]
            let na = Float(cl[a].windows.count), nb = Float(cl[b].windows.count)
            cl[a].windows += cl[b].windows
            vDSP_vadd(cl[a].sum, 1, cl[b].sum, 1, &cl[a].sum, 1, vDSP_Length(dim))
            cl[b].alive = false
            for k in 0 ..< c where cl[k].alive && k != a {
                let s = (na * m[a * c + k] + nb * m[b * c + k]) / (na + nb)
                m[a * c + k] = s; m[k * c + a] = s
            }
            rescan(a)
            for k in 0 ..< c where cl[k].alive && k != a && (nn[k] == a || nn[k] == b) { rescan(k) }
        }
    }
}
