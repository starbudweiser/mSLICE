import AppKit

// `mSLICE --check-l10n` : vérifie que chaque texte existe dans les quatre langues.
if CommandLine.arguments.contains("--check-l10n") {
    let problems = L.problems()
    if problems.isEmpty { print("OK : \(L.table.count) textes × 4 langues"); exit(0) }
    print("Textes incomplets : \(problems.joined(separator: ", "))"); exit(1)
}
// `mSLICE --selftest <fichier>` : essais du moteur d'export sans fenêtre.
if let i = CommandLine.arguments.firstIndex(of: "--selftest"), CommandLine.arguments.indices.contains(i + 1) {
    let path = CommandLine.arguments[i + 1]
    Task { @MainActor in exit(await SelfTest.run(path: path)) }
    dispatchMain()
}

// `mSLICE --selftest-editor <fichier>` : logique du bistouri I / O sans fenêtre.
if let i = CommandLine.arguments.firstIndex(of: "--selftest-editor"), CommandLine.arguments.indices.contains(i + 1) {
    let path = CommandLine.arguments[i + 1]
    exit(MainActor.assumeIsolated { EditorTest.run(path: path) })
}

// `mSLICE --selftest-batch <fichier>` : élagage en lot sur une copie temporaire.
if let i = CommandLine.arguments.firstIndex(of: "--selftest-batch"), CommandLine.arguments.indices.contains(i + 1) {
    let path = CommandLine.arguments[i + 1]
    Task { @MainActor in exit(await BatchTest.run(path: path)) }
    dispatchMain()
}

// `mSLICE --selftest-analysis <fichier>` : analyse native (plans, scènes, sons), requêtes, temps, mémoire, annulation, pause.
if let i = CommandLine.arguments.firstIndex(of: "--selftest-analysis"), CommandLine.arguments.indices.contains(i + 1) {
    let path = CommandLine.arguments[i + 1]
    Task { @MainActor in exit(await AnalysisTest.run(path: path)) }
    dispatchMain()
}

// `mSLICE --selftest-dialogues [<fichier>]` : sous-titres, découpage en répliques, corrections, fichier de répliques ; avec un fichier : transcription réelle.
if let i = CommandLine.arguments.firstIndex(of: "--selftest-dialogues") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : nil
    Task { @MainActor in exit(await DialoguesTest.run(path: path)) }
    dispatchMain()
}

// `mSLICE --install-model <zip>` : installe le modèle des personnages depuis un zip local (essais et captures, sans fenêtre ni réseau) ; l'empreinte du zip doit être celle du catalogue.
if let i = CommandLine.arguments.firstIndex(of: "--install-model"), CommandLine.arguments.indices.contains(i + 1) {
    let zip = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let which = CommandLine.arguments.indices.contains(i + 2) ? CommandLine.arguments[i + 2] : "characters"       // « voices » pour le modèle de voix
    Task { @MainActor in
        let spec = ModelCatalog.all.first { $0.id == which } ?? ModelCatalog.characters
        do { try await ModelStore.installFile(zip, spec: spec, sha256: spec.sha256 ?? ""); print(ModelFiles.verified(spec) ? "installé et vérifié : \(ModelFiles.folder(spec).path)" : "installé mais non conforme"); exit(ModelFiles.verified(spec) ? 0 : 1) }
        catch { print("échec : \(error.localizedDescription)"); exit(1) }
    }
    dispatchMain()
}

// `mSLICE --dfn-run <entrée.wav (48 kHz mono)> <sortie.wav>` : débruitage DeepFilterNet3 sans fenêtre (essais de fidélité), sortie en flottants.
if let i = CommandLine.arguments.firstIndex(of: "--dfn-run"), CommandLine.arguments.indices.contains(i + 2) {
    let a = URL(fileURLWithPath: CommandLine.arguments[i + 1]), b = URL(fileURLWithPath: CommandLine.arguments[i + 2])
    guard let d = DeepFilterNet() else { print("modèle introuvable (MSLICE_DFN_MODEL)"); exit(1) }
    let t0 = Date(); let ok = d.run(input: a, output: b, job: AnalysisJob(), float32: true) { _ in }
    print(ok ? "OK : \(String(format: "%.2f", Date().timeIntervalSince(t0))) s" : "ÉCHEC"); exit(ok ? 0 : 1)
}

// `mSLICE --silence-info <fichier>` : silences trouvés (réglages de « blancs retirés ») et durée gagnée en fusionnant le fichier entier.
if let i = CommandLine.arguments.firstIndex(of: "--silence-info"), CommandLine.arguments.indices.contains(i + 1) {
    let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    Task { @MainActor in
        guard let info = Probe.read(url) else { print("sonde impossible"); exit(1) }
        let r = await Silence.ranges(info, noiseDB: Silence.trimNoiseDB, minDuration: Silence.trimMinDuration)
        let whole = [Segment(start: 0, end: info.duration)]
        let t = Silence.tighten(whole, silences: r, inside: true)
        print("durée \(String(format: "%.2f", info.duration)) s, \(r.count) silences (\(String(format: "%.2f", r.reduce(0) { $0 + $1.end - $1.start })) s), \(t.count) prises, \(String(format: "%.2f", t.reduce(0) { $0 + $1.duration })) s gardées")
        for z in r.prefix(12) { print(String(format: "  silence %.2f → %.2f (%.2f s)", z.start, z.end, z.end - z.start)) }
        exit(0)
    }
    dispatchMain()
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
