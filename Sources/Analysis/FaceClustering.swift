// mSLICE — des visages aux personnages : suivis de visage, puis regroupement par liaison moyenne sur les empreintes.
//
// Réglages mesurés à l'essai des modèles (ETAT.md § 9, AuraFace 8 bits sur 1 840 visages) : liaison moyenne à la distance 0,70 (similarité 0,30) →
// 99,8 % de précision, 86,7 % de rappel sur les visages nets. Deux contraintes : jamais deux visages d'une même image dans un même personnage
// (personnes forcément différentes), et les visages d'un même suivi sont réunis avant le regroupement (ils sont presque identiques : 0,85 de similarité).
// Fusion manuelle dans le panneau : réunir est facile, séparer ne l'est pas, d'où une coupure plutôt stricte.
import Accelerate
import Foundation

enum FaceClustering {
    static let linkSimilarity: Float = 0.30          // liaison moyenne à la distance 0,70
    static let trackIoU: Float = 0.12                // recouvrement minimal de deux boîtes pour un même suivi
    static let trackSimilarity: Float = 0.25         // et similarité minimale de leurs empreintes (garde-fou contre une permutation)
    static let minFaces = 4                          // un personnage apparaît sur au moins 4 images échantillonnées
    static let maxClusters = 3000                    // plafond de la matrice de similarités (36 Mo)

    // MARK: Suivis

    /// Identifiant de suivi par visage : deux visages d'images voisines (écart ≤ 1,6 pas), sans coupure entre elles, dont les boîtes se recouvrent
    /// et dont les empreintes se ressemblent, sont le même suivi (un visage ne prolonge qu'un suivi, et réciproquement).
    static func tracks(_ f: FaceIndex, cuts: [Double]) -> [Int32] {
        let n = f.count
        var track = [Int32](repeating: -1, count: n)
        var next: Int32 = 0
        // images : suites de visages de même instant
        var frames: [Range<Int>] = []
        var s = 0
        for i in 1 ... max(n, 1) where n > 0 { if i == n || f.t[i] != f.t[s] { frames.append(s ..< i); s = i } }
        func hasCut(_ a: Double, _ b: Double) -> Bool {
            var lo = 0, hi = cuts.count
            while lo < hi { let m = (lo + hi) / 2; if cuts[m] <= a { lo = m + 1 } else { hi = m } }
            return lo < cuts.count && cuts[lo] <= b
        }
        for (k, fr) in frames.enumerated() {
            if k > 0 {
                let prev = frames[k - 1]
                let gap = Double(f.t[fr.lowerBound] - f.t[prev.lowerBound])
                if gap <= 1.6 * f.step, !hasCut(Double(f.t[prev.lowerBound]), Double(f.t[fr.lowerBound])) {
                    var pairs: [(iou: Float, a: Int, b: Int)] = []
                    for a in prev { for b in fr {
                        let iou = Self.iou(f, a, b)
                        if iou >= trackIoU, Self.dot(f, a, b) >= trackSimilarity { pairs.append((iou, a, b)) }
                    } }
                    var usedA = Set<Int>(), usedB = Set<Int>()
                    for p in pairs.sorted(by: { $0.iou > $1.iou }) where !usedA.contains(p.a) && !usedB.contains(p.b) {
                        usedA.insert(p.a); usedB.insert(p.b); track[p.b] = track[p.a]
                    }
                }
            }
            for i in fr where track[i] < 0 { track[i] = next; next += 1 }
        }
        return track
    }

    private static func iou(_ f: FaceIndex, _ a: Int, _ b: Int) -> Float {
        let (ax, ay, aw, ah) = (f.box[4 * a], f.box[4 * a + 1], f.box[4 * a + 2], f.box[4 * a + 3])
        let (bx, by, bw, bh) = (f.box[4 * b], f.box[4 * b + 1], f.box[4 * b + 2], f.box[4 * b + 3])
        let ix = max(0, min(ax + aw, bx + bw) - max(ax, bx)), iy = max(0, min(ay + ah, by + bh) - max(ay, by))
        let inter = ix * iy, union = aw * ah + bw * bh - inter
        return union > 0 ? inter / union : 0
    }

