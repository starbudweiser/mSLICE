// mSLICE — qui parle : attribue chaque réplique à un protagoniste (étape « Protagonistes » : visage + voix) d'après la voix qui parle pendant la réplique ;
// à défaut de voix reconnue, d'après le seul visage à l'écran. Le nom donné par les sous-titres (« STEVE : ») passe avant, et un personnage choisi à la main
// n'est jamais modifié. Logique pure, sans interface : partagée avec `mslice-mcp`.
import Foundation

/// Un protagoniste vu comme des plages de temps : quand sa voix parle, quand son visage est à l'écran.
struct SpeakerCandidate: Sendable {
    var id: String                                          // « p3 » ou « v2 », comme `Protagonist.id`
    var voiceID: Int32? = nil                               // la voix du protagoniste (pour le vote par réplique, `LineVoices`)
    var voice: [(start: Double, end: Double)] = []
    var face: [(start: Double, end: Double)] = []
}

enum Speakers {
    static let minVoiceShare = 0.35, minVoiceSeconds = 0.6    // part de la réplique (ou durée) où la voix doit parler
    static let minFaceShare = 0.5                             // part de la réplique où le visage doit être à l'écran

    static func overlap(_ iv: [(start: Double, end: Double)], _ s: Double, _ e: Double) -> Double {
        iv.reduce(0) { $0 + max(min($1.end, e) - max($1.start, s), 0) }
    }

    /// Le protagoniste qui parle pendant [start, end] ; nil si on ne peut pas trancher.
    static func assign(start: Double, end: Double, candidates: [SpeakerCandidate], vote: LineVote? = nil) -> String? {
        let dur = end - start
        guard dur > 0 else { return nil }
        // 0. le vote de la réplique elle-même (empreintes calculées à l'intérieur de la réplique) quand il est net : il passe avant les fenêtres de la grille, qui débordent sur les voisines
        if let vote, vote.confident, let c = candidates.first(where: { $0.voiceID == vote.voice }) { return c.id }
        // 1. la voix qui parle le plus pendant la réplique
        let voices = candidates.filter { !$0.voice.isEmpty }.map { ($0.id, overlap($0.voice, start, end)) }.sorted { $0.1 > $1.1 }
        if let best = voices.first, best.1 / dur >= minVoiceShare || best.1 >= min(minVoiceSeconds, dur) {
            if voices.count < 2 || voices[1].1 < best.1 * 0.8 { return best.0 }
        }
        // 2. le seul visage à l'écran, parmi les personnes sans voix reconnue (un visage dont la voix se tait est un plan de réaction)
        let faces = candidates.filter { $0.voice.isEmpty && overlap($0.face, start, end) / dur >= minFaceShare }
        if faces.count == 1, voices.allSatisfy({ $0.1 / dur < minVoiceShare }) { return faces[0].id }
        // 3. sans aucune voix reconnue dans le fichier : le seul visage à l'écran
        if candidates.allSatisfy({ $0.voice.isEmpty }) {
            let seen = candidates.filter { overlap($0.face, start, end) / dur >= minFaceShare }
            if seen.count == 1 { return seen[0].id }
        }
        return nil
    }

    /// Attribue les répliques sans nom de sous-titres ni choix de l'utilisateur ; rend le nombre de répliques attribuées.
    @discardableResult static func apply(_ set: inout DialogueSet, candidates: [SpeakerCandidate], votes: [UUID: LineVote] = [:]) -> Int {
        var n = 0
        for i in set.lines.indices where set.lines[i].manual != true && set.lines[i].who == nil {
            let a = assign(start: set.lines[i].start, end: set.lines[i].end, candidates: candidates, vote: votes[set.lines[i].id])
            set.lines[i].speaker = a
            if a != nil { n += 1 }
        }
        return n
    }
}
