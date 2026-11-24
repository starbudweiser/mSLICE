// mSLICE — analyse native d'un fichier : plans, étiquettes de scène (Vision) et sons (SoundAnalysis). Sans interface, partagée avec `mslice-mcp`.
//
// Une seule passe de décodage matériel (AVAssetReader, 512 px) lit toutes les images : chacune sert à détecter les coupures (miniature 32×18),
// et une image toutes les 0,5 s part en classification. Aucune image n'est gardée : l'empreinte mémoire reste celle de quelques tampons.
// En parallèle, une seconde passe décode l'audio en 16 kHz mono et le confie à SoundAnalysis.
// Tout tourne en qualité de service « utilitaire », une analyse à la fois, et se met en pause quand l'appli lit ou exporte (`AnalysisGate`).
import AVFoundation
import CoreMedia
import Foundation
import SoundAnalysis
import Vision

/// Annulation d'une analyse (bouton Annuler, fermeture du fichier).
final class AnalysisJob: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
}

/// Pause demandée par l'appli pendant la lecture ou l'export : l'analyse cède le processeur et reprend ensuite.
final class AnalysisGate: @unchecked Sendable {
    static let shared = AnalysisGate()
    private let lock = NSLock()
    private var flag = false
    var paused: Bool { get { lock.lock(); defer { lock.unlock() }; return flag } set { lock.lock(); flag = newValue; lock.unlock() } }
    /// Attend la fin de la pause (ou l'annulation).
    func wait(_ job: AnalysisJob) { while paused, !job.cancelled { Thread.sleep(forTimeInterval: 0.15) } }
}

struct AnalysisProgress: Sendable {
    var hasVideo = false, hasAudio = false
    var sounds = 0.0, images = 0.0          // 0…1
    var imagesTime = 0.0                    // secondes de vidéo déjà traitées
    var soundsSeconds = 0.0                 // durée du calcul des sons, une fois terminé
    var paused = false
    var memoryMB = 0.0                      // empreinte du processus qui analyse
    var fraction: Double {
        switch (hasVideo, hasAudio) {
        case (true, true): return 0.1 * sounds + 0.9 * images
        case (true, false): return images
        case (false, true): return sounds
        default: return 0
        }
    }
}

/// Une seule analyse à la fois dans le processus : les autres attendent leur tour.
actor AnalysisSlot {
    static let shared = AnalysisSlot()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async { if busy { await withCheckedContinuation { waiters.append($0) } } else { busy = true } }
    func release() { if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() } }
}

func onThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { c in
        let t = Thread { c.resume(returning: work()) }
        t.qualityOfService = .utility; t.stackSize = 4 << 20; t.start()
    }
}

enum Analyzer {
    static let sceneStep = 0.5
    static let decodeWidth = 512

    /// Fichier que macOS sait lire pour l'analyse : l'original, ou le proxy du lecteur (`Proxies`) pour les formats exotiques.
    static func source(_ info: MediaInfo) async -> URL { await Proxies.playableURL(info) }

    /// Analyse complète. nil si elle est annulée ou impossible. Le résultat est enregistré dans `AnalysisStore`.
    static func run(_ info: MediaInfo, job: AnalysisJob, slot: Bool = true, progress: @escaping @Sendable (AnalysisProgress) -> Void) async -> AnalysisIndex? {
        if slot { await AnalysisSlot.shared.acquire() }
        defer { if slot { Task { await AnalysisSlot.shared.release() } } }
        if job.cancelled { return nil }
        let url = await source(info)
        let t0 = Date()
        let state = ProgressBox(AnalysisProgress(hasVideo: !info.isAudioOnly, hasAudio: info.audio != nil), emit: progress)
        state.update { _ in }

        async let video: VideoResult? = info.isAudioOnly ? nil : onThread { VideoPass.run(url: url, duration: info.duration, job: job, state: state) }
        async let sound: SoundResult? = info.audio == nil ? nil : onThread { SoundPass.run(url: url, duration: info.duration, job: job, state: state) }
        let (v, s) = await (video, sound)
        if job.cancelled { return nil }
        if !info.isAudioOnly, v == nil { return nil }
        if info.audio != nil, !info.isAudioOnly, s == nil, v == nil { return nil }

        var index = AnalysisIndex(duration: info.duration)
        index.hasVideo = v != nil; index.hasAudio = s != nil
        if let v { index.cuts = v.cuts; index.sceneStep = sceneStep; index.sceneLabels = v.labels; index.sceneOffsets = v.offsets; index.sceneLabelIdx = v.labelIdx; index.sceneConf = v.conf }
        if let s { index.soundWindow = s.window; index.soundHop = s.hop; index.soundLabels = s.labels; index.soundStarts = s.starts; index.soundOffsets = s.offsets; index.soundLabelIdx = s.labelIdx; index.soundConf = s.conf }
        index.seconds = Date().timeIntervalSince(t0)
        guard index.hasVideo || index.hasAudio else { return nil }
        AnalysisStore.save(index, for: info)
        return index
    }
}