    private static func dot(_ f: FaceIndex, _ a: Int, _ b: Int) -> Float {
        var s: Int32 = 0
        let oa = a * FaceIndex.dim, ob = b * FaceIndex.dim
        for k in 0 ..< FaceIndex.dim { s += Int32(f.emb[oa + k]) * Int32(f.emb[ob + k]) }
        return Float(s) * f.embScale[a] * f.embScale[b]
    }

    // MARK: Regroupement

    private struct Cluster {
        var faces: [Int]
        var sum: [Float]
        var frames: Set<Int32>
        var alive = true
    }

    private static func frameKey(_ f: FaceIndex, _ i: Int) -> Int32 { Int32((Double(f.t[i]) * 1000).rounded()) }

    private static func makeClusters(_ f: FaceIndex, faces: [Int]) -> [Cluster] {
        var byTrack: [Int32: [Int]] = [:], order: [Int32] = []
        for i in faces { if byTrack[f.track[i]] == nil { order.append(f.track[i]) }; byTrack[f.track[i], default: []].append(i) }
        return order.map { tr in
            let idx = byTrack[tr]!
            var sum = [Float](repeating: 0, count: FaceIndex.dim)
            for i in idx { let v = f.vector(i); vDSP_vadd(sum, 1, v, 1, &sum, 1, vDSP_Length(FaceIndex.dim)) }
            return Cluster(faces: idx, sum: sum, frames: Set(idx.map { frameKey(f, $0) }))
        }
    }

