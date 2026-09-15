import CoreAI
import Foundation
import Observation
import OSLog
import SwiftUI

@main struct MuralApp: App {
    @State private var store: LearningStore?
    @State private var startupError: String?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let inMemory = arguments.contains("--preview") || AudioVerification.requested || CoreAIModelProbe.requested
        do { _store = State(initialValue: try LearningStore(inMemory: inMemory)) }
        catch { _startupError = State(initialValue: "Mural couldn’t open its learning record. Your existing data has not been replaced.") }
    }

    var body: some Scene {
        WindowGroup {
            if CoreAIModelProbe.requested {
                CoreAIModelProbeView().preferredColorScheme(.light)
            } else if let store {
                RootView(store: store).preferredColorScheme(.light)
            } else {
                ContentUnavailableView("Let’s try again", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError ?? "The learning record is unavailable."))
                    .preferredColorScheme(.light)
            }
        }
    }
}

/// Explicit Core AI loading experiment. It never replaces the production ASR path.
///
/// Launch a Release build with `--coreai-load-probe`. The implementation agent
/// stages an AOT `.aimodelc` in the app container and this probe measures the
/// expensive parts independently of microphone/tutor behavior.
@MainActor @Observable final class CoreAIModelProbe {
    struct Report: Codable, Sendable {
        var date = Date()
        var modelPath: String
        var modelKind: String
        var architecture: String
        var cacheReset: Bool
        var cacheHit: Bool
        var cacheLookupSeconds: Double
        var specializationSeconds: Double
        var functionLoadSeconds: Double
        var totalSeconds: Double
        var functionNames: [String]
        var error: String?
    }

    enum ProbeError: LocalizedError {
        case missingAsset(String)
        case missingMainFunction

        var errorDescription: String? {
            switch self {
            case .missingAsset(let message): message
            case .missingMainFunction: "The Core AI asset has no main inference function."
            }
        }
    }