/// Progression partagée entre les deux passes (verrouillée) ; n'émet qu'environ quatre fois par seconde.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AnalysisProgress
    private var last = Date.distantPast
    private let emit: @Sendable (AnalysisProgress) -> Void
    init(_ v: AnalysisProgress, emit: @escaping @Sendable (AnalysisProgress) -> Void) { value = v; self.emit = emit }
    func update(force: Bool = false, _ change: (inout AnalysisProgress) -> Void) {
        lock.lock(); change(&value)
        let due = force || Date().timeIntervalSince(last) > 0.25
        if due { last = Date(); value.memoryMB = ProcessMemory.footprintMB() }
        let v = value
        lock.unlock()
        if due { emit(v) }
    }
}

// MARK: - Images : plans et scènes

struct VideoResult: Sendable {
    var cuts: [Double]
    var labels: [String]
    var offsets: [Int32]
    var labelIdx: [UInt16]
    var conf: [UInt8]
}

/// Détecteur de coupures franches : miniature de luminance (32×18) et de chrominance (16×9×2) de chaque image, comparée à la précédente.
final class CutDetector {
    static let tw = 32, th = 18
    private var prevY = [UInt8](repeating: 0, count: tw * th), curY = [UInt8](repeating: 0, count: tw * th)
    private var prevC = [UInt8](repeating: 0, count: tw * th / 2), curC = [UInt8](repeating: 0, count: tw * th / 2)
    private var havePrev = false
    private var ring = [Double](repeating: 0, count: 12), ringN = 0
    private(set) var cuts: [(t: Double, score: Double)] = []
    private(set) var scores: [Double] = []
    var keepScores = false

    /// Écart minimal (0…255, pondéré luminance + chrominance) pour qu'un changement soit une coupure, et rapport à l'agitation récente.
    static let minScore = 16.0, ratio = 3.5

    func feed(_ pb: CVPixelBuffer, pts: Double) {
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pb) >= 2, let y = CVPixelBufferGetBaseAddressOfPlane(pb, 0), let c = CVPixelBufferGetBaseAddressOfPlane(pb, 1) else { return }
        let W = CVPixelBufferGetWidthOfPlane(pb, 0), H = CVPixelBufferGetHeightOfPlane(pb, 0)
        let ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), cs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        let cw = W / 2, ch = H / 2
        guard W >= CutDetector.tw * 4, H >= CutDetector.th * 4 else { return }
        let yp = y.assumingMemoryBound(to: UInt8.self), cp = c.assumingMemoryBound(to: UInt8.self)
        let tw = CutDetector.tw, th = CutDetector.th
        // luminance : 4×4 points par case
        for ty in 0 ..< th {
            let y0 = ty * H / th, y1 = max((ty + 1) * H / th, y0 + 1)
            let sy = max((y1 - y0) / 4, 1)
            for tx in 0 ..< tw {
                let x0 = tx * W / tw, x1 = max((tx + 1) * W / tw, x0 + 1)
                let sx = max((x1 - x0) / 4, 1)
                var sum = 0, n = 0, yy = y0
                while yy < y1 { var xx = x0; let row = yp + yy * ys; while xx < x1 { sum += Int(row[xx]); n += 1; xx += sx }; yy += sy }
                curY[ty * tw + tx] = UInt8(sum / max(n, 1))
            }
        }
        // chrominance (Cb et Cr entrelacés) : cases de 2×2 miniatures de luminance, soit 16×9, 2 canaux
        let ctw = tw / 2, cth = th / 2
        for ty in 0 ..< cth {
            let y0 = ty * ch / cth, y1 = max((ty + 1) * ch / cth, y0 + 1)
            let sy = max((y1 - y0) / 4, 1)
            for tx in 0 ..< ctw {
                let x0 = tx * cw / ctw, x1 = max((tx + 1) * cw / ctw, x0 + 1)
                let sx = max((x1 - x0) / 4, 1)
                var sb = 0, sr = 0, n = 0, yy = y0
                while yy < y1 { var xx = x0; let row = cp + yy * cs; while xx < x1 { sb += Int(row[2 * xx]); sr += Int(row[2 * xx + 1]); n += 1; xx += sx }; yy += sy }
                curC[(ty * ctw + tx) * 2] = UInt8(sb / max(n, 1)); curC[(ty * ctw + tx) * 2 + 1] = UInt8(sr / max(n, 1))
            }
        }
        defer { swap(&prevY, &curY); swap(&prevC, &curC); havePrev = true }
        guard havePrev else { return }
        var dy = 0, dc = 0
        for i in 0 ..< curY.count { dy += abs(Int(curY[i]) - Int(prevY[i])) }
        for i in 0 ..< curC.count { dc += abs(Int(curC[i]) - Int(prevC[i])) }
        let score = Double(dy) / Double(curY.count) + 0.5 * Double(dc) / Double(curC.count)
        if keepScores { scores.append(score) }
        // agitation récente : médiane des douze derniers écarts
        let n = min(ringN, ring.count)
        var recent = 0.0
        if n >= 4 { var s = Array(ring[0 ..< n]); s.sort(); recent = s[n / 2] }
        if score > CutDetector.minScore, score > recent * CutDetector.ratio + 6 {
            // deux coupures à moins de 0,15 s : on ne garde que la plus forte (éclair, image parasite)
            if let l = cuts.last, pts - l.t < 0.15 { if score > l.score { cuts[cuts.count - 1] = (pts, score) } } else { cuts.append((pts, score)) }
        } else {
            ring[ringN % ring.count] = score; ringN += 1       // les coupures elles-mêmes ne comptent pas dans l'agitation
        }
    }
}

