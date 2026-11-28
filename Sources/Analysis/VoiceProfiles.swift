// mSLICE — profils de voix et vote par réplique.
//
// Le regroupement des fenêtres (`VoiceClustering`) donne les voix ; ici on en tire un PROFIL fiable par voix (le « noyau » : fenêtres de prises de parole longues et bien
// groupées, au-dessus de la médiane de ressemblance à leur centre, empreintes CENTRÉES sur la moyenne du fichier : le centrage retire ce que toutes les voix du fichier
// ont en commun, la micro, la salle, et élargit les écarts) et on classe chaque RÉPLIQUE sur ces profils à partir d'empreintes calculées à l'intérieur de la réplique
// (`SegmentEmbedding`), donc sans le mélange avec la voix du locuteur voisin que font les fenêtres d'une grille fixe.
// Mesuré sur de vraies voix (une scène de Kaamelott, segments de 0,7 à 1,7 s recollés en alternance, profils tirés d'autres prises de parole) : grille 86 % → réplique 92 %.
import Accelerate
import Foundation

struct LineVote: Sendable, Equatable {
    var voice: Int32
    var sim: Float                         // ressemblance (centrée) au profil de la voix
    var margin: Float                      // avance sur la deuxième voix
    /// Assez net pour décider seul : franche ressemblance, ou ressemblance moyenne avec une bonne avance.
    var confident: Bool { (sim >= 0.25 && margin >= 0.10) || (sim >= 0.40 && margin >= 0.05) }
}

struct VoiceProfiles: Sendable {
    var mu: [Float]                        // moyenne des fenêtres attribuées à une voix visible
    var ids: [Int32]
    var proto: [[Float]]                   // un profil normalisé par voix

    static let minRun = 6                  // fenêtres consécutives (1,5 s) pour compter dans le noyau

    private static func unit(_ v: [Float]) -> [Float] {
        var n: Float = 0; vDSP_svesq(v, 1, &n, vDSP_Length(v.count)); n = max(n.squareRoot(), 1e-9)
        return v.map { $0 / n }
    }
    private static func dot(_ a: [Float], _ b: [Float]) -> Float { var d: Float = 0; vDSP_dotpr(a, 1, b, 1, &d, vDSP_Length(a.count)); return d }

    /// nil sans voix visible.
    static func build(_ v: VoiceIndex) -> VoiceProfiles? {
        let dim = VoiceIndex.dim
        var by: [Int32: [Int]] = [:]
        for i in 0 ..< v.count where v.group[i] >= 0 && !v.hidden.contains(v.group[i]) { by[v.group[i], default: []].append(i) }
        guard !by.isEmpty else { return nil }
        var mu = [Float](repeating: 0, count: dim), n: Float = 0
        for (_, idx) in by { for i in idx { vDSP_vadd(mu, 1, v.vector(i), 1, &mu, 1, vDSP_Length(dim)); n += 1 } }
        mu = mu.map { $0 / max(n, 1) }
        var ids: [Int32] = [], proto: [[Float]] = []
        for g in by.keys.sorted() {
            let idx = by[g]!
            let z = idx.map { i -> [Float] in var d = [Float](repeating: 0, count: dim); vDSP_vsub(mu, 1, v.vector(i), 1, &d, 1, vDSP_Length(dim)); return unit(d) }
            var centre = [Float](repeating: 0, count: dim)
            for e in z { vDSP_vadd(centre, 1, e, 1, &centre, 1, vDSP_Length(dim)) }
            centre = unit(centre)
            let sims = z.map { dot($0, centre) }
            let sorted = sims.sorted(), median = sorted[sorted.count / 2]
            // appartenir à une plage de fenêtres consécutives d'au moins `minRun`
            var inRun = [Bool](repeating: false, count: idx.count)
            var s = 0
            for k in 1 ... idx.count {
                if k == idx.count || idx[k] != idx[k - 1] + 1 {
                    if k - s >= minRun { for q in s ..< k { inRun[q] = true } }
                    s = k
                }
            }
            var keep = (0 ..< idx.count).filter { inRun[$0] && sims[$0] >= median }
            if keep.count < minRun { keep = (0 ..< idx.count).filter { inRun[$0] } }
            if keep.count < minRun { keep = Array(0 ..< idx.count) }
            var p = [Float](repeating: 0, count: dim)
            for k in keep { vDSP_vadd(p, 1, z[k], 1, &p, 1, vDSP_Length(dim)) }
            ids.append(g); proto.append(unit(p))
        }
        return VoiceProfiles(mu: mu, ids: ids, proto: proto)
    }

