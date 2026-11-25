// mSLICE — reconnaissance des voix : une passe de lecture audio (16 kHz, mono), une fenêtre de 1,515 s toutes les 0,75 s, gardée seulement s'il y a de la parole
// (analyse sonore d'Apple quand elle existe, sinon un seuil d'énergie), empreinte par le modèle optionnel CAM++, puis regroupement (`VoiceClustering`).
// Mémoire bornée (on ne garde que la fenêtre en cours), qualité de service « utilitaire », pause pendant la lecture, annulable. Tourne dans le processus
// d'analyse séparé (`mslice-mcp --voices <fichier>`) : le modèle est rendu au système avec le processus.
import AVFoundation
import Foundation

enum VoicePass {
    static let maxWindows = 150_000
    static let minRMS: Float = 0.002
    static let speechMin: Float = 0.4          // confiance minimale de « parole » dans l'analyse sonore
    static let speechShare = 0.6               // part de la fenêtre qui doit être de la parole

    struct Record: Sendable { var t: Float; var vec: [Float] }

    /// Une passe de lecture ; nil si annulée ou impossible. `speech` : une valeur par case de `grid` secondes (confiance de la parole), nil sans analyse sonore.
    static func run(url: URL, duration: Double, speech: [Float]?, grid: Double, job: AnalysisJob, state: ProgressBox, embedder: VoiceEmbedder) -> [Record]? {
        let asset = AVURLAsset(url: url)
        guard let (track, _, _) = loadTrack(asset, .audio), let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: VoiceFeatures.rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        out.alwaysCopiesSampleData = false
        guard reader.canAdd(out) else { return nil }
        reader.add(out)
        guard reader.startReading() else { return nil }

        let win = VoiceFeatures.windowSamples, hopS = Int(VoiceIndex.hop * VoiceFeatures.rate)
        var buf: [Float] = []
        var base = 0                              // indice (dans le flux) du premier échantillon de `buf`
        var next = 0                              // début (dans le flux) de la prochaine fenêtre
        var origin: Double?
        var records: [Record] = []
        var total = 0
        while let sb = out.copyNextSampleBuffer() {
            if job.cancelled { reader.cancelReading(); return nil }
            AnalysisGate.shared.wait(job)
            if origin == nil { let p = CMSampleBufferGetPresentationTimeStamp(sb).seconds; if p.isFinite { origin = p } }
            guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
            var length = 0; var ptr: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr) == kCMBlockBufferNoErr, let p = ptr else { continue }
            let n = length / 4
            p.withMemoryRebound(to: Float.self, capacity: n) { buf.append(contentsOf: UnsafeBufferPointer(start: $0, count: n)) }
            total += n
            while base + buf.count >= next + win {
                let t = Double(next) / VoiceFeatures.rate + (origin ?? 0)
                if records.count < maxWindows, keep(t0: Double(next) / VoiceFeatures.rate, speech: speech, grid: grid, samples: buf, from: next - base, count: win),
                   let v = buf.withUnsafeBufferPointer({ embedder.embed(UnsafeBufferPointer(rebasing: $0[(next - base) ..< (next - base + win)])) }) {
                    records.append(Record(t: Float(t), vec: v))
                }
                next += hopS
            }
            if next > base { let drop = min(next - base, buf.count); buf.removeFirst(drop); base += drop }
            state.update { $0.images = min((Double(total) / VoiceFeatures.rate) / max(duration, 0.1), 1); $0.paused = AnalysisGate.shared.paused }
        }
        if reader.status == .failed, total == 0 { return nil }
        state.update(force: true) { $0.images = 1 }
        return records
    }

    private static func keep(t0: Double, speech: [Float]?, grid: Double, samples: [Float], from: Int, count: Int) -> Bool {
        var s: Float = 0
        for i in from ..< from + count { s += samples[i] * samples[i] }
        guard (s / Float(count)).squareRoot() >= minRMS else { return false }
        guard let speech else { return true }
        let c0 = max(Int((t0 / grid).rounded(.down)), 0), c1 = min(Int(((t0 + VoiceIndex.window) / grid).rounded(.up)), speech.count)
        guard c0 < c1 else { return false }
        var hit = 0
        for c in c0 ..< c1 where speech[c] >= speechMin { hit += 1 }
        return Double(hit) / Double(c1 - c0) >= speechShare
    }
}

