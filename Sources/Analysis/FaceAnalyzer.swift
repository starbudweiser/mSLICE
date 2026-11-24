// mSLICE — reconnaissance des personnages : une image par seconde, visages et repères (Vision), visage aligné 112 × 112 sur le gabarit ArcFace, empreinte de
// 512 valeurs par le modèle optionnel (AuraFace en Core ML, moteur neuronal), puis suivis et regroupement (`FaceClustering`). Mêmes règles que l'analyse
// native : une seule passe de décodage matériel, mémoire bornée, qualité de service « utilitaire », pause pendant la lecture, annulable. Tourne dans le
// processus d'analyse séparé (`mslice-mcp --faces <fichier>`) : le modèle est rendu au système avec le processus.
//
// Le modèle n'est chargé que s'il est installé ET que son empreinte recalculée est conforme (`ModelFiles.verified`).
import AVFoundation
import CoreImage
import CoreML
import Foundation
import Vision

/// Le modèle d'empreintes (entrée : image RGB 112 × 112 alignée, 0…255 ; sortie : 512 valeurs, normalisées ici).
final class FaceEmbedder: @unchecked Sendable {
    private let model: MLModel
    private let input: String, output: String
    private let lock = NSLock()

    init?(spec: ModelSpec = ModelCatalog.characters) {
        guard ModelFiles.verified(spec) else { return nil }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuAndNeuralEngine
        guard let m = try? MLModel(contentsOf: ModelFiles.compiled(spec), configuration: cfg),
              let i = m.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .image })?.key,
              let o = m.modelDescription.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key else { return nil }
        model = m; input = i; output = o
    }

    /// Empreinte normalisée (norme 1) d'un visage aligné ; nil si le modèle échoue ou rend autre chose que 512 valeurs.
    func embed(_ pb: CVPixelBuffer) -> [Float]? {
        lock.lock(); defer { lock.unlock() }
        guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: [input: MLFeatureValue(pixelBuffer: pb)])),
              let arr = out.featureValue(for: output)?.multiArrayValue, arr.count == FaceIndex.dim else { return nil }
        var v = [Float](repeating: 0, count: FaceIndex.dim)
        var s: Float = 0
        for i in 0 ..< FaceIndex.dim { let x = arr[i].floatValue; v[i] = x; s += x * x }
        guard s.isFinite, s > 1e-12 else { return nil }
        let inv = 1 / s.squareRoot()
        for i in 0 ..< FaceIndex.dim { v[i] *= inv }
        return v
    }
}

enum FacePass {
    static let step = 1.0                    // une image par seconde (mesuré à l'essai des modèles)
    static let minPixels = 32.0              // plus petit visage gardé (largeur, en pixels de l'image analysée)
    static let maxFaces = 12_000
    /// Décodage à la résolution d'origine jusqu'à 1 920 px : mesuré à l'essai, 1 280 px ralentit la passe par 2,5 (mise à l'échelle) sans abaisser la mémoire,
    /// qui est surtout celle du modèle chargé (≈ 280 Mo de pic dans le processus, rendus en entier à sa fin) ; le nombre d'images en attente ne change rien.
    static let decodeWidth = 1920
    static let pending = 2

    struct Record: Sendable { var t: Float; var box: [Float]; var px: Float; var vec: [Float] }

    private final class Records: @unchecked Sendable {
        private let lock = NSLock()
        private var byFrame: [Int: [Record]] = [:]
        func set(_ i: Int, _ r: [Record]) { lock.lock(); byFrame[i] = r; lock.unlock() }
        func all() -> [Record] { lock.lock(); defer { lock.unlock() }; return byFrame.keys.sorted().flatMap { byFrame[$0] ?? [] } }
    }

    /// Gabarit ArcFace 112×112 (origine en haut à gauche) : œil gauche (côté gauche de l'image), œil droit, bout du nez, coins gauche et droit de la bouche.
    private static let template: [(Double, Double)] = [(38.2946, 51.6963), (73.5318, 51.5014), (56.0252, 71.7366), (41.5493, 92.3655), (70.7299, 92.2041)]

