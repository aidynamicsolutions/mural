import Foundation

/// Test-build-only selection between two independently pinned artifacts.
/// This is not a user model picker, pin override, or runtime downloader.
enum BreezeTrialSelection {
    enum Variant: String, Equatable { case pal8, pal4 }
    struct InvalidSelection: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static var enabled: Bool {
        #if MURAL_BREEZE_PAL4_TRIAL
        return true
        #else
        return false
        #endif
    }
    static func parse(_ arguments: [String], enabled: Bool) throws -> Variant {
        let flags = arguments.filter { $0.hasPrefix("--breeze-trial") }
        guard flags.isEmpty || enabled else {
            throw InvalidSelection(message: "Breeze trials are disabled in this build.")
        }
        guard flags.count <= 1 else {
            throw InvalidSelection(message: "Specify exactly one Breeze trial arm.")
        }
        guard let flag = flags.first else { return .pal8 }
        switch flag {
        case "--breeze-trial=pal8": return .pal8
        case "--breeze-trial=pal4": return .pal4
        default: throw InvalidSelection(message: "Use --breeze-trial=pal8 or --breeze-trial=pal4.")
        }
    }
    /// Reject extra models and links without mistaking Apple's /var alias for a package path.
    static func verifyInventory(at folder: URL, allowed: Set<String>) throws {
        // Root/ancestor symlinks are checked by the caller before canonicalizing
        // Apple's trusted sandbox prefix. Entries themselves must still be regular files.
        let canonicalFolder = folder.resolvingSymlinksInPath()
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: canonicalFolder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw InvalidSelection(message: "Cannot inspect the PAL4 trial inventory.")
        }
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw InvalidSelection(message: "PAL4 trial inventory contains a symbolic link.")
            }
            if values.isRegularFile == true {
                let components = url.resolvingSymlinksInPath().pathComponents
                guard components.starts(with: canonicalFolder.pathComponents) else {
                    throw InvalidSelection(message: "PAL4 inventory escaped its root.")
                }
                let relative = components.dropFirst(canonicalFolder.pathComponents.count).joined(separator: "/")
                guard allowed.contains(relative) else {
                    throw InvalidSelection(message: "Unpinned file in PAL4 trial inventory.")
                }
            }
        }
        if let enumerationError { throw enumerationError }
    }

    // Diagnostic identity only. Asset resolution always calls the throwing parser.
    static var requestsPAL4: Bool {
        enabled && ProcessInfo.processInfo.arguments.contains("--breeze-trial=pal4")
    }
}