enum VoiceAnalyzer {
    /// Reconnaissance complète d'un fichier : passe audio, regroupement, enregistrement dans `VoiceStore`. nil si annulée ou impossible (fichier sans son,
    /// modèle absent ou altéré).
    static func run(_ info: MediaInfo, job: AnalysisJob, slot: Bool = true, progress: @escaping @Sendable (AnalysisProgress) -> Void) async -> VoiceIndex? {
        guard info.audio != nil else { return nil }
        if slot { await AnalysisSlot.shared.acquire() }
        defer { if slot { Task { await AnalysisSlot.shared.release() } } }
        if job.cancelled { return nil }
        guard let embedder = VoiceEmbedder() else { return nil }
        let url = await Analyzer.source(info)
        let t0 = Date()
        let state = ProgressBox(AnalysisProgress(hasVideo: true, hasAudio: false), emit: progress)
        state.update { _ in }
        var speech: [Float]?, grid = 0.5
        if let idx = AnalysisStore.load(info), idx.hasAudio {
            let f = Finder(idx)
            speech = f.scores(FindTerm(kind: .sound, key: "speech")); grid = f.grid
        }
        let sp = speech, g = grid
        let found: [VoicePass.Record]? = await onThread { VoicePass.run(url: url, duration: info.duration, speech: sp, grid: g, job: job, state: state, embedder: embedder) }
        guard let records = found, !job.cancelled else { return nil }

        var v = VoiceIndex(duration: info.duration)
        v.modelSHA = ModelCatalog.voices.sha256 ?? ""
        for r in records {
            v.t.append(r.t)
            let q = VoiceIndex.quantize(r.vec)
            v.emb += q.q; v.embScale.append(q.scale)
        }
        v.group = VoiceClustering.cluster(v)
        v.nextGroup = (v.group.max() ?? -1) + 1
        if let faces = FaceStore.load(info) { v.link = VoiceLinking.link(v, faces: faces) }
        v.seconds = Date().timeIntervalSince(t0)
        VoiceStore.save(v, for: info)
        return v
    }
}

// MARK: Voix et visages

/// Associe chaque voix au personnage (groupe de visages) dont le visage est seul à l'écran pendant qu'elle parle. Une voix est liée si au moins 2 s de sa
/// parole tombent sur un seul personnage visible et si ce personnage en couvre au moins 60 % ; un personnage n'est lié qu'à la voix qui le couvre le mieux.
enum VoiceLinking {
    static let minSeconds = 2.0, minShare = 0.6

    static func link(_ v: VoiceIndex, faces f: FaceIndex) -> [Int32: Int32] {
        // seconde entière → ensemble des personnages à l'écran
        var visible: [Int: Set<Int32>] = [:]
        for i in 0 ..< f.count where f.group[i] >= 0 && !f.hidden.contains(f.group[i]) { visible[Int((Double(f.t[i]) / f.step).rounded()), default: []].insert(f.group[i]) }
        var score: [Int32: [Int32: Double]] = [:]
        for g in v.voices().map(\.id) {
            for iv in v.intervals(of: g) {
                var t = iv.start
                while t < iv.end - 1e-6 {
                    let e = min(t + 0.25, iv.end)
                    if let p = visible[Int((((t + e) / 2) / f.step).rounded())], p.count == 1, let who = p.first { score[g, default: [:]][who, default: 0] += e - t }
                    t = e
                }
            }
        }
        var best: [(voice: Int32, person: Int32, seconds: Double)] = []
        for (g, m) in score {
            let all = m.values.reduce(0, +)
            if let top = m.max(by: { $0.value < $1.value }), top.value >= minSeconds, top.value / all >= minShare { best.append((g, top.key, top.value)) }
        }
        var out: [Int32: Int32] = [:], used = Set<Int32>()
        for b in best.sorted(by: { $0.seconds > $1.seconds }) where !used.contains(b.person) { out[b.voice] = b.person; used.insert(b.person) }
        return out
    }
}