    /// Similitude (échelle, rotation, translation) par moindres carrés (Umeyama) qui amène `src` sur `dst`.
    static func similarity(_ src: [(Double, Double)], _ dst: [(Double, Double)]) -> CGAffineTransform {
        let n = Double(src.count)
        let sm = (src.map { $0.0 }.reduce(0, +) / n, src.map { $0.1 }.reduce(0, +) / n)
        let dm = (dst.map { $0.0 }.reduce(0, +) / n, dst.map { $0.1 }.reduce(0, +) / n)
        var a = 0.0, b = 0.0, den = 0.0
        for i in 0 ..< src.count {
            let sx = src[i].0 - sm.0, sy = src[i].1 - sm.1, dx = dst[i].0 - dm.0, dy = dst[i].1 - dm.1
            a += sx * dx + sy * dy; b += sx * dy - sy * dx; den += sx * sx + sy * sy
        }
        guard den > 1e-9 else { return .identity }
        let c = a / den, s = b / den
        return CGAffineTransform(a: c, b: s, c: -s, d: c, tx: dm.0 - (c * sm.0 - s * sm.1), ty: dm.1 - (s * sm.0 + c * sm.1))
    }

    private static func buffer() -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 112, 112, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        return pb
    }

    /// Les visages d'une image : détection, repères, alignement, empreinte.
    static func faces(in pb: CVPixelBuffer, orient: CGImagePropertyOrientation, pts: Double, ctx: CIContext, embedder: FaceEmbedder) -> [Record] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: orient, options: [:])
        guard (try? handler.perform([request])) != nil, let found = request.results, !found.isEmpty else { return [] }
        var img = CIImage(cvPixelBuffer: pb).oriented(orient)
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        let W = Double(img.extent.width), H = Double(img.extent.height)
        let size = CGSize(width: W, height: H)
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 112, height: 112))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var out: [Record] = []
        for f in found.sorted(by: { $0.boundingBox.minX < $1.boundingBox.minX }) {
            let bb = f.boundingBox
            let bw = bb.width * W, bh = bb.height * H
            guard bw >= minPixels, let lm = f.landmarks, let le = lm.leftEye, let re = lm.rightEye, let nose = lm.nose, let lips = lm.outerLips else { continue }
            func pointsOf(_ r: VNFaceLandmarkRegion2D) -> [(Double, Double)] { r.pointsInImage(imageSize: size).map { (Double($0.x), Double($0.y)) } }
            func mean(_ p: [(Double, Double)]) -> (Double, Double) { (p.map { $0.0 }.reduce(0, +) / Double(p.count), p.map { $0.1 }.reduce(0, +) / Double(p.count)) }
            let lp = pointsOf(lips), np = pointsOf(nose)
            guard lp.count >= 2, !np.isEmpty, !pointsOf(le).isEmpty, !pointsOf(re).isEmpty else { continue }
            var eyeL = mean(pointsOf(le)), eyeR = mean(pointsOf(re))
            if let a = lm.leftPupil, let b = lm.rightPupil, !pointsOf(a).isEmpty, !pointsOf(b).isEmpty { eyeL = mean(pointsOf(a)); eyeR = mean(pointsOf(b)) }
            if eyeL.0 > eyeR.0 { swap(&eyeL, &eyeR) }
            let ys = np.map { $0.1 }
            let noseTip = (mean(np).0, ys.min()! + 0.25 * (ys.max()! - ys.min()!))
            let mL = lp.min { $0.0 < $1.0 }!, mR = lp.max { $0.0 < $1.0 }!
            let T = similarity([eyeL, eyeR, noseTip, mL, mR], template.map { ($0.0, 112 - $0.1) })       // le gabarit passe en origine « en bas à gauche »
            let aligned = img.transformed(by: T).composited(over: gray).cropped(to: CGRect(x: 0, y: 0, width: 112, height: 112))
            guard let buf = buffer() else { continue }
            ctx.render(aligned, to: buf, bounds: CGRect(x: 0, y: 0, width: 112, height: 112), colorSpace: space)
            guard let v = embedder.embed(buf) else { continue }
            out.append(Record(t: Float(pts), box: [Float(bb.minX), Float(1 - bb.maxY), Float(bb.width), Float(bb.height)], px: Float(bh), vec: v))
        }
        return out
    }

    /// Une passe de décodage matériel ; nil si annulée ou impossible.
    static func run(url: URL, duration: Double, job: AnalysisJob, state: ProgressBox, embedder: FaceEmbedder) -> [Record]? {
        let asset = AVURLAsset(url: url)
        guard let (track, natural, transform) = loadTrack(asset, .video) else { return nil }
        let nw = max(abs(natural.width), 16), nh = max(abs(natural.height), 16)
        let w = min(Double(decodeWidth), nw), scale = w / nw
        let outW = Int(w) & ~1, outH = Int(nh * scale) & ~1
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: outW, kCVPixelBufferHeightKey as String: outH,
        ])
        out.alwaysCopiesSampleData = false
        guard reader.canAdd(out) else { return nil }
        reader.add(out)
        guard reader.startReading() else { return nil }
        let orient = VideoPass.orientation(transform)
        let ctx = CIContext(options: [.cacheIntermediates: false])
        let records = Records()
        let queue = DispatchQueue(label: "fr.stephan.mslice.faces", qos: .utility, attributes: .concurrent)
        let slots = DispatchSemaphore(value: max(pending, 1))
        let group = DispatchGroup()
        var nextSample = 0, lastPTS = 0.0

        while let sb = out.copyNextSampleBuffer() {
            if job.cancelled { reader.cancelReading(); break }
            AnalysisGate.shared.wait(job)
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
            guard pts.isFinite else { continue }
            lastPTS = pts
            if pts >= Double(nextSample) * step - 0.001 {
                let index = nextSample
                nextSample = max(nextSample + 1, Int((pts / step).rounded(.down)) + 1)
                slots.wait(); group.enter()
                queue.async {
                    autoreleasepool { records.set(index, faces(in: pb, orient: orient, pts: pts, ctx: ctx, embedder: embedder)) }
                    if index % 20 == 19 { ctx.clearCaches() }
                    slots.signal(); group.leave()
                }
            }
            state.update { $0.images = min(pts / max(duration, 0.1), 1); $0.imagesTime = pts; $0.paused = AnalysisGate.shared.paused }
        }
        group.wait()
        if job.cancelled { return nil }
        if reader.status == .failed, lastPTS < duration * 0.5 { return nil }
        state.update(force: true) { $0.images = 1; $0.imagesTime = duration }
        return records.all()
    }
}

