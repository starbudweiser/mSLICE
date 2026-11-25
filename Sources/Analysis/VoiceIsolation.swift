// mSLICE — voix seule : l'isolation de la voix de macOS (AudioUnit `AUSoundIsolation`, celle de Final Cut Pro) en rendu hors ligne (`AVAudioEngine` en mode
// manuel). Rien à télécharger ; mesuré 45× le temps réel, musique seule −14 → −66 dB. Sans interface : partagé avec `mslice-mcp`.
import AVFoundation
import AudioToolbox
import Foundation

enum VoiceIsolation {
    static let description = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: 0x766F6973 /* « vois » */,
                                                       componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
    /// L'isolation de voix existe-t-elle sur ce Mac ?
    static var available: Bool { var d = description; return AudioComponentFindNext(nil, &d) != nil }

    /// Isole la voix d'un fichier audio (mono, 48 kHz de préférence) vers un WAV ; progression 0…1, annulable. Vrai si le fichier est écrit.
    static func run(input: URL, output: URL, job: AnalysisJob, progress: @escaping @Sendable (Double) -> Void) async -> Bool {
        let au: AVAudioUnit? = await withCheckedContinuation { c in AVAudioUnit.instantiate(with: description, options: []) { u, _ in c.resume(returning: u) } }
        guard let au else { return false }
        return await onThread { render(au, input: input, output: output, job: job, progress: progress) }
    }

    private static func render(_ au: AVAudioUnit, input: URL, output: URL, job: AnalysisJob, progress: @Sendable (Double) -> Void) -> Bool {
        guard let file = try? AVAudioFile(forReading: input), file.length > 0 else { return false }
        let format = file.processingFormat
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        engine.attach(player); engine.attach(au)
        if let tree = au.auAudioUnit.parameterTree {
            tree.parameter(withAddress: 0)?.value = 100          // mélange : 100 %
            tree.parameter(withAddress: 1)?.value = 1            // son à isoler : voix
        }
        engine.connect(player, to: au, format: format)
        engine.connect(au, to: engine.mainMixerNode, format: format)
        let chunk: AVAudioFrameCount = 8192
        do { try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunk) } catch { return false }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunk) else { return false }
        let total = file.length
        do {
            try engine.start()
            player.scheduleFile(file, at: nil)
            player.play()
            try? FileManager.default.removeItem(at: output)
            let out = try AVAudioFile(forWriting: output, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount,
                                                                     AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
            var done: AVAudioFramePosition = 0
            while done < total {
                if job.cancelled { engine.stop(); return false }
                let n = AVAudioFrameCount(min(AVAudioFramePosition(chunk), total - done))
                let status = try engine.renderOffline(n, to: buffer)
                if status == .error { engine.stop(); return false }
                if status == .success || status == .insufficientDataFromInputNode, buffer.frameLength > 0 { try out.write(from: buffer) }
                done += AVAudioFramePosition(n)
                progress(min(Double(done) / Double(total), 1))
            }
            engine.stop()
            return true
        } catch { engine.stop(); return false }
    }
}
