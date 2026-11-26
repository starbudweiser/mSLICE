// mSLICE — débruitage de la voix par DeepFilterNet3 (Schröter et al., licence MIT : licenses/DeepFilterNet-LICENSE-MIT.txt), modèle Core ML de 9 Mo embarqué.
// Le réseau (encodeur, décodeurs, GRU) est dans `DeepFilterNet3.mlmodelc` ; tout le reste de la chaîne est porté ici : STFT (fenêtre de Vorbis, 960 / 480 à 48 kHz),
// caractéristiques ERB (dB, moyenne glissante) et spectrales (norme unitaire), masque ERB au-dessus de 4,6 kHz, filtrage profond (ordre 5, anticipation 2) en dessous, synthèse.
// Validé contre la chaîne d'origine (libdf + PyTorch) : voir `--dfn-run`. Traitement en flux par blocs de 500 images (5 s) :
// les 8 premières images de chaque bloc ne servent qu'au contexte des convolutions, l'état des GRU passe d'un bloc au suivant (résultat identique à un seul passage).
// Sans interface : partagé avec `mslice-mcp`.
import Accelerate
import AVFoundation
import CoreML
import Foundation

final class DeepFilterNet {
    static let sr = 48000.0
    private static let N = 960, H = 480, F = 481, E = 32, D = 96, order = 5, look = 2
    private static let T = 500, K = 8                       // images par bloc, images de contexte
    private static let alpha: Float = 0.99                  // exp(−0,01 s / 1 s)