enum FaceAnalyzer {
    /// Reconnaissance complète d'un fichier : passe d'images, suivis, regroupement, enregistrement dans `FaceStore`. nil si annulée ou impossible
    /// (fichier sans image, modèle absent ou altéré).
    static func run(_ info: MediaInfo, job: AnalysisJob, slot: Bool = true, progress: @escaping @Sendable (AnalysisProgress) -> Void) async -> FaceIndex? {
        guard !info.isAudioOnly, info.video != nil else { return nil }
        if slot { await AnalysisSlot.shared.acquire() }
        defer { if slot { Task { await AnalysisSlot.shared.release() } } }
        if job.cancelled { return nil }
        guard let embedder = FaceEmbedder() else { return nil }
        let url = await Analyzer.source(info)
        let t0 = Date()
        let state = ProgressBox(AnalysisProgress(hasVideo: true, hasAudio: false), emit: progress)
        state.update { _ in }
        let found: [FacePass.Record]? = await onThread { FacePass.run(url: url, duration: info.duration, job: job, state: state, embedder: embedder) }
        guard var records = found, !job.cancelled else { return nil }
        if records.count > FacePass.maxFaces { records = Array(records.sorted { $0.px > $1.px }.prefix(FacePass.maxFaces)).sorted { ($0.t, $0.box[0]) < ($1.t, $1.box[0]) } }

        var f = FaceIndex(duration: info.duration)
        f.step = FacePass.step
        f.modelSHA = ModelCatalog.characters.sha256 ?? ""
        for r in records {
            f.t.append(r.t); f.box += r.box; f.px.append(r.px)
            let q = FaceIndex.quantize(r.vec)
            f.emb += q.q; f.embScale.append(q.scale)
        }
        f.track = FaceClustering.tracks(f, cuts: AnalysisStore.load(info)?.cuts ?? [])
        f.group = FaceClustering.cluster(f)
        f.nextGroup = (f.group.max() ?? -1) + 1
        f.seconds = Date().timeIntervalSince(t0)
        FaceStore.save(f, for: info)
        return f
    }
}
