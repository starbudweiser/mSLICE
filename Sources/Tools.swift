// mSLICE — localisation de ffmpeg / ffprobe et lancement de processus (asynchrone, annulable).
import Foundation

enum Tools {
    static let ffmpeg: URL? = locate("ffmpeg")
    static let ffprobe: URL? = locate("ffprobe")

    /// Dans l'appli : Contents/Helpers (embarqué). Pour le développement : MSLICE_FFMPEG_DIR, le build statique de ce projet, puis Homebrew.
    static func locate(_ name: String) -> URL? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let helpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)").path as String? { candidates.append(helpers) }
        if let dir = ProcessInfo.processInfo.environment["MSLICE_FFMPEG_DIR"] { candidates.append("\(dir)/\(name)") }
        candidates += ["\(NSHomeDirectory())/Library/Caches/mSLICE-ffmpeg/out/bin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        return candidates.first(where: { fm.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
}

/// Permet d'interrompre le processus en cours (bouton Annuler, touche Échap).
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var proc: Process?
    private var flag = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func attach(_ p: Process) { lock.lock(); proc = p; let c = flag; lock.unlock(); if c { p.terminate() } }
    func cancel() { lock.lock(); flag = true; let p = proc; lock.unlock(); p?.terminate() }
}

enum Run {
    struct Result { var status: Int32; var err: String }

    /// Lance un exécutable, appelle `onLine` pour chaque ligne de sa sortie standard (progression), renvoie le statut et la fin de sa sortie d'erreur.
    static func exec(_ exe: URL, _ args: [String], cancel: CancelToken? = nil, onLine: (@Sendable (String) -> Void)? = nil) async -> Result {
        await withCheckedContinuation { (cont: CheckedContinuation<Result, Never>) in
            let p = Process(); p.executableURL = exe; p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
            let lock = NSLock()
            var buf = Data(), errData = Data()
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; if d.isEmpty { return }
                var lines: [String] = []
                lock.lock(); buf.append(d)
                while let i = buf.firstIndex(of: 10) { lines.append(String(decoding: buf[buf.startIndex ..< i], as: UTF8.self)); buf.removeSubrange(buf.startIndex ... i) }
                lock.unlock()
                for l in lines { onLine?(l) }
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; if d.isEmpty { return }
                lock.lock(); errData.append(d); if errData.count > 8192 { errData = errData.suffix(8192) }; lock.unlock()
            }
            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
                lock.lock(); let e = String(decoding: errData, as: UTF8.self); lock.unlock()
                cont.resume(returning: Result(status: proc.terminationStatus, err: e))
            }
            do { try p.run(); cancel?.attach(p) } catch { cont.resume(returning: Result(status: -1, err: "\(error)")) }
        }
    }

    /// Version synchrone pour les sondes courtes (ffprobe) : renvoie toute la sortie standard.
    static func data(_ exe: URL, _ args: [String]) -> Data? {
        let p = Process(); p.executableURL = exe; p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? d : nil
    }
}
