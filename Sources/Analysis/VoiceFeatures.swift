// mSLICE — empreinte de voix : caractéristiques sonores (banc de filtres de Kaldi, 80 bandes) puis modèle optionnel CAM++ (3D-Speaker, Apache 2.0) en Core ML.
//
// Le calcul des caractéristiques reproduit `torchaudio.compliance.kaldi.fbank` aux valeurs par défaut utilisées à l'entraînement du modèle : trames de 25 ms
// toutes les 10 ms, fenêtre de Povey, pré-accentuation 0,97, composante continue retirée, FFT sur 512 points, spectre de puissance, 80 filtres
// triangulaires de 20 Hz à 8 kHz (échelle mel), logarithme ; échantillons mis à l'échelle ×32 768 ; puis moyenne retirée sur la fenêtre.
// Une fenêtre de 24 240 échantillons (1,515 s) donne exactement 150 trames, la longueur fixe du modèle converti.
import Accelerate
import CoreML
import Foundation

enum VoiceFeatures {
    static let rate = 16000.0
    static let frames = 150
    static let windowSamples = 400 + 160 * (frames - 1)       // 24 240 échantillons = 1,515 s
    static let bins = 80
    private static let fft = 512, half = 257

    /// Fenêtre de Povey (Hann élevée à 0,85) sur 400 échantillons.
    private static let window: [Float] = (0 ..< 400).map { Float(pow(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / 399), 0.85)) }

    /// Filtres triangulaires (80 × 257), construits dans l'échelle mel comme Kaldi.
    private static let filters: [Float] = {
        func mel(_ f: Double) -> Double { 1127 * log(1 + f / 700) }
        let low = mel(20), high = mel(8000), delta = (high - low) / Double(bins + 1)
        var m = [Float](repeating: 0, count: bins * half)
        for b in 0 ..< bins {
            let l = low + Double(b) * delta, c = low + Double(b + 1) * delta, r = low + Double(b + 2) * delta
            for k in 0 ..< half {
                let mk = mel(Double(k) * rate / Double(fft))
                if mk > l && mk < r { m[b * half + k] = Float(mk <= c ? (mk - l) / (c - l) : (r - mk) / (r - c)) }
            }
        }
        return m
    }()

    private static let log2n = vDSP_Length(9)
    private static let setup = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2))!

    /// 150 × 80 valeurs (ligne par trame) pour exactement `windowSamples` échantillons (−1…1) ; nil si le signal est plus court.
    static func fbank(_ x: UnsafeBufferPointer<Float>) -> [Float]? {
        guard x.count >= windowSamples else { return nil }
        var out = [Float](repeating: 0, count: frames * bins)
        var frame = [Float](repeating: 0, count: fft)
        var re = [Float](repeating: 0, count: fft / 2), im = [Float](repeating: 0, count: fft / 2)
        var power = [Float](repeating: 0, count: half)
        let eps = Float.ulpOfOne
        for t in 0 ..< frames {
            let o = t * 160
            var mean: Float = 0
            for i in 0 ..< 400 { frame[i] = x[o + i] * 32768; mean += frame[i] }
            mean /= 400
            for i in 0 ..< 400 { frame[i] -= mean }
            for i in stride(from: 399, to: 0, by: -1) { frame[i] -= 0.97 * frame[i - 1] }
            frame[0] -= 0.97 * frame[0]                                   // premier échantillon : prolongé par réplication (Kaldi)
            for i in 0 ..< 400 { frame[i] *= window[i] }
            for i in 400 ..< fft { frame[i] = 0 }
            // FFT réelle (rangement compact : re[0] = DC, im[0] = Nyquist) ; vDSP donne 2 × la transformée
            re.withUnsafeMutableBufferPointer { rp in im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { fp in fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fft / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fft / 2)) } }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            } }
            power[0] = (re[0] / 2) * (re[0] / 2)
            power[half - 1] = (im[0] / 2) * (im[0] / 2)
            for k in 1 ..< fft / 2 { power[k] = (re[k] * re[k] + im[k] * im[k]) / 4 }
            for b in 0 ..< bins {
                var s: Float = 0
                vDSP_dotpr(filters.withUnsafeBufferPointer { $0.baseAddress! + b * half }, 1, power, 1, &s, vDSP_Length(half))
                out[t * bins + b] = log(max(s, eps))
            }
        }
        for b in 0 ..< bins {                                              // moyenne retirée sur la fenêtre
            var s: Float = 0
            for t in 0 ..< frames { s += out[t * bins + b] }
            s /= Float(frames)
            for t in 0 ..< frames { out[t * bins + b] -= s }
        }
        return out
    }
}

/// Le modèle de voix (entrée : 150 × 80 caractéristiques ; sortie : 512 valeurs, normalisées ici).
final class VoiceEmbedder: @unchecked Sendable {
    static let dim = 512
    private let model: MLModel
    private let input: String, output: String
    private let lock = NSLock()

    init?(spec: ModelSpec = ModelCatalog.voices) {
        guard ModelFiles.verified(spec) else { return nil }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuAndNeuralEngine
        guard let m = try? MLModel(contentsOf: ModelFiles.compiled(spec), configuration: cfg),
              let i = m.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key,
              let o = m.modelDescription.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key else { return nil }
        model = m; input = i; output = o
    }

    /// Empreinte normalisée (norme 1) de 24 240 échantillons ; nil si le modèle échoue.
    func embed(_ samples: UnsafeBufferPointer<Float>) -> [Float]? {
        guard let f = VoiceFeatures.fbank(samples), let arr = try? MLMultiArray(shape: [1, NSNumber(value: VoiceFeatures.frames), NSNumber(value: VoiceFeatures.bins)], dataType: .float32) else { return nil }
        f.withUnsafeBufferPointer { src in arr.dataPointer.copyMemory(from: src.baseAddress!, byteCount: src.count * 4) }
        lock.lock(); defer { lock.unlock() }
        guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: [input: MLFeatureValue(multiArray: arr)])),
              let r = out.featureValue(for: output)?.multiArrayValue, r.count == Self.dim else { return nil }
        var v = [Float](repeating: 0, count: Self.dim)
        var s: Float = 0
        for i in 0 ..< Self.dim { let x = r[i].floatValue; v[i] = x; s += x * x }
        guard s.isFinite, s > 1e-12 else { return nil }
        let inv = 1 / s.squareRoot()
        for i in 0 ..< Self.dim { v[i] *= inv }
        return v
    }
}