/// Première piste d'un type, avec sa taille et sa matrice (lues sans l'API synchrone dépréciée).
func loadTrack(_ asset: AVURLAsset, _ type: AVMediaType) -> (AVAssetTrack, CGSize, CGAffineTransform)? {
    final class Box: @unchecked Sendable { var v: (AVAssetTrack, CGSize, CGAffineTransform)? }
    let box = Box(), sem = DispatchSemaphore(value: 0)
    Task {
        if let t = (try? await asset.loadTracks(withMediaType: type))?.first {
            let (size, tf) = (try? await t.load(.naturalSize, .preferredTransform)) ?? (.zero, .identity)
            box.v = (t, size, tf)
        }
        sem.signal()
    }
    sem.wait()
    return box.v
}

/// Empreinte mémoire du processus (celle que mesure l'indicateur « Mémoire » du Moniteur d'activité).
enum ProcessMemory {
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}

enum VideoPass {
    /// Orientation d'affichage d'après la matrice de la piste (vidéos de téléphone).
    static func orientation(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (Int(t.a.rounded()), Int(t.b.rounded()), Int(t.c.rounded()), Int(t.d.rounded())) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        case (-1, 0, 0, 1): return .upMirrored
        default: return .up
        }
    }

    /// `debug` : récupère aussi les écarts image par image (réglage du détecteur, essais).
    static func run(url: URL, duration: Double, job: AnalysisJob, state: ProgressBox, debug: ((CutDetector) -> Void)? = nil) -> VideoResult? {
        let asset = AVURLAsset(url: url)
        guard let (track, natural, transform) = loadTrack(asset, .video) else { return nil }
        let nw = max(abs(natural.width), 16), nh = max(abs(natural.height), 16)
        let w = min(Double(Analyzer.decodeWidth), nw), scale = w / nw
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
        let orient = orientation(transform)

        let detector = CutDetector(); detector.keepScores = debug != nil
        let step = Analyzer.sceneStep
        let results = ClassifyResults()
        let queue = DispatchQueue(label: "fr.stephan.mslice.vision", qos: .utility, attributes: .concurrent)
        let slots = DispatchSemaphore(value: 3)             // au plus trois images en attente : mémoire bornée
        let group = DispatchGroup()
        var nextSample = 0, lastPTS = 0.0

        while let sb = out.copyNextSampleBuffer() {
            if job.cancelled { reader.cancelReading(); break }
            AnalysisGate.shared.wait(job)
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
            guard pts.isFinite else { continue }
            lastPTS = pts
            detector.feed(pb, pts: pts)
            if pts >= Double(nextSample) * step - 0.001 {
                let index = nextSample
                nextSample = max(nextSample + 1, Int((pts / step).rounded(.down)) + 1)      // trou dans la vidéo : on ne rattrape pas
                slots.wait()
                group.enter()
                queue.async {
                    results.set(index, ClassifyResults.classify(pb, orient))
                    slots.signal(); group.leave()
                }
            }
            state.update { $0.images = min(pts / max(duration, 0.1), 1); $0.imagesTime = pts; $0.paused = AnalysisGate.shared.paused }
        }
        group.wait()
        if job.cancelled { return nil }
        if reader.status == .failed, lastPTS < duration * 0.5 { return nil }
        state.update(force: true) { $0.images = 1; $0.imagesTime = duration }
        debug?(detector)
        return results.finish(samples: max(Int((duration / step).rounded(.up)), 1), cuts: detector.cuts.map(\.t))
    }
}