    /// Affinage des groupes de fenêtres sur les profils (k-moyennes en similarité centrée, quelques tours) : une fenêtre passe à la voix dont le profil la prend nettement mieux que le sien
    /// (au moins 0,25 de ressemblance et 0,10 d'avance), une fenêtre laissée sans voix (chevauchement, changement de locuteur) est rattachée seulement si c'est très net (0,40 et 0,15).
    /// Les profils sont refaits à chaque tour avec le noyau de chaque voix, donc les fenêtres d'une autre personne tombées dans une voix lâche retrouvent la leur.
    static func refine(_ v: VoiceIndex, rounds: Int = 4) -> [Int32] {
        var cur = v
        let dim = VoiceIndex.dim
        for _ in 0 ..< rounds {
            guard let p = build(cur), p.ids.count > 1 else { break }
            var changed = 0
            var next = cur.group
            for i in 0 ..< cur.count {
                var d = [Float](repeating: 0, count: dim); vDSP_vsub(p.mu, 1, cur.vector(i), 1, &d, 1, vDSP_Length(dim))
                let u = unit(d)
                var best = -2 as Float, second = -2 as Float, bi = 0, own: Float = -2
                for (k, q) in p.proto.enumerated() {
                    let s = dot(u, q)
                    if p.ids[k] == cur.group[i] { own = s }
                    if s > best { second = best; best = s; bi = k } else if s > second { second = s }
                }
                let g = cur.group[i]
                if g >= 0, p.ids[bi] != g, !cur.hidden.contains(g), best >= 0.25, best - own >= 0.10 { next[i] = p.ids[bi]; changed += 1 }
                else if g < 0, best >= 0.40, best - second >= 0.15 { next[i] = p.ids[bi]; changed += 1 }
            }
            cur.group = next
            if changed == 0 { break }
        }
        return cur.group
    }

    /// La voix qui ressemble le plus à une réplique (moyenne de ses empreintes), avec son avance sur la suivante.
    func classify(_ vectors: [[Float]]) -> LineVote? {
        guard !vectors.isEmpty, !ids.isEmpty else { return nil }
        let dim = mu.count
        var sum = [Float](repeating: 0, count: dim)
        for e in vectors {
            var d = [Float](repeating: 0, count: dim); vDSP_vsub(mu, 1, e, 1, &d, 1, vDSP_Length(dim))
            let u = Self.unit(d); vDSP_vadd(sum, 1, u, 1, &sum, 1, vDSP_Length(dim))
        }
        let q = Self.unit(sum)
        var best = -2 as Float, second = -2 as Float, bi = 0
        for (i, p) in proto.enumerated() {
            let s = Self.dot(q, p)
            if s > best { second = best; best = s; bi = i } else if s > second { second = s }
        }
        return LineVote(voice: ids[bi], sim: best, margin: ids.count > 1 ? best - second : best)
    }
}

enum LineVoices {
    /// Un vote par réplique (clé : identifiant de la réplique) ; vide si le modèle de voix ou le son manque. Lit la piste « voix seules » si elle existe, sinon l'original.
    static func votes(_ lines: [DialogueLine], info: MediaInfo, voices: VoiceIndex, job: AnalysisJob = AnalysisJob()) async -> [UUID: LineVote] {
        guard !lines.isEmpty, let profiles = VoiceProfiles.build(voices), let embedder = VoiceEmbedder() else { return [:] }
        let url = CleanVoice.exists(info) ? CleanVoice.url(info) : await Analyzer.source(info)
        let ranges = lines.map { (start: $0.start, end: $0.end) }
        let found: [[(t: Double, v: [Float])]]? = await onThread { SegmentEmbedding.embedRanges(url: url, ranges: ranges, embedder: embedder, job: job) }
        guard let found else { return [:] }
        var out: [UUID: LineVote] = [:]
        for (i, l) in lines.enumerated() { if let v = profiles.classify(found[i].map(\.v)) { out[l.id] = v } }
        return out
    }
}