    /// Liaison moyenne (UPGMA) : la similarité de deux groupes est la moyenne des similarités de leurs visages, soit le produit de leurs sommes
    /// d'empreintes divisé par leurs effectifs. S'arrête sous `threshold` ou quand il reste `until` groupes ; ne réunit jamais deux groupes qui
    /// partagent une image.
    private static func link(_ cl: inout [Cluster], threshold: Float, until: Int = 1) {
        let c = cl.count
        guard c > 1 else { return }
        var m = [Float](repeating: -2, count: c * c)
        var sums = [Float](repeating: 0, count: c * FaceIndex.dim)
        for (i, k) in cl.enumerated() { sums.replaceSubrange(i * FaceIndex.dim ..< (i + 1) * FaceIndex.dim, with: k.sum) }
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(c), Int32(c), Int32(FaceIndex.dim), 1, sums, Int32(FaceIndex.dim), sums, Int32(FaceIndex.dim), 0, &m, Int32(c))
        for i in 0 ..< c { for j in 0 ..< c {
            if i == j || !cl[i].frames.isDisjoint(with: cl[j].frames) { m[i * c + j] = -2 }
            else { m[i * c + j] /= Float(cl[i].faces.count * cl[j].faces.count) }
        } }
        var nn = [Int](repeating: -1, count: c), nnS = [Float](repeating: -2, count: c)
        func rescan(_ i: Int) {
            var best: Float = -2, bj = -1
            let row = i * c
            for j in 0 ..< c where cl[j].alive && j != i { let s = m[row + j]; if s > best { best = s; bj = j } }
            nn[i] = bj; nnS[i] = best
        }
        for i in 0 ..< c { rescan(i) }
        var alive = c
        while alive > until {
            var bi = -1; var bs: Float = -2
            for i in 0 ..< c where cl[i].alive && nnS[i] > bs { bs = nnS[i]; bi = i }
            guard bi >= 0, bs >= threshold, bs > -1.5 else { break }
            let a = bi, b = nn[bi]
            let na = Float(cl[a].faces.count), nb = Float(cl[b].faces.count)
            cl[a].faces += cl[b].faces
            vDSP_vadd(cl[a].sum, 1, cl[b].sum, 1, &cl[a].sum, 1, vDSP_Length(FaceIndex.dim))
            cl[a].frames.formUnion(cl[b].frames)
            cl[b].alive = false; alive -= 1
            for k in 0 ..< c where cl[k].alive && k != a {
                let s: Float = (m[a * c + k] <= -1.5 || m[b * c + k] <= -1.5) ? -2 : (na * m[a * c + k] + nb * m[b * c + k]) / (na + nb)
                m[a * c + k] = s; m[k * c + a] = s
            }
            rescan(a)
            for k in 0 ..< c where cl[k].alive && k != a && (nn[k] == a || nn[k] == b) { rescan(k) }
        }
    }

    /// Un groupe par visage, numérotés du plus grand au plus petit ; -1 pour les visages qui n'ont pas assez d'apparitions pour être un personnage.
    static func cluster(_ f: FaceIndex, threshold: Float = linkSimilarity) -> [Int32] {
        let n = f.count
        guard n > 0 else { return [] }
        var cl = makeClusters(f, faces: Array(0 ..< n))
        var rest: [Cluster] = []
        if cl.count > maxClusters {                                    // trop de suivis pour la matrice : les plus gros d'abord, les autres rattachés ensuite
            cl.sort { $0.faces.count > $1.faces.count }
            rest = Array(cl[maxClusters...]); cl = Array(cl[..<maxClusters])
        }
        link(&cl, threshold: threshold)
        for r in rest {
            var best: Float = -2, bi = -1
            let rn = Float(r.faces.count)
            for (i, k) in cl.enumerated() where k.alive && k.frames.isDisjoint(with: r.frames) {
                var d: Float = 0; vDSP_dotpr(k.sum, 1, r.sum, 1, &d, vDSP_Length(FaceIndex.dim))
                let s = d / (Float(k.faces.count) * rn); if s > best { best = s; bi = i }
            }
            if bi >= 0, best >= threshold { cl[bi].faces += r.faces; vDSP_vadd(cl[bi].sum, 1, r.sum, 1, &cl[bi].sum, 1, vDSP_Length(FaceIndex.dim)); cl[bi].frames.formUnion(r.frames) }
        }
        var group = [Int32](repeating: -1, count: n)
        var next: Int32 = 0
        for k in cl.filter({ $0.alive && $0.faces.count >= minFaces }).sorted(by: { ($0.faces.count, $1.faces[0]) > ($1.faces.count, $0.faces[0]) }) {
            for i in k.faces { group[i] = next }
            next += 1
        }
        return group
    }

    /// Paires de personnages qui se ressemblent assez pour être la même personne (liaison moyenne entre leurs visages) sans jamais être à l'écran en même temps :
    /// le regroupement automatique reste strict, l'utilisateur confirme. Mesuré sur une vidéo de 1 min : deux personnes coupées en deux groupes remontent
    /// avec 0,23 et 0,29, des personnes différentes restent sous 0,20.
    static func suggestions(_ f: FaceIndex, minSimilarity: Float = 0.21, limit: Int = 4) -> [(a: Int32, b: Int32, similarity: Float)] {
        var by: [Int32: [Int]] = [:]
        for i in 0 ..< f.count where f.group[i] >= 0 && !f.hidden.contains(f.group[i]) { by[f.group[i], default: []].append(i) }
        let ids = by.keys.sorted()
        guard ids.count > 1, ids.count <= 400 else { return [] }
        var sums: [Int32: [Float]] = [:], frames: [Int32: Set<Int32>] = [:]
        for g in ids {
            var sum = [Float](repeating: 0, count: FaceIndex.dim)
            for i in by[g]! { let v = f.vector(i); vDSP_vadd(sum, 1, v, 1, &sum, 1, vDSP_Length(FaceIndex.dim)) }
            sums[g] = sum; frames[g] = Set(by[g]!.map { frameKey(f, $0) })
        }
        var out: [(a: Int32, b: Int32, similarity: Float)] = []
        for (n, a) in ids.enumerated() { for b in ids[(n + 1)...] where frames[a]!.isDisjoint(with: frames[b]!) {
            var d: Float = 0; vDSP_dotpr(sums[a]!, 1, sums[b]!, 1, &d, vDSP_Length(FaceIndex.dim))
            let s = d / (Float(by[a]!.count) * Float(by[b]!.count))
            if s >= minSimilarity { out.append((a, b, s)) }
        } }
        return Array(out.sorted { $0.similarity > $1.similarity }.prefix(limit))
    }

    /// Visages à déplacer pour séparer un personnage en deux (la plus petite moitié) ; nil s'il n'a qu'un seul suivi ou si deux groupes ne se dégagent pas.
    static func splitInTwo(_ f: FaceIndex, group g: Int32) -> [Int]? {
        let faces = (0 ..< f.count).filter { f.group[$0] == g }
        var cl = makeClusters(f, faces: faces)
        guard cl.count >= 2, cl.count <= maxClusters else { return nil }
        link(&cl, threshold: -1, until: 2)
        let alive = cl.filter(\.alive)
        guard alive.count == 2 else { return nil }
        return alive.min { $0.faces.count < $1.faces.count }?.faces.sorted()
    }
}