    static let modelStem = "phowhisper-cs-fp16-v1"
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("--coreai-load-probe")
    }
    static var resetRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--coreai-reset-cache")
    }

    private(set) var running = false
    private(set) var status = "Ready to test"
    private(set) var architecture = AIModel.deviceArchitectureName
    private(set) var modelPath = ""
    private(set) var cacheHit = false
    private(set) var cacheLookupSeconds: Double?
    private(set) var specializationSeconds: Double?
    private(set) var functionLoadSeconds: Double?
    private(set) var totalSeconds: Double?
    private(set) var functionNames: [String] = []
    private(set) var error: String?
    private(set) var reportPath = ""

    @ObservationIgnored private var loadedModel: AIModel?
    @ObservationIgnored private var loadedFunction: InferenceFunction?
    @ObservationIgnored private let logger = Logger(subsystem: "no.william.mural", category: "CoreAIProbe")

    func run(resetCache: Bool = false) async {
        guard !running else { return }
        running = true
        status = "Locating Core AI asset…"
        error = nil
        cacheHit = false
        cacheLookupSeconds = nil
        specializationSeconds = nil
        functionLoadSeconds = nil
        totalSeconds = nil
        functionNames = []
        defer { running = false }

        let totalStarted = ProcessInfo.processInfo.systemUptime
        do {
            let url = try Self.resolveModelURL()
            modelPath = url.path
            architecture = AIModel.deviceArchitectureName
            let cache = AIModelCache.default
            let options = SpecializationOptions.default

            if resetCache {
                // Release any references first. Delete only entries derived from this
                // selected Core AI test asset; never touch Core ML or unrelated models.
                loadedFunction = nil
                loadedModel = nil
                status = "Resetting this Core AI cache entry…"
                try cache.deleteEntries(for: url)
            }

            status = "Checking Core AI specialization cache…"
            let cacheStarted = ProcessInfo.processInfo.systemUptime
            let cached = try cache.model(for: url, options: options)
            cacheLookupSeconds = ProcessInfo.processInfo.systemUptime - cacheStarted
            cacheHit = cached != nil

            let model: AIModel
            if let cached {
                model = cached
                specializationSeconds = 0
                status = "Cached model found. Loading main function…"
            } else {
                status = "Specializing Core AI model…"
                let specializationStarted = ProcessInfo.processInfo.systemUptime
                model = try await AIModel.specialize(
                    contentsOf: url,
                    options: options,
                    cachePolicy: .persistent
                )
                specializationSeconds = ProcessInfo.processInfo.systemUptime - specializationStarted
                status = "Specialized. Loading main function…"
            }

            functionNames = model.functionNames
            let loadStarted = ProcessInfo.processInfo.systemUptime
            guard let function = try model.loadFunction(named: "main") else {
                throw ProbeError.missingMainFunction
            }
            functionLoadSeconds = ProcessInfo.processInfo.systemUptime - loadStarted
            loadedModel = model
            loadedFunction = function
            totalSeconds = ProcessInfo.processInfo.systemUptime - totalStarted
            status = "Core AI model ready"

            logger.notice(
                "coreai_probe_ready cache_hit=\(self.cacheHit, privacy: .public) cache_lookup_seconds=\(self.cacheLookupSeconds ?? -1, privacy: .public) specialization_seconds=\(self.specializationSeconds ?? -1, privacy: .public) function_load_seconds=\(self.functionLoadSeconds ?? -1, privacy: .public) total_seconds=\(self.totalSeconds ?? -1, privacy: .public) architecture=\(self.architecture, privacy: .public)"
            )
            try writeReport(
                url: url,
                resetCache: resetCache,
                error: nil
            )
        } catch {
            self.error = error.localizedDescription
            totalSeconds = ProcessInfo.processInfo.systemUptime - totalStarted
            status = "Core AI probe failed"
            logger.error("coreai_probe_failed total_seconds=\(self.totalSeconds ?? -1, privacy: .public)")
            if let url = try? Self.resolveModelURL() {
                try? writeReport(url: url, resetCache: resetCache, error: error.localizedDescription)
            }
        }
    }

    private func writeReport(url: URL, resetCache: Bool, error: String?) throws {
        let report = Report(
            modelPath: url.path,
            modelKind: url.pathExtension,
            architecture: architecture,
            cacheReset: resetCache,
            cacheHit: cacheHit,
            cacheLookupSeconds: cacheLookupSeconds ?? 0,
            specializationSeconds: specializationSeconds ?? 0,
            functionLoadSeconds: functionLoadSeconds ?? 0,
            totalSeconds: totalSeconds ?? 0,
            functionNames: functionNames,
            error: error
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let destination = URL.documentsDirectory.appending(path: "coreai-load-probe.json")
        try encoder.encode(report).write(to: destination, options: .atomic)
        reportPath = destination.path
    }

    private static func requestedPath() -> URL? {
        let prefix = "--coreai-model-path="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let path = String(argument.dropFirst(prefix.count))
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func resolveModelURL() throws -> URL {
        let fm = FileManager.default
        if let requestedPath = requestedPath() {
            guard fm.fileExists(atPath: requestedPath.path) else {
                throw ProbeError.missingAsset("Requested Core AI model does not exist at \(requestedPath.path)")
            }
            return requestedPath
        }

        let arch = AIModel.deviceArchitectureName
        var roots = [
            URL.applicationSupportDirectory.appending(path: "CoreAI/PhoWhisper", directoryHint: .isDirectory),
            URL.documentsDirectory.appending(path: "CoreAI/PhoWhisper", directoryHint: .isDirectory),
        ]
        if let resources = Bundle.main.resourceURL { roots.append(resources) }

        let names = [
            "\(modelStem).\(arch).aimodelc",
            "\(modelStem).aimodelc",
            "\(modelStem).aimodel",
        ]
        for root in roots {
            for name in names {
                let candidate = root.appending(path: name)
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
        }

        // Be tolerant of a CLI seed changing output naming, but only when there
        // is one unambiguous architecture-matching compiled asset.
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            let matches = entries.filter {
                $0.pathExtension == "aimodelc" && $0.lastPathComponent.contains(arch)
            }
            if matches.count == 1 { return matches[0] }
        }

        throw ProbeError.missingAsset(
            "No Core AI PhoWhisper asset found for architecture \(arch). Stage \(modelStem).\(arch).aimodelc under Application Support/CoreAI/PhoWhisper, Documents/CoreAI/PhoWhisper, the app bundle, or launch with --coreai-model-path=<absolute path>."
        )
    }
}

private struct CoreAIModelProbeView: View {
    @State private var probe = CoreAIModelProbe()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("PhoWhisper Core AI loading gate")
                        .font(.title2.bold())
                    Text("This probe measures model readiness only. It does not replace Mural’s working Core ML ASR or record microphone audio.")
                        .foregroundStyle(.secondary)

                    Group {
                        row("Status", probe.status)
                        row("Architecture", probe.architecture)
                        if !probe.modelPath.isEmpty { row("Asset", probe.modelPath) }
                        row("Cache hit", probe.cacheHit ? "yes" : "no")
                        if let value = probe.cacheLookupSeconds { row("Cache lookup", format(value)) }
                        if let value = probe.specializationSeconds { row("Specialization", format(value)) }
                        if let value = probe.functionLoadSeconds { row("loadFunction", format(value)) }
                        if let value = probe.totalSeconds { row("Total ready", format(value)) }
                        if !probe.functionNames.isEmpty { row("Functions", probe.functionNames.joined(separator: ", ")) }
                        if !probe.reportPath.isEmpty { row("Report", probe.reportPath) }
                    }

                    if let error = probe.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }

                    Button(probe.running ? "Working…" : "Run load probe") {
                        Task { await probe.run() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(probe.running)

                    Button("Reset only this model cache & run") {
                        Task { await probe.run(resetCache: true) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(probe.running)

                    Text("Use cache reset only for controlled cold Core AI trials. AOT compilation should be done on the Mac before staging the architecture-specific .aimodelc on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("Core AI Probe")
        }
        .task {
            await probe.run(resetCache: CoreAIModelProbe.resetRequested)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
    }

    private func format(_ seconds: Double) -> String {
        String(format: "%.3f s", seconds)
    }
}
