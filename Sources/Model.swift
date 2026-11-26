// mSLICE — morceaux, formats de sortie, options d'export.
import Foundation

/// Un morceau à garder : entrée et sortie en secondes dans le fichier d'origine.
struct Segment: Identifiable, Equatable, Codable {
    var id = UUID()
    var start: Double
    var end: Double
    var who: String? = nil           // protagoniste d'où vient le morceau (id « p3 » / « v2 ») : sa couleur ; nil : morceau posé à la main
    var name: String? = nil          // nom du fichier exporté, choisi par l'utilisateur (sans extension) ; nil : nom automatique numéroté
    var duration: Double { end - start }
}

/// Formats de sortie proposés (« Identique » = même conteneur que l'original).
enum OutFormat: String, CaseIterable, Codable {
    case same, mp4, mov, mkv, webm, mp3, m4a, wav, flac, aiff, opus
    var isAudio: Bool { [.mp3, .m4a, .wav, .flac, .aiff, .opus].contains(self) }
    var title: String {
        switch self { case .same: L.t("fmt.same"); case .opus: "Opus"; case .webm: "WebM"; default: rawValue.uppercased() }
    }
    /// Extension du fichier produit ; `.same` reprend celle de l'original.
    func ext(source: String) -> String { self == .same ? source : (self == .opus ? "opus" : rawValue) }
    static let video: [OutFormat] = [.mp4, .mov, .mkv, .webm]
    static let audio: [OutFormat] = [.mp3, .m4a, .wav, .flac, .aiff, .opus]
}

enum VideoCodec: String, CaseIterable, Codable {
    case h264, hevc, prores, vp9
    var title: String { switch self { case .h264: "H.264"; case .hevc: "H.265"; case .prores: "ProRes"; case .vp9: "VP9" } }
}

enum Quality: String, CaseIterable, Codable {
    case high, medium, low
    var factor: Double { switch self { case .high: 1.0; case .medium: 0.6; case .low: 0.35 } }
    var title: String { L.t("quality." + rawValue) }
}

struct ExportOptions: Codable, Equatable {
    var merge = false                     // un seul fichier fusionné, sinon un fichier par morceau (numérotés)
    var passthrough = true                // copie directe des flux, sans recompression
    var format: OutFormat = .same
    var codec: VideoCodec = .h264
    var quality: Quality = .high
    var folder: String? = nil             // nil : même dossier que l'original
    var suffix = "extrait"                // nom du fichier fusionné : <nom>_<suffixe>
    var digits = 2                        // numérotation : _01, _02…
    var voiceOnly = false                 // « voix seules » : l'audio exporté est la piste nettoyée (`CleanVoice`) ; jamais mémorisé d'un lancement à l'autre

    var trimSilence = false               // « blancs retirés » : silences resserrés autour des morceaux (et à l'intérieur dans un fichier fusionné) ; jamais mémorisé

    private enum CodingKeys: String, CodingKey { case merge, passthrough, format, codec, quality, folder, suffix, digits }

    /// Format effectif quand on recompresse : « Identique » devient MP4 (ou M4A pour un fichier audio).
    /// Avec « voix seules », l'audio est toujours réencodé : un audio seul d'un format inconnu (wma, ac3…) sort en M4A.
    func resolvedFormat(for info: MediaInfo) -> OutFormat {
        if voiceOnly, format == .same, info.isAudioOnly, OutFormat(rawValue: info.ext.lowercased()) == nil { return .m4a }
        if format != .same || passthrough { return format }
        return info.isAudioOnly ? .m4a : .mp4
    }
}

/// Un fichier à produire : sa destination, les morceaux qui le composent et sa durée attendue.
struct OutputItem {
    var url: URL
    var segments: [Segment]
    var expected: Double
}
