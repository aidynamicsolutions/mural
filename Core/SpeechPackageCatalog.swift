import Foundation

public enum SpeechPackageCatalog {
    /// No public artifact URL + independently reviewed whole-package pin was supplied.
    /// Populate with Tools/ASR/make_speech_package.py output only after hosting and review.
    /// Do not accept a pin from a launch argument, remote catalog, or the same download.
    /// Newest reviewed version first per pair. Keep prior trusted entries so an app update
    /// can use the old active version until its replacement is verified and activated.
    public static let entries: [ReviewedSpeechPackage] = []

    public static func entry(for pair: LocalSpeechPair) throws -> ReviewedSpeechPackage {
        guard let selected = entries.first(where: { $0.pair == pair }) else { throw SpeechPackageError.notPublished }
        guard Set(entries.map { $0.id }).count == entries.count else { throw SpeechPackageError.invalidManifest }
        for entry in entries { try entry.validate() }
        return selected
    }
}
