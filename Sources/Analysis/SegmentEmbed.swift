// mSLICE — empreintes de voix par SEGMENT (une réplique, une prise de parole) au lieu d'une grille fixe : les fenêtres restent à l'intérieur du segment, donc ne
// mélangent jamais la voix d'un autre locuteur voisin ; un segment plus court qu'une fenêtre (1,515 s) est répété bout à bout pour remplir la fenêtre du modèle.
import AVFoundation
import Foundation

enum AudioSamples {
    /// Tout le son d'un fichier en mono 16 kHz (−1…1), `from`…`to` en secondes (nil : tout). nil si illisible.
    static func load(url: URL, from: Double? = nil, to: Double? = nil) -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let (track, _, _) = loadTrack(asset, .audio), let reader = try? AVAssetReader(asset: asset) else { return nil }
        if let from, let to, to > from { reader.timeRange = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600), duration: CMTime(seconds: to - from, preferredTimescale: 600)) }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: VoiceFeatures.rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        out.alwaysCopiesSampleData = false
        guard reader.canAdd(out) else { return nil }
        reader.add(out)
        guard reader.startReading() else { return nil }
        var buf: [Float] = []
        while let sb = out.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
            var length = 0; var ptr: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr) == kCMBlockBufferNoErr, let p = ptr else { continue }
            let n = length / 4
            p.withMemoryRebound(to: Float.self, capacity: n) { buf.append(contentsOf: UnsafeBufferPointer(start: $0, count: n)) }
        }
        return buf
    }
}

enum SegmentEmbedding {
    /// Les empreintes d'un segment [start, end] (s) d'un son 16 kHz : des fenêtres de 1,515 s toutes les `hop` secondes à l'intérieur du segment (la dernière calée sur la fin),
    /// ou une seule fenêtre faite du segment répété s'il est plus court. Chaque empreinte est rendue avec l'instant du centre de sa fenêtre.
    static func embed(_ x: [Float], base: Int = 0, start: Double, end: Double, hop: Double = 0.5, embedder: VoiceEmbedder) -> [(t: Double, v: [Float])] {
        let rate = VoiceFeatures.rate, win = VoiceFeatures.windowSamples
        let a = max(Int(start * rate) - base, 0), b = min(Int(end * rate) - base, x.count)
        guard b - a >= Int(0.25 * rate) else { return [] }
        var out: [(Double, [Float])] = []
        if b - a >= win {
            var s = a
            let step = max(Int(hop * rate), 1)
            while true {
                let e = min(s + win, b)
                let from = e - win
                if let v = x.withUnsafeBufferPointer({ embedder.embed(UnsafeBufferPointer(rebasing: $0[from ..< from + win])) }) { out.append((Double(from + base + win / 2) / rate, v)) }
                if e >= b { break }
                s += step
            }
        } else {
            var tiled = [Float](); tiled.reserveCapacity(win)
            var k = 0
            while tiled.count < win {
                // fondu croisé très court aux jonctions pour ne pas créer de claquement
                tiled.append(x[a + k % (b - a)]); k += 1
            }
            if let v = tiled.withUnsafeBufferPointer({ embedder.embed($0) }) { out.append((Double(a + base + (b - a) / 2) / rate, v)) }
        }
        return out
    }

    /// Les empreintes de plusieurs segments en UNE passe de lecture (mémoire bornée : on ne garde que le son utile aux segments restants). `ranges` en secondes, rendu dans le même ordre.
    /// nil si le son est illisible ou si le travail est annulé.
    static func embedRanges(url: URL, ranges: [(start: Double, end: Double)], hop: Double = 0.5, embedder: VoiceEmbedder, job: AnalysisJob? = nil) -> [[(t: Double, v: [Float])]]? {
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
        let rate = VoiceFeatures.rate
        var result = [[(t: Double, v: [Float])]](repeating: [], count: ranges.count)
        let order = ranges.indices.sorted { ranges[$0].end < ranges[$1].end }
        var next = 0
        var buf: [Float] = [], base = 0, origin: Double?
        func flush(final: Bool) {
            while next < order.count {
                let r = ranges[order[next]], o = origin ?? 0
                let endIdx = Int((r.end - o) * rate)
                if !final, base + buf.count < endIdx + Int(0.05 * rate) { break }
                result[order[next]] = embed(buf, base: base, start: r.start - o, end: r.end - o, hop: hop, embedder: embedder).map { ($0.t + o, $0.v) }
                next += 1
            }
            // on jette ce que les segments restants n'utiliseront plus
            if next < order.count {
                let minStart = order[next...].map { ranges[$0].start }.min() ?? 0
                let drop = min(max(Int((minStart - (origin ?? 0)) * rate) - base - Int(rate), 0), buf.count)
                if drop > 0 { buf.removeFirst(drop); base += drop }
            }
        }
        while let sb = out.copyNextSampleBuffer() {
            if job?.cancelled == true { reader.cancelReading(); return nil }
            if origin == nil { let p = CMSampleBufferGetPresentationTimeStamp(sb).seconds; if p.isFinite { origin = p } }
            guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
            var length = 0; var ptr: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr) == kCMBlockBufferNoErr, let p = ptr else { continue }
            let n = length / 4
            p.withMemoryRebound(to: Float.self, capacity: n) { buf.append(contentsOf: UnsafeBufferPointer(start: $0, count: n)) }
            flush(final: false)
        }
        flush(final: true)
        return result
    }
}