/// Résultats de classification des échantillons d'images (remplis depuis plusieurs fils).
final class ClassifyResults: @unchecked Sendable {
    private let lock = NSLock()
    private var byIndex: [Int: [(label: String, conf: Float)]] = [:]
    func set(_ i: Int, _ r: [(label: String, conf: Float)]) { lock.lock(); byIndex[i] = r; lock.unlock() }

    /// Meilleures étiquettes d'une image : confiance ≥ 0,05, dix au plus.
    static func classify(_ pb: CVPixelBuffer, _ orient: CGImagePropertyOrientation) -> [(label: String, conf: Float)] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: orient, options: [:])
        guard (try? handler.perform([request])) != nil, let obs = request.results else { return [] }
        var top: [(label: String, conf: Float)] = []
        for o in obs where o.confidence >= 0.05 { top.append((o.identifier, o.confidence)); if top.count >= 10 { break } }       // résultats déjà triés
        return top
    }

    func finish(samples: Int, cuts: [Double]) -> VideoResult {
        lock.lock(); defer { lock.unlock() }
        var labels: [String] = [], map: [String: UInt16] = [:]
        var offsets: [Int32] = [0], idx: [UInt16] = [], conf: [UInt8] = []
        let n = max(samples, (byIndex.keys.max() ?? -1) + 1)
        for i in 0 ..< n {
            for e in byIndex[i] ?? [] {
                let k: UInt16
                if let v = map[e.label] { k = v } else { k = UInt16(labels.count); labels.append(e.label); map[e.label] = k }
                idx.append(k); conf.append(UInt8(min(max(e.conf, 0), 1) * 255))
            }
            offsets.append(Int32(idx.count))
        }
        return VideoResult(cuts: cuts, labels: labels, offsets: offsets, labelIdx: idx, conf: conf)
    }
}

// MARK: - Sons

struct SoundResult: Sendable {
    var window: Double, hop: Double
    var labels: [String]
    var starts: [Float]
    var offsets: [Int32]
    var labelIdx: [UInt16]
    var conf: [UInt8]
}

private final class SoundObserver: NSObject, SNResultsObserving {
    var labels: [String] = [], map: [String: UInt16] = [:]
    var starts: [Float] = [], offsets: [Int32] = [0], idx: [UInt16] = [], conf: [UInt8] = []
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        starts.append(Float(r.timeRange.start.seconds))
        for c in r.classifications.prefix(6) where c.confidence >= 0.1 {
            let k: UInt16
            if let v = map[c.identifier] { k = v } else { k = UInt16(labels.count); labels.append(c.identifier); map[c.identifier] = k }
            idx.append(k); conf.append(UInt8(min(max(c.confidence, 0), 1) * 255))
        }
        offsets.append(Int32(idx.count))
    }
    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}

enum SoundPass {
    static let rate = 16000.0
    static let window = 1.5, overlap = 2.0 / 3.0       // fenêtres de 1,5 s, une toutes les 0,5 s

    static func run(url: URL, duration: Double, job: AnalysisJob, state: ProgressBox) -> SoundResult? {
        let t0 = Date()
        let asset = AVURLAsset(url: url)
        guard let (track, _, _) = loadTrack(asset, .audio), let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        out.alwaysCopiesSampleData = false
        guard reader.canAdd(out) else { return nil }
        reader.add(out)
        guard reader.startReading(), let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else { return nil }
        guard let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return nil }
        request.windowDuration = CMTime(seconds: window, preferredTimescale: 48000)
        request.overlapFactor = overlap
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let observer = SoundObserver()
        guard (try? analyzer.add(request, withObserver: observer)) != nil else { return nil }

        var position: AVAudioFramePosition = 0, origin: Double?
        while let sb = out.copyNextSampleBuffer() {
            if job.cancelled { reader.cancelReading(); return nil }
            AnalysisGate.shared.wait(job)
            let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
            let n = CMSampleBufferGetNumSamples(sb)
            guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { continue }
            buf.frameLength = AVAudioFrameCount(n)
            guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(n), into: buf.mutableAudioBufferList) == noErr else { continue }
            if origin == nil, pts.isFinite { origin = pts }
            analyzer.analyze(buf, atAudioFramePosition: position)
            position += AVAudioFramePosition(n)
            state.update { $0.sounds = min((Double(position) / rate) / max(duration, 0.1), 1); $0.paused = AnalysisGate.shared.paused }
        }
        if reader.status == .failed, position == 0 { return nil }
        analyzer.completeAnalysis()
        let shift = Float(origin ?? 0)
        let starts = observer.starts.map { $0 + shift }
        state.update(force: true) { $0.sounds = 1; $0.soundsSeconds = Date().timeIntervalSince(t0) }
        return SoundResult(window: window, hop: window * (1 - overlap), labels: observer.labels, starts: starts, offsets: observer.offsets, labelIdx: observer.idx, conf: observer.conf)
    }
}
