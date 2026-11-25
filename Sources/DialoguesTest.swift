// mSLICE — essai `--selftest-dialogues [<fichier>]` : sous-titres (SRT, ASS, VTT, SDH, tirets, didascalies), découpage de la parole en répliques, corrections,
// fichier de répliques, textes dans les quatre langues. Avec un fichier : extraction des sous-titres s'il y en a, transcription réelle (macOS 26), annulation.
import Foundation

@MainActor
enum DialoguesTest {
    static func run(path: String?) async -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ msg: String) { print((ok ? "OK     " : "ÉCHEC  ") + msg); if !ok { failures += 1 } }
        func texts(_ l: [DialogueLine]) -> [String] { l.map(\.text) }

        // 1. SRT : balises, entités, didascalies, noms SDH, tirets de dialogue
        let srt = """
        1
        00:00:01,000 --> 00:00:03,000
        <i>Salut</i>, ça va ?

        2
        00:00:03,500 --> 00:00:05,500
        - Oui, et toi ?
        - Pas mal.

        3
        00:00:06,000 --> 00:00:08,000
        (musique douce)

        4
        00:00:08,500 --> 00:00:10,000
        STEVE : Je te l'avais dit.

        5
        00:00:10,500 --> 00:00:12,000
        [Nancy] On y va.

        6
        00:00:12,500 --> 00:00:14,000
        [en riant] Tu plaisantes &amp; tu le sais.

        7
        00:00:14,500 --> 00:00:16,000
        ♪ la la la ♪

        8
        00:00:16,500 --> 00:00:19,000
        Une phrase longue
        sur deux lignes.
        """
        let a = Subtitles.dialogue(from: Subtitles.parse(srt))
        check(texts(a) == ["Salut, ça va ?", "Oui, et toi ?", "Pas mal.", "Je te l'avais dit.", "On y va.", "Tu plaisantes & tu le sais.", "Une phrase longue sur deux lignes."], "SRT : balises retirées, tirets séparés, didascalies et notes écartées, lignes jointes — \(texts(a))")
        check(a.first { $0.text == "Je te l'avais dit." }?.who == "Steve" && a.first { $0.text == "On y va." }?.who == "Nancy" && a.first { $0.text == "Salut, ça va ?" }?.who == nil, "SRT : noms « STEVE : » et « [Nancy] » gardés à part (« Steve », « Nancy »), « [en riant] » est une didascalie")
        if let o = a.first(where: { $0.text == "Oui, et toi ?" }), let p = a.first(where: { $0.text == "Pas mal." }) {
            check(abs(o.start - 3.5) < 1e-6 && abs(p.end - 5.5) < 1e-6 && abs(o.end - p.start) < 1e-6 && o.end > o.start && p.end > p.start, "SRT : le temps d'un sous-titre à deux répliques est réparti (\(o.end))")
        } else { check(false, "SRT : répliques à tirets introuvables") }

        // 2. ASS : colonnes, virgules dans le texte, balises {\…}, \N, acteur, dessin vectoriel
        let ass = """
        [Script Info]
        Title: x

        [V4+ Styles]
        Format: Name, Fontname

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:03.50,Default,Dustin,0,0,0,,{\\i1}Bonjour{\\i0}, mon ami\\Nça va ?
        Dialogue: 0,0:00:04.00,0:00:05.00,Default,,0,0,0,,{\\p1}m 0 0 l 10 10{\\p0}
        Dialogue: 0,0:00:06.00,0:00:07.00,Default,Default,0,0,0,,Fini.
        """
        let b = Subtitles.dialogue(from: Subtitles.parse(ass))
        check(texts(b) == ["Bonjour, mon ami ça va ?", "Fini."] && b.first?.who == "Dustin" && b.last?.who == nil && abs(b[0].start - 1) < 1e-6 && abs(b[0].end - 3.5) < 1e-6, "ASS : texte avec virgules, balises retirées, acteur « Dustin », dessin ignoré — \(texts(b))")

        // 3. WebVTT : en-tête, notes, heures facultatives, balise <v>, réglages de position
        let vtt = """
        WEBVTT

        NOTE un commentaire

        00:01.000 --> 00:03.000 align:start
        <v Steve>Allez, on y va.</v>

        1:00:05.000 --> 1:00:07.250
        Une heure plus tard.
        """
        let c = Subtitles.dialogue(from: Subtitles.parse(vtt))
        check(texts(c) == ["Allez, on y va.", "Une heure plus tard."] && c[0].who == "Steve" && abs(c[1].start - 3605) < 1e-6 && abs(c[1].end - 3607.25) < 1e-6, "VTT : balise <v>, heures facultatives, réglages ignorés — \(texts(c))")
        check(Subtitles.decode(Data([0xEF, 0xBB, 0xBF] + Array("é".utf8))) == "é" && Subtitles.decode(Data([0xE9])) == "é" && Subtitles.decode(Data([0xFF, 0xFE, 0x61, 0x00])) == "a", "encodages : UTF-8 avec BOM, Windows-1252, UTF-16")
        check(Subtitles.parse("n'importe quoi").isEmpty && Subtitles.parse("").isEmpty && Subtitles.parse("1\n00:00:05,000 --> 00:00:01,000\nà l'envers").isEmpty, "texte invalide ou plage inversée : aucune réplique, pas de plantage")

        // 4. fichiers à côté de la vidéo
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mslice-dlg-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        setenv("MSLICE_INDEX_DIR", tmp.path, 1)
        defer { try? FileManager.default.removeItem(at: tmp); unsetenv("MSLICE_INDEX_DIR") }
        let video = tmp.appendingPathComponent("Film.mkv")
        for n in ["Film.srt", "Film.fr.srt", "Film.ass", "Film.vtt", "Autre.srt", "Film.txt", "Film.mkv"] { try? Data().write(to: tmp.appendingPathComponent(n)) }
        let sib = Subtitles.siblingFiles(of: video)
        check(sib.map { $0.id } == ["fFilm.ass", "fFilm.fr.srt", "fFilm.srt", "fFilm.vtt"] && sib.first { $0.id == "fFilm.fr.srt" }?.language == "fr", "fichiers à côté : .srt, .fr.srt, .ass, .vtt trouvés, « Autre.srt » et « .txt » ignorés — \(sib.map { $0.id })")

        // 5. découpage de la parole en répliques
        func w(_ t: String, _ s: Double, _ e: Double) -> TimedWord { TimedWord(text: t, start: s, end: e) }
        let words = [w("Bonjour", 0, 0.5), w("tout", 0.5, 0.8), w("le", 0.8, 0.9), w("monde.", 0.9, 1.4),            // ponctuation
                     w("Je", 1.5, 1.7), w("suis", 1.7, 2.0), w("là", 2.0, 2.3),                                       // fin par une pause
                     w("Et", 3.2, 3.4), w("toi", 3.4, 3.8), w("?", 3.8, 3.85)]
        let u = Utterances.split(words)
        check(texts(u) == ["Bonjour tout le monde.", "Je suis là", "Et toi ?"] && abs(u[1].start - 1.5) < 1e-6 && abs(u[1].end - 2.3) < 1e-6, "découpage : ponctuation et pause de plus de 0,6 s — \(texts(u))")
        var long: [TimedWord] = []
        for i in 0 ..< 40 { long.append(w(i == 19 ? "mot," : "mot", Double(i) * 0.5, Double(i) * 0.5 + 0.45)) }          // 20 s sans ponctuation finale
        let lu = Utterances.split(long)
        check(lu.count >= 2 && lu.allSatisfy { $0.duration <= 12.01 } && lu.first!.text.hasSuffix("mot,"), "découpage : jamais plus de 12 s, coupe après la virgule — \(lu.map { Int($0.duration) })")
        check(Utterances.split([]).isEmpty && Utterances.split([w("…", 0, 1)]).isEmpty, "découpage : liste vide ou sans lettre → aucune réplique")

        // 6. corrections : texte, coupe en deux, écartée
        var set = DialogueSet(duration: 60, kind: .subtitles, detail: "essai", language: "fr")
        set.lines = [DialogueLine(start: 10, end: 14, text: "Bonjour tout le monde"), DialogueLine(start: 20, end: 22, text: "Salut")]
        let id0 = set.lines[0].id
        set.setText(id0, "  Bonjour\n\ttout le monde !  ")
        check(set.lines[0].text == "Bonjour tout le monde !" && set.lines[0].corrected, "correction : espaces et caractères de contrôle nettoyés, marquée « corrigée »")
        set.setText(id0, "   "); check(set.lines[0].text == "Bonjour tout le monde !", "correction : un texte vide est refusé")
        let second = set.split(id0, atOffset: 7)
        check(set.lines.count == 3 && set.lines[0].text == "Bonjour" && set.lines[1].text == "tout le monde !" && set.lines[1].id == second && abs(set.lines[0].end - set.lines[1].start) < 1e-9 && set.lines[0].start == 10 && set.lines[1].end == 14, "coupe en deux : temps réparti, bords conservés — \(set.lines.map { ($0.text, $0.start, $0.end) })")
        check(set.split(id0, atOffset: 0) == nil && set.split(id0, atOffset: 99) == nil && set.lines.count == 3, "coupe en deux : position invalide refusée")
        set.setDiscarded(set.lines[2].id, true)
        check(set.active.count == 2 && set.lines.count == 3, "écartée : garde la réplique, hors de la liste active")

        // 6 bis. qui parle : voix d'abord, puis seul visage, noms des sous-titres et choix manuels intouchés
        let dustin = SpeakerCandidate(id: "p0", voice: [(0, 10), (30, 40)], face: [(0, 12), (28, 42)])
        let steve = SpeakerCandidate(id: "p1", voice: [(10, 20)], face: [(9, 22)])
        let nancy = SpeakerCandidate(id: "v2", voice: [(20, 30)], face: [])
        let cast = [dustin, steve, nancy]
        check(Speakers.assign(start: 1, end: 4, candidates: cast) == "p0" && Speakers.assign(start: 11, end: 15, candidates: cast) == "p1" && Speakers.assign(start: 21, end: 25, candidates: cast) == "v2", "qui parle : la voix qui parle pendant la réplique (visage + voix liés, voix sans visage)")
        check(Speakers.assign(start: 9, end: 11, candidates: cast) == nil, "qui parle : deux voix à parts égales → pas de choix (« Qui ? »)")
        check(Speakers.assign(start: 45, end: 48, candidates: cast) == nil, "qui parle : personne ne parle ni n'est à l'écran → nil")
        let silentFace = [SpeakerCandidate(id: "p0", voice: [(0, 5)], face: [(0, 20)]), SpeakerCandidate(id: "p1", voice: [], face: [(10, 20)])]
        check(Speakers.assign(start: 12, end: 16, candidates: silentFace) == "p1", "qui parle : sans voix reconnue, le seul visage sans voix connue à l'écran")
        let facesOnly = [SpeakerCandidate(id: "p0", face: [(0, 10)]), SpeakerCandidate(id: "p1", face: [(10, 20)])]
        check(Speakers.assign(start: 1, end: 4, candidates: facesOnly) == "p0" && Speakers.assign(start: 8, end: 12, candidates: facesOnly) == nil, "qui parle : sans voix du tout, le seul visage à l'écran (deux visages → nil)")
        var sp = DialogueSet(duration: 60, kind: .subtitles, detail: "", language: "")
        sp.lines = [DialogueLine(start: 1, end: 4, text: "a"), DialogueLine(start: 11, end: 15, text: "b", who: "Hopper"), DialogueLine(start: 21, end: 25, text: "c"), DialogueLine(start: 1, end: 4, text: "d")]
        sp.setSpeaker(sp.lines[3].id, speaker: nil, name: "  Will ")
        let n = Speakers.apply(&sp, candidates: cast)
        check(n == 2 && sp.lines[0].speaker == "p0" && sp.lines[1].speaker == nil && sp.lines[1].who == "Hopper" && sp.lines[2].speaker == "v2" && sp.lines[3].who == "Will" && sp.lines[3].speaker == nil, "attribution : sous-titres et choix manuel intouchés, 2 répliques attribuées")
        sp.setSpeaker(sp.lines[0].id, speaker: "p1", name: nil)
        Speakers.apply(&sp, candidates: cast)
        check(sp.lines[0].speaker == "p1" && sp.lines[0].manual == true, "attribution : un choix manuel survit à une nouvelle attribution")

        // 7. fichier de répliques : aller-retour, refus d'un autre fichier ou d'une autre version
        let src = tmp.appendingPathComponent("Film.mkv")
        let info = MediaInfo(url: src, duration: 60, size: 0, bitrate: 0, format: "", streams: [])
        check(DialogueStore.save(set, for: info), "fichier .msdialog écrit")
        let back = DialogueStore.load(info)
        check(back?.lines == set.lines && back?.kind == .subtitles, "fichier .msdialog : aller-retour identique (corrections et écartées comprises)")
        check(DialogueStore.load(MediaInfo(url: src, duration: 90, size: 0, bitrate: 0, format: "", streams: [])) == nil, "fichier .msdialog : refusé si la durée du fichier ne correspond pas")
        try? Data("n'importe quoi".utf8).write(to: DialogueStore.url(info))
        check(DialogueStore.load(info) == nil, "fichier .msdialog : illisible → ignoré")
        DialogueStore.remove(info)

        // 8. textes
        check(L.problems().isEmpty && L.table.keys.filter { $0.hasPrefix("dlg.") }.count > 40, "textes : quatre langues complètes (\(L.table.keys.filter { $0.hasPrefix("dlg.") }.count) textes de l'onglet) \(L.problems().prefix(4))")

        // 9. fichier réel : sous-titres éventuels, puis transcription
        if let path {
            let url = URL(fileURLWithPath: path)
            guard let real = Probe.read(url) else { check(false, "fichier illisible : \(path)"); return 1 }
            let subs = Subtitles.sources(for: real)
            print("INFO   sources de sous-titres : \(subs.map(\.id))")
            for s in subs {
                let t0 = Date()
                let l = await Subtitles.load(s, info: real)
                check(l?.isEmpty == false, "sous-titres « \(s.id) » : \(l?.count ?? 0) répliques en \(String(format: "%.2f", Date().timeIntervalSince(t0))) s")
            }
            if TranscriptionSupport.available, real.audio != nil {
                let lang = DialogueModel.defaultLanguage(real)
                let state = await TranscriptionSupport.assetState(lang)
                print("INFO   langue \(lang) : \(state)")
                if state == .installed {
                    let t0 = Date()
                    let job = AnalysisJob()
                    let lines = await AnalysisRunner.runDialogues(real, language: lang, job: job) { _ in }
                    let dt = Date().timeIntervalSince(t0)
                    check((lines?.count ?? 0) >= 3, "transcription (\(lang)) : \(lines?.count ?? 0) répliques en \(String(format: "%.2f", dt)) s pour \(Fmt.time(real.duration))")
                    for l in (lines ?? []).prefix(30) { print("       \(Fmt.time(l.start)) → \(Fmt.time(l.end))  \(l.text)") }
                    check(lines?.allSatisfy { $0.end > $0.start && $0.end <= real.duration + 1 && !$0.text.isEmpty } ?? false, "transcription : plages de temps cohérentes")
                    // annulation : la tâche s'arrête vite et ne rend rien
                    let j2 = AnalysisJob()
                    let t1 = Date()
                    Task { try? await Task.sleep(nanoseconds: 150_000_000); j2.cancel() }
                    let none = await AnalysisRunner.runDialogues(real, language: lang, job: j2) { _ in }
                    check(none == nil && Date().timeIntervalSince(t1) < 6, "transcription annulée : rien rendu, arrêt en \(String(format: "%.1f", Date().timeIntervalSince(t1))) s")
                }
            } else { print("INFO   transcription non essayée (macOS < 26 ou fichier sans son)") }
        }
        print(failures == 0 ? "\nTous les essais passent." : "\n\(failures) essai(s) en échec.")
        return failures == 0 ? 0 : 1
    }
}