    /// Dossier du modèle compilé : `MSLICE_DFN_MODEL` (essais), sinon `Resources` de l'appli (aussi vu depuis `mslice-mcp`, dans `Contents/MacOS`).
    static var modelURL: URL? {
        if let p = ProcessInfo.processInfo.environment["MSLICE_DFN_MODEL"] { return URL(fileURLWithPath: p) }
        let name = "DeepFilterNet3.mlmodelc"
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent(name),
                          Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/\(name)")]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static var available: Bool { modelURL != nil }

    private let model: MLModel
    private let win: [Float]
    private let erbEdges: [Int]
    private let setupF: vDSP_DFT_Setup, setupI: vDSP_DFT_Setup

    init?() {
        guard let url = Self.modelURL else { return nil }
        let cfg = MLModelConfiguration(); cfg.computeUnits = ProcessInfo.processInfo.environment["MSLICE_DFN_CPU"] != nil ? .cpuOnly : .cpuAndGPU
        guard let m = try? MLModel(contentsOf: url, configuration: cfg),
              let f = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(Self.N), .FORWARD), let i = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(Self.N), .INVERSE) else { return nil }
        model = m; setupF = f; setupI = i
        let half = Self.N / 2
        var w = [Float](repeating: 0, count: Self.N)
        for n in 0..<half {
            let s = sin(0.5 * Double.pi * (Double(n) + 0.5) / Double(half))
            let v = Float(sin(0.5 * Double.pi * s * s)); w[n] = v; w[Self.N - 1 - n] = v
        }
        win = w
        erbEdges = Self.erbEdges()
    }
    deinit { vDSP_DFT_DestroySetup(setupF); vDSP_DFT_DestroySetup(setupI) }

    /// Largeurs des bandes ERB de libdf (48 kHz, FFT 960, 32 bandes, 2 bins au minimum) : relevées sur la bibliothèque d'origine, somme 481.
    private static func erbEdges() -> [Int] {
        let widths = [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 5, 5, 7, 7, 8, 10, 12, 13, 15, 18, 20, 24, 28, 31, 37, 42, 50, 56, 67]
        var e = [0]; for w in widths { e.append(e.last! + w) }
        return e
    }

    // MARK: flux

    /// Débruite un WAV mono 48 kHz vers un autre WAV (même longueur) ; progression 0…1, annulable. `float32` : rendu en flottants (essais) au lieu de 16 bits.
    func run(input: URL, output: URL, job: AnalysisJob, float32: Bool = false, progress: @escaping @Sendable (Double) -> Void) -> Bool {
        guard let file = try? AVAudioFile(forReading: input), file.length > 0, file.processingFormat.sampleRate == Self.sr,
              let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sr, channels: 1, interleaved: false) else { return false }
        let total = Int(file.length)
        try? FileManager.default.removeItem(at: output)
        let settings: [String: Any] = float32
            ? [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.sr, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false]
            : [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.sr, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        guard let out = try? AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false),
              let rbuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1 << 16), let wbuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(Self.H * (Self.T + 2))) else { return false }

        let N = Self.N, H = Self.H, F = Self.F, E = Self.E, D = Self.D, T = Self.T, K = Self.K, nB = Self.T - Self.K
        let nt = (total + N - H) / H + 1                        // images d'analyse : l'entrée est prolongée de N zéros comme dans enhance()
        // lecture séquentielle de l'entrée, prolongée par des zéros
        var readPos = 0
        func nextHop() -> [Float]? {
            var h = [Float](repeating: 0, count: H); var got = 0
            while got < H && readPos < total {
                rbuf.frameLength = 0
                let want = AVAudioFrameCount(min(Int(rbuf.frameCapacity), H - got, total - readPos))
                do { try file.read(into: rbuf, frameCount: want) } catch { return nil }
                let n = Int(rbuf.frameLength); if n == 0 { break }
                let p = rbuf.floatChannelData![0]; for i in 0..<n { h[got + i] = p[i] }
                got += n; readPos += n
            }
            return h
        }

        // mémoire glissante des images (indices absolus ; on garde de base à base+count)
        var base = 0
        var specRe = [Float](), specIm = [Float](), fErb = [Float](), fSpec = [Float]()         // F, F, E, D×2 par image
        var mem = [Float](repeating: 0, count: N - H)
        var erbState = (0..<E).map { Float(-60) + (Float(-90) - Float(-60)) * Float($0) / Float(E - 1) }
        var unitState = (0..<D).map { Float(0.001) + (Float(0.0001) - Float(0.001)) * Float($0) / Float(D - 1) }
        var computed = 0                                                                         // images d'analyse déjà faites
        var frame = [Float](repeating: 0, count: N), zero = [Float](repeating: 0, count: N)
        var re = [Float](repeating: 0, count: N), im = [Float](repeating: 0, count: N), inRe = [Float](repeating: 0, count: N)
        var oRe = [Float](repeating: 0, count: N), oIm = [Float](repeating: 0, count: N)
        let wnorm = Float(1.0 / (Double(N * N) / Double(2 * H)))

        func analyse(upTo last: Int) -> Bool {
            let upper = min(last, nt - 1)
            while computed <= upper {
                guard let hop = nextHop() else { return false }
                for i in 0..<(N - H) { frame[i] = mem[i] }
                for i in 0..<H { frame[N - H + i] = hop[i] }
                for i in 0..<(N - H) { mem[i] = frame[H + i] }
                vDSP_vmul(frame, 1, win, 1, &inRe, 1, vDSP_Length(N))
                vDSP_DFT_Execute(setupF, inRe, zero, &re, &im)
                // images stockées
                var s = [Float](repeating: 0, count: F), sI = [Float](repeating: 0, count: F)
                for k in 0..<F { s[k] = re[k] * wnorm; sI[k] = im[k] * wnorm }
                specRe += s; specIm += sI
                // ERB (dB) normalisée
                for b in 0..<E {
                    var p: Float = 0
                    for k in erbEdges[b]..<erbEdges[b + 1] { p += s[k] * s[k] + sI[k] * sI[k] }
                    p /= Float(erbEdges[b + 1] - erbEdges[b])
                    let db = 10 * log10(p + 1e-10)
                    erbState[b] = db * (1 - Self.alpha) + erbState[b] * Self.alpha
                    fErb.append((db - erbState[b]) / 40)
                }
                for k in 0..<D {
                    let mag = (s[k] * s[k] + sI[k] * sI[k]).squareRoot()
                    unitState[k] = mag * (1 - Self.alpha) + unitState[k] * Self.alpha
                    let r = 1 / unitState[k].squareRoot()
                    fSpec.append(s[k] * r); fSpec.append(sI[k] * r)
                }
                computed += 1
            }
            return true
        }

        // sortie
        var outMem = [Float](repeating: 0, count: N - H)
        var skip = N - H                                                                         // retard de la chaîne STFT : on écarte les 480 premiers échantillons
        var remaining = total
        func emit(_ samples: UnsafePointer<Float>, _ n: Int) {
            var s = 0
            if skip > 0 { s = min(skip, n); skip -= s }
            let take = min(n - s, remaining); if take <= 0 { return }
            let p = wbuf.floatChannelData![0]
            for i in 0..<take { p[Int(wbuf.frameLength) + i] = samples[s + i] }
            wbuf.frameLength += AVAudioFrameCount(take); remaining -= take
        }

        var hEnc = [Float](repeating: 0, count: 256), hErb = [Float](repeating: 0, count: 512), hDf = [Float](repeating: 0, count: 512)
        var o = 0
        let inErb = try? MLMultiArray(shape: [1, 1, NSNumber(value: T), NSNumber(value: E)], dataType: .float32)
        let inSpec = try? MLMultiArray(shape: [1, 1, NSNumber(value: T), NSNumber(value: D), 2], dataType: .float32)
        let inH1 = try? MLMultiArray(shape: [1, 1, 256], dataType: .float32), inH2 = try? MLMultiArray(shape: [2, 1, 256], dataType: .float32), inH3 = try? MLMultiArray(shape: [2, 1, 256], dataType: .float32)
        guard let inErb, let inSpec, let inH1, let inH2, let inH3 else { return false }
        var fr = [Float](repeating: 0, count: N)
        var maskBin = [Float](repeating: 0, count: F)

        while o < nt {
            if job.cancelled { return false }
            // il faut les images d'analyse jusqu'à o + nB − 1 + anticipation (2) : caractéristiques et filtrage profond
            guard analyse(upTo: o + nB + Self.look) else { return false }
            let eP = inErb.dataPointer.assumingMemoryBound(to: Float.self), sP = inSpec.dataPointer.assumingMemoryBound(to: Float.self)
            for p in 0..<T {
                let j = o - K + p, f = j + Self.look                                             // image du réseau, caractéristique décalée de l'anticipation
                if j >= 0 && f < nt {                                                            // avant le début : contexte nul (comme le remplissage de la chaîne d'origine)
                    let r = (f - base)
                    for e in 0..<E { eP[p * E + e] = fErb[r * E + e] }
                    for d in 0..<(D * 2) { sP[p * D * 2 + d] = fSpec[r * D * 2 + d] }
                } else {
                    for e in 0..<E { eP[p * E + e] = 0 }
                    for d in 0..<(D * 2) { sP[p * D * 2 + d] = 0 }
                }
            }
            func fill(_ a: MLMultiArray, _ v: [Float]) { let p = a.dataPointer.assumingMemoryBound(to: Float.self); for i in 0..<v.count { p[i] = v[i] } }
            fill(inH1, hEnc); fill(inH2, hErb); fill(inH3, hDf)
            let feats = try? MLDictionaryFeatureProvider(dictionary: ["feat_erb": inErb, "feat_spec": inSpec, "h_enc": inH1, "h_erb": inH2, "h_df": inH3])
            guard let feats, let pred = try? model.prediction(from: feats),
                  let mask = pred.featureValue(for: "mask")?.multiArrayValue, let coefs = pred.featureValue(for: "coefs")?.multiArrayValue,
                  let nE = pred.featureValue(for: "n_enc")?.multiArrayValue, let nR = pred.featureValue(for: "n_erb")?.multiArrayValue, let nD = pred.featureValue(for: "n_df")?.multiArrayValue else { return false }
            hEnc = Self.contiguous(nE, 256); hErb = Self.contiguous(nR, 512); hDf = Self.contiguous(nD, 512)
            let mS = mask.strides.map { $0.intValue }, cS = coefs.strides.map { $0.intValue }          // [1,1,T,32], [1,5,T,96,2]
            let mP = mask.dataPointer.assumingMemoryBound(to: Float.self), cP = coefs.dataPointer.assumingMemoryBound(to: Float.self)

            let last = min(o + nB, nt)
            for t in o..<last {
                let p = K + (t - o)
                // masque ERB → bins (au-dessus de D) ; filtrage profond en dessous
                for b in 0..<E {
                    let m = mP[p * mS[2] + b * mS[3]]
                    for k in erbEdges[b]..<erbEdges[b + 1] { maskBin[k] = m }
                }
                let r = t - base
                for k in 0..<F { re[k] = specRe[r * F + k] * maskBin[k]; im[k] = specIm[r * F + k] * maskBin[k] }
                for k in 0..<D {
                    var ar: Float = 0, ai: Float = 0
                    for n in 0..<Self.order {
                        let ti = t - 2 + n
                        guard ti >= 0 && ti < nt else { continue }
                        let rr = ti - base
                        let sr = specRe[rr * F + k], si = specIm[rr * F + k]
                        let cr = cP[n * cS[1] + p * cS[2] + k * cS[3]], ci = cP[n * cS[1] + p * cS[2] + k * cS[3] + cS[4]]
                        ar += sr * cr - si * ci; ai += sr * ci + si * cr
                    }
                    re[k] = ar; im[k] = ai
                }
                // spectre hermitien complet puis transformée inverse non normalisée
                for k in F..<N { re[k] = re[N - k]; im[k] = -im[N - k] }
                vDSP_DFT_Execute(setupI, re, im, &oRe, &oIm)
                vDSP_vmul(oRe, 1, win, 1, &fr, 1, vDSP_Length(N))
                for i in 0..<(N - H) { fr[i] += outMem[i] }
                for i in 0..<(N - H) { outMem[i] = fr[H + i] }
                fr.withUnsafeBufferPointer { emit($0.baseAddress!, H) }
            }
            if wbuf.frameLength > 0 { do { try out.write(from: wbuf) } catch { return false }; wbuf.frameLength = 0 }
            o = last
            // on oublie les images dont on n'a plus besoin (contexte K + filtrage profond 2)
            let keepFrom = max(o - K - 2, 0)
            if keepFrom > base {
                let drop = keepFrom - base
                specRe.removeFirst(drop * F); specIm.removeFirst(drop * F); fErb.removeFirst(drop * E); fSpec.removeFirst(drop * D * 2); base = keepFrom
            }
            progress(min(Double(o) / Double(nt), 1))
        }
        return true
    }

    private static func contiguous(_ a: MLMultiArray, _ count: Int) -> [Float] {
        // les états sont de petites matrices [couches, 1, 256] : lecture par indice logique (indépendante des pas mémoire)
        (0..<count).map { a[$0].floatValue }
    }
}
