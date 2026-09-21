import SwiftUI
import FluidAudio
import AVFoundation
import Combine
import OSLog
import UniformTypeIdentifiers
import MuralCore

enum OnDeviceSpeechVoiceCatalog {
    static let preferenceKey = "localTTSVoiceIdentifier"
    static let fallbackLanguage = "en-US"
    private static let logger = Logger(subsystem: "no.william.mural", category: "LocalTTS")

    struct Option: Identifiable, Hashable {
        let id: String
        let name: String
        let systemName: String
        let language: String
        let localeName: String
        let qualityLabel: String
        let qualityRank: Int

        var label: String { "\(name) · \(qualityLabel)" }
        var summary: String { "\(name) · \(qualityLabel) · \(localeName)" }
        var isPremium: Bool { qualityRank == 3 }
        var searchText: String { "\(name) \(systemName) \(language) \(localeName) \(qualityLabel)" }
    }

    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter(isEligible)
            .sorted { lhs, rhs in
                if lhs.language != rhs.language {
                    if lhs.language == fallbackLanguage { return true }
                    if rhs.language == fallbackLanguage { return false }
                    let leftLocale = localeName(for: lhs.language)
                    let rightLocale = localeName(for: rhs.language)
                    let localeOrder = leftLocale.localizedCaseInsensitiveCompare(rightLocale)
                    if localeOrder != .orderedSame { return localeOrder == .orderedAscending }
                    return lhs.language < rhs.language
                }
                let leftRank = qualityRank(lhs.quality)
                let rightRank = qualityRank(rhs.quality)
                if leftRank != rightRank { return leftRank > rightRank }
                let nameOrder = displayName(lhs.name).localizedCaseInsensitiveCompare(displayName(rhs.name))
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return lhs.identifier < rhs.identifier
            }
    }

    static func availableOptions() -> [Option] {
        availableVoices().map { voice in
            Option(id: voice.identifier, name: displayName(voice.name), systemName: voice.name,
                   language: voice.language, localeName: localeName(for: voice.language),
                   qualityLabel: qualityLabel(voice.quality), qualityRank: qualityRank(voice.quality))
        }
    }

    static func bestAvailableOption(from options: [Option]) -> Option? {
        let region = deviceRegionCode
        return options.sorted { lhs, rhs in
            if lhs.qualityRank != rhs.qualityRank { return lhs.qualityRank > rhs.qualityRank }
            let leftMatchesRegion = region != nil && regionCode(for: lhs.language) == region
            let rightMatchesRegion = region != nil && regionCode(for: rhs.language) == region
            if leftMatchesRegion != rightMatchesRegion { return leftMatchesRegion }
            let localeOrder = lhs.localeName.localizedCaseInsensitiveCompare(rhs.localeName)
            if localeOrder != .orderedSame { return localeOrder == .orderedAscending }
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.id < rhs.id
        }.first
    }

    static func resolvedVoice() -> AVSpeechSynthesisVoice? {
        if let identifier = UserDefaults.standard.string(forKey: preferenceKey),
           !identifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: identifier),
           isEligible(voice) {
            logSelection(voice, mode: "explicit")
            return voice
        }
        let voices = availableVoices()
        let voice = bestAvailableVoice(from: voices)
            ?? deviceRegionCode.flatMap { AVSpeechSynthesisVoice(language: "en-\($0)") }
            ?? AVSpeechSynthesisVoice(language: fallbackLanguage)
        if let voice { logSelection(voice, mode: "best-available") }
        return voice
    }

    static func description(for voice: AVSpeechSynthesisVoice) -> String {
        "\(displayName(voice.name)) (\(voice.language)) · \(qualityLabel(voice.quality))"
    }

    static func localeName(for identifier: String) -> String {
        let locale = Locale(identifier: identifier)
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        let languageName = Locale.current.localizedString(forLanguageCode: languageCode) ?? "English"
        if let regionCode = locale.region?.identifier,
           let regionName = Locale.current.localizedString(forRegionCode: regionCode) {
            return "\(languageName) (\(regionName))"
        }
        return languageName
    }

    static func logEnglishCatalog() {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter(isEnglish)
        logger.notice("voice_catalog_begin count=\(voices.count, privacy: .public) device_region=\(deviceRegionCode ?? "none", privacy: .public)")
        for voice in voices.sorted(by: { $0.identifier < $1.identifier }) {
            var traits: [String] = []
            if voice.voiceTraits.contains(.isNoveltyVoice) { traits.append("novelty") }
            if voice.voiceTraits.contains(.isPersonalVoice) { traits.append("personal") }
            if traits.isEmpty { traits.append("regular") }
            let traitText = traits.joined(separator: ",")
            logger.notice("voice_catalog name=\(voice.name, privacy: .public) identifier=\(voice.identifier, privacy: .public) language=\(voice.language, privacy: .public) quality=\(qualityLabel(voice.quality), privacy: .public) traits=\(traitText, privacy: .public)")
        }
        logger.notice("voice_catalog_end")
    }

    private static var deviceRegionCode: String? {
        Locale.autoupdatingCurrent.region?.identifier
    }

    private static func regionCode(for language: String) -> String? {
        Locale(identifier: language).region?.identifier
    }

    private static func bestAvailableVoice(from voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        let region = deviceRegionCode
        return voices.sorted { lhs, rhs in
            let leftRank = qualityRank(lhs.quality)
            let rightRank = qualityRank(rhs.quality)
            if leftRank != rightRank { return leftRank > rightRank }
            let leftMatchesRegion = region != nil && regionCode(for: lhs.language) == region
            let rightMatchesRegion = region != nil && regionCode(for: rhs.language) == region
            if leftMatchesRegion != rightMatchesRegion { return leftMatchesRegion }
            let leftLocale = localeName(for: lhs.language)
            let rightLocale = localeName(for: rhs.language)
            let localeOrder = leftLocale.localizedCaseInsensitiveCompare(rightLocale)
            if localeOrder != .orderedSame { return localeOrder == .orderedAscending }
            let nameOrder = displayName(lhs.name).localizedCaseInsensitiveCompare(displayName(rhs.name))
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.identifier < rhs.identifier
        }.first
    }

    private static func logSelection(_ voice: AVSpeechSynthesisVoice, mode: String) {
        logger.notice("tts_voice_selected mode=\(mode, privacy: .public) name=\(voice.name, privacy: .public) identifier=\(voice.identifier, privacy: .public) language=\(voice.language, privacy: .public) quality=\(qualityLabel(voice.quality), privacy: .public) device_region=\(deviceRegionCode ?? "none", privacy: .public)")
    }

    private static func isEnglish(_ voice: AVSpeechSynthesisVoice) -> Bool {
        Locale(identifier: voice.language).language.languageCode?.identifier == "en"
    }

    private static func isEligible(_ voice: AVSpeechSynthesisVoice) -> Bool {
        isEnglish(voice) &&
        !voice.voiceTraits.contains(.isNoveltyVoice) &&
        !voice.voiceTraits.contains(.isPersonalVoice)
    }

    private static func displayName(_ name: String) -> String {
        for suffix in [" (Premium)", " (Enhanced)"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    private static func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        if quality == .premium { return 3 }
        if quality == .enhanced { return 2 }
        return 1
    }

    private static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        if quality == .premium { return "Premium" }
        if quality == .enhanced { return "Enhanced" }
        return "Standard"
    }
}

// LocalConversationEngine.swift already refers to an unqualified LocalSpeechVoice.
// A nested type declared in an extension participates in that type's name lookup,
// so this safely layers the regional resolver over the existing engine without
// touching the Core AI / ASR implementation in that large source file.
extension LocalConversationEngine {
    enum LocalSpeechVoice {
        static func resolvedVoice() -> AVSpeechSynthesisVoice? {
            OnDeviceSpeechVoiceCatalog.resolvedVoice()
        }

        static func description(for voice: AVSpeechSynthesisVoice) -> String {
            OnDeviceSpeechVoiceCatalog.description(for: voice)
        }
    }
}

struct ThemesView: View {
    let coordinator: ConversationCoordinator
    let choose: (ConversationTheme?) -> Void
    @State private var search = ""
    @State private var category = "All"
    @State private var current = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var themes: [ConversationTheme] {
        coordinator.language.themes.filter { (category == "All" || $0.category == category) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search)) }
    }
    private var categories: [String] { coordinator.language.themes.map(\.category).reduce(into: ["All"]) { if !$0.contains($1) { $0.append($1) } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if coordinator.isLocal { Text("Themes and topic search are unavailable in On-device mode. Use Talk to record a turn.").font(.footnote) }
                PageHeading(eyebrow: "A place to begin", title: "What’s on\nyour mind?", subtitle: "Same friend. Somewhere new.")
                Button { choose(nil) } label: {
                    HStack { Image(systemName: "waveform"); Text("Just talk"); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.headline).padding(22).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 26))
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { c in
                            Button(c) { category = c }.font(.caption).padding(.horizontal, 15).padding(.vertical, 11)
                                .background(category == c ? MuralColor.peach : .white.opacity(0.65), in: Capsule())
                                .accessibilityAddTraits(category == c ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 150), spacing: 12)], spacing: 12) {
                    ForEach(themes) { theme in
                        Button { if theme.id == "today" { current = true } else { choose(theme) } } label: {
                            VStack(alignment: .leading, spacing: 28) {
                                Image(systemName: theme.symbol).font(.system(size: 28, weight: .light)).foregroundStyle(MuralColor.secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(theme.title).font(.system(.headline, design: .rounded))
                                    Text(theme.subtitle).font(.caption).foregroundStyle(MuralColor.secondary)
                                }
                            }.frame(maxWidth: .infinity, minHeight: 142, alignment: .leading).padding(19)
                                .background(MuralColor.panels[theme.colorIndex], in: RoundedRectangle(cornerRadius: 27))
                        }.buttonStyle(.plain)
                    }
                }
                if themes.isEmpty { ContentUnavailableView.search(text: search) }
            }.padding(24)
        }.foregroundStyle(MuralColor.ink)
            .disabled(coordinator.isLocal)
            .searchable(text: $search, prompt: "Find a conversation")
            .sheet(isPresented: $current) { CurrentTopicView(coordinator: coordinator) { choose(coordinator.selectedTheme) } }
            .onChange(of: coordinator.mode) { current = false; search = "" }
    }
}

struct CurrentTopicView: View {
    let coordinator: ConversationCoordinator
    let selected: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var brief: TopicBrief?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeading(eyebrow: "The world today", title: "A fresh conversation.", subtitle: "What would you like to talk about?")
                    TextField(coordinator.language.topicPlaceholder, text: $query, axis: .vertical).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    Button { find() } label: {
                        HStack { Text(loading ? "Finding something interesting…" : "Find a topic"); Spacer(); if loading { ProgressView() } else { Image(systemName: "sparkle.magnifyingglass") } }.padding(18).background(MuralColor.peach, in: Capsule())
                    }.disabled(loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let error { Text(error).font(.footnote).foregroundStyle(MuralColor.secondary) }
                    if let brief {
                        Text(.init(brief.text)).font(.body).textSelection(.enabled)
                        SourcesView(sources: brief.sources, date: brief.retrievedAt)
                        Button("Talk about this", systemImage: "waveform") { coordinator.discuss(brief); selected(); dismiss() }
                            .font(.headline).padding(18).frame(maxWidth: .infinity).background(MuralColor.orange, in: Capsule())
                    }
                    Text("Search uses your OpenAI API account. Sources stay attached to the topic.").font(.footnote).foregroundStyle(MuralColor.secondary)
                }.padding(26)
            }.background(MuralColor.cream).foregroundStyle(MuralColor.ink)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
    private func find() {
        loading = true; error = nil
        Task { do { brief = try await coordinator.currentTopic(query) } catch { self.error = error.localizedDescription }; loading = false }
    }
}

struct WordsView: View {
    let coordinator: ConversationCoordinator
    @State private var search = ""
    @State private var selected: WordState?
    @State private var sessions = false
    private var learner: LearnerState { coordinator.store.learner }
    private var words: [WordState] { learner.words.filter { search.isEmpty || $0.lemma.localizedCaseInsensitiveContains(search) || $0.meaning.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Little by little · \(coordinator.language.name)", title: "Your words.", subtitle: "Familiar words, ready for another conversation.")
                if coordinator.isLocal {
                    Text(coordinator.localAssessmentRunning ? "Reviewing your last reply on this iPhone…" : "On-device practice reviews only your last reply after you tap End, saving up to two English words or phrases when the evidence is clear.")
                        .font(.footnote).foregroundStyle(MuralColor.secondary)
                }
                if words.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "leaf").font(.system(size: 34, weight: .light))
                        Text(search.isEmpty ? "They’ll grow from here." : "No matching words yet.").font(.system(.title2, design: .rounded, weight: .medium))
                        Text(search.isEmpty ? "As we talk, useful words and phrases find a home here. Their strength grows when you recall them over time." : "Try another \(coordinator.language.name) word or English meaning.").font(.subheadline).foregroundStyle(MuralColor.secondary)
                    }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(MuralColor.sage, in: RoundedRectangle(cornerRadius: 28))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(words) { word in
                            Button { selected = word } label: {
                                HStack(spacing: 18) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(word.lemma).font(.system(.title2, design: .rounded, weight: .medium))
                                        Text(word.meaning).font(.subheadline).foregroundStyle(MuralColor.secondary)
                                    }
                                    Spacer(minLength: 10)
                                    VStack(alignment: .trailing, spacing: 8) { RecallBars(count: word.bars); Text(word.label).font(.caption2).foregroundStyle(MuralColor.secondary) }
                                }.padding(.vertical, 20)
                            }.buttonStyle(.plain)
                            Divider().overlay(MuralColor.peach)
                        }
                    }
                }
                HStack { Text("1 · Fragile"); Spacer(); Text("2 · Growing"); Spacer(); Text("3 · Steady") }.font(.caption).foregroundStyle(MuralColor.secondary)
                Text("The bars estimate spoken recall, not permanent mastery. Using a word with visible meanings counts as supported practice.").font(.footnote).foregroundStyle(MuralColor.secondary)
                if !learner.capabilities.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Finding your voice").font(.system(.title3, design: .rounded, weight: .semibold))
                        ForEach(learner.capabilities, id: \.self) { Text($0).font(.subheadline) }
                        Text("Observed across conversations. These are provisional, not formal level certificates.").font(.footnote).foregroundStyle(MuralColor.secondary)
                    }.padding(22).background(MuralColor.butter, in: RoundedRectangle(cornerRadius: 24))
                }
                Button("Past conversations", systemImage: "clock.arrow.circlepath") { sessions = true }.font(.subheadline).padding(.vertical, 8)
            }.padding(26)
        }.foregroundStyle(MuralColor.ink).searchable(text: $search, prompt: "Find a word")
            .sheet(item: $selected) { word in WordDetailView(word: word, store: coordinator.store) }
            .sheet(isPresented: $sessions) { SessionHistoryView(store: coordinator.store) }
    }
}

struct WordDetailView: View {
    let word: WordState
    let store: LearningStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text(word.lemma).font(.system(.largeTitle, design: .rounded, weight: .medium))
                Text(word.meaning).font(.title3).foregroundStyle(MuralColor.secondary)
                HStack { RecallBars(count: word.bars); Text(word.label).font(.subheadline) }
                Text(word.explanation).font(.body)
                Text("“\(word.example)”").font(.system(.title3, design: .rounded)).padding(20).frame(maxWidth: .infinity, alignment: .leading).background(MuralColor.peach, in: RoundedRectangle(cornerRadius: 22))
                Text("\(word.independentCount) independent uses · Last seen \(word.lastSeen.formatted(date: .abbreviated, time: .omitted))").font(.footnote).foregroundStyle(MuralColor.secondary)
                Button("Remove from my words", role: .destructive) { store.hideWord(word.id); dismiss() }.font(.footnote)
                Spacer()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(MuralColor.cream).foregroundStyle(MuralColor.ink)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

struct SourcesView: View {
    var sources: [SourceLink]
    var date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources · \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(MuralColor.secondary)
            ForEach(sources) { source in if let url = source.safeURL { Link(destination: url) { Label(source.title, systemImage: "arrow.up.right").font(.subheadline) } } }
        }
    }
}

struct TranscriptView: View {
    let session: SessionRecord?
    var meaningLanguage = "English"
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let session {
                        ForEach(session.passages) { passage in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(passage.speaker == .assistant ? "MURAL" : "YOU").font(.caption).tracking(1).foregroundStyle(MuralColor.secondary)
                                Text(passage.text).font(.system(.title3, design: .rounded)).textSelection(.enabled)
                                if passage.fragments.contains(where: { $0.playbackCompleted == false }) {
                                    Text("Playback not completed").font(.caption).foregroundStyle(MuralColor.secondary)
                                }
                                if let translation = session.translations[MeaningRequest.cacheKey(revisionKey: passage.revisionKey, language: meaningLanguage)] ?? session.translations[passage.revisionKey] {
                                    Text(translation).font(.subheadline).foregroundStyle(MuralColor.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(session.topics) { topic in Text(.init(topic.text)); SourcesView(sources: topic.sources, date: topic.retrievedAt) }
                        if session.fragments.isEmpty && session.topics.isEmpty { Text("Your conversation will appear here.").foregroundStyle(MuralColor.secondary) }
                    } else { Text("Start a conversation and your words will appear here.") }
                }.padding(26)
            }.background(MuralColor.cream).foregroundStyle(MuralColor.ink)
                .navigationTitle("Our conversation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct SessionHistoryView: View {
    let store: LearningStore
    @State private var selected: SessionRecord?
    @State private var deleting: SessionRecord?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if store.learningSessions.isEmpty { Text("Your \(store.language.name) conversations will appear here.").foregroundStyle(MuralColor.secondary) }
                ForEach(store.learningSessions) { session in
                    Button { selected = session } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.title).font(.headline)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(MuralColor.secondary)
                        }.padding(.vertical, 8)
                    }.swipeActions { Button("Delete", role: .destructive) { deleting = session }.disabled(session.endedAt == nil) }
                }
            }.scrollContentBackground(.hidden).background(MuralColor.cream)
                .navigationTitle("Past conversations").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.sheet(item: $selected) { session in EditableTranscriptView(sessionID: session.id, store: store) }
            .confirmationDialog("Delete this conversation and its learning evidence?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete conversation", role: .destructive) { if let deleting { store.deleteSession(deleting.id) }; deleting = nil }
            }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct EditableTranscriptView: View {
    let sessionID: UUID
    let store: LearningStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: String?
    @State private var editedText = ""
    private var session: SessionRecord? { store.sessions.first { $0.id == sessionID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(session?.passages ?? []) { passage in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(passage.speaker == .user ? "YOU" : "MURAL").font(.caption).tracking(1)
                                Spacer()
                                if passage.speaker == .user && session?.endedAt != nil {
                                    Button("Edit") { editedText = passage.text; editingID = passage.id }.font(.caption)
                                }
                            }.foregroundStyle(MuralColor.secondary)
                            Text(passage.text).font(.system(.title3, design: .rounded)).textSelection(.enabled)
                            if passage.fragments.contains(where: { $0.playbackCompleted == false }) {
                                Text("Playback not completed").font(.caption).foregroundStyle(MuralColor.secondary)
                            }
                        }
                    }
                    ForEach(session?.topics ?? []) { topic in Text(.init(topic.text)); SourcesView(sources: topic.sources, date: topic.retrievedAt) }
                }.padding(26)
            }.background(MuralColor.cream).foregroundStyle(MuralColor.ink)
                .navigationTitle("Our conversation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.sheet(isPresented: Binding(get: { editingID != nil }, set: { if !$0 { editingID = nil } })) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("What you said", text: $editedText, axis: .vertical).lineLimit(4...10).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    Text("Correct a misheard phrase. Learning evidence from the old wording will be removed; the original remains in your backup history.").font(.footnote).foregroundStyle(MuralColor.secondary)
                    Spacer()
                }.padding(24).background(MuralColor.cream).navigationTitle("What you said").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingID = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button("Save") { if let id = editingID { store.correctPassage(sessionID: sessionID, passageID: id, text: editedText) }; editingID = nil } }
                    }
            }.presentationDetents([.medium, .large])
        }
    }
}

struct SettingsView: View {
    let coordinator: ConversationCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(OnDeviceSpeechVoiceCatalog.preferenceKey) private var localVoiceIdentifier = ""
    @State private var key = ""
    @State private var hasKey = CredentialStore.hasKey
    @State private var message: String?
    @State private var exporting = false
    @State private var importing = false
    @State private var backup: BackupDocument?
    @State private var deleting = false
    @State private var notices = false
    @State private var showingAPIKey = false
    @State private var showingVoiceUpgrade = false
    @State private var localVoiceOptions = OnDeviceSpeechVoiceCatalog.availableOptions()
    private var store: LearningStore { coordinator.store }
    private var totalVoiceSeconds: Double { store.sessions.reduce(0) { $0 + $1.voiceSeconds } }
    private var hasPremiumVoice: Bool { localVoiceOptions.contains(where: \.isPremium) }
    private var selectedVoiceSummary: String {
        if localVoiceIdentifier.isEmpty {
            return OnDeviceSpeechVoiceCatalog.bestAvailableOption(from: localVoiceOptions)
                .map { "Best available · \($0.label)" } ?? "Best available"
        }
        return localVoiceOptions.first(where: { $0.id == localVoiceIdentifier })?.summary ?? "Best available"
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SettingsMenuRow(title: "Conversation mode", value: coordinator.mode.rawValue,
                                    options: ConversationCoordinator.Mode.allCases.map(\.rawValue), identifier: "settings-conversation-mode") {
                        Picker("Conversation mode", selection: Binding(get: { coordinator.mode }, set: { coordinator.selectMode($0) })) {
                            ForEach(ConversationCoordinator.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    }.disabled(!coordinator.canChangeMode)
                    Text(coordinator.isLocal
                         ? "On-device: English with Vietnamese support. Finalized text stays on this iPhone."
                         : "GPT-Live: separate OpenAI consent and your API key are required. Audio and selected text are processed by OpenAI.")
                        .font(.footnote)
                } header: { Text("Conversation") }
                Section {
                    SettingsMenuRow(title: "Voice", value: coordinator.localAudio.conversationTTSBackend == .apple ? "Apple" : "Mural Voice",
                                    options: ["Mural Voice", "Apple"], identifier: "tts-talk-backend") {
                        Picker("Voice", selection: Binding(get: { coordinator.localAudio.conversationTTSBackend }, set: { backend in
                            do { try coordinator.localAudio.selectConversationTTS(backend) }
                            catch { message = error.localizedDescription }
                        })) {
                            Text("Mural Voice").tag(LocalTTSBackend.supertonic)
                            Text("Apple").tag(LocalTTSBackend.apple)
                        }
                    }
                    .disabled(coordinator.isRunning || coordinator.localResourcesBusy || !coordinator.localAudio.canSelectTTS)

                    if coordinator.localAudio.conversationTTSBackend == .supertonic {
                        Picker("Mural voice", selection: Binding(get: { coordinator.localAudio.supertonicVoice }, set: { voice in
                            do { try coordinator.localAudio.selectSupertonicVoice(voice) }
                            catch { message = error.localizedDescription }
                        })) {
                            Section("Female voices") {
                                ForEach(Supertonic3Voice.allCases.filter { $0.rawValue.hasPrefix("F") }, id: \.self) { voice in
                                    Text(voice.muralName).tag(voice)
                                }
                            }
                            Section("Male voices") {
                                ForEach(Supertonic3Voice.allCases.filter { $0.rawValue.hasPrefix("M") }, id: \.self) { voice in
                                    Text(voice.muralName).tag(voice)
                                }
                            }
                        }
                        .disabled(coordinator.isRunning || coordinator.localResourcesBusy || !coordinator.localAudio.canSelectTTS)
                        .accessibilityIdentifier("tts-supertonic-voice")
                        SettingsMenuRow(title: "Speech speed", value: coordinator.localAudio.supertonicSpeed.label,
                                        options: SupertonicSpeed.allCases.map(\.label), identifier: "tts-supertonic-speed") {
                            Picker("Speech speed", selection: Binding(get: { coordinator.localAudio.supertonicSpeed }, set: { speed in
                                do { try coordinator.localAudio.selectSupertonicSpeed(speed) }
                                catch { message = error.localizedDescription }
                            })) {
                                ForEach(SupertonicSpeed.allCases) { speed in
                                    Text(speed.label).tag(speed)
                                }
                            }
                        }
                        .disabled(coordinator.isRunning || coordinator.localResourcesBusy || !coordinator.localAudio.canSelectTTS)
                    } else {
                        NavigationLink {
                            LocalVoicePickerView(selection: $localVoiceIdentifier, options: $localVoiceOptions)
                        } label: {
                            LabeledContent("Apple voice", value: selectedVoiceSummary)
                        }
                        .disabled(coordinator.isLocal && coordinator.isRunning)
                        .accessibilityIdentifier("local-voice-picker")
                        if hasPremiumVoice {
                            Label("Premium voice installed", systemImage: "checkmark.circle.fill")
                                .accessibilityIdentifier("local-voice-premium-ready")
                        }
                        Button("Get more Apple voices", systemImage: "arrow.down.circle") { showingVoiceUpgrade = true }
                            .accessibilityIdentifier("local-voice-upgrade")
                    }
                } header: { Text("On-device voice") } footer: {
                    if coordinator.localAudio.conversationTTSBackend == .supertonic {
                        Text("Mural Voice defaults to Theo at 1.0×. If it is unavailable or cannot speak, Mural uses your Apple voice for that conversation.")
                    } else {
                        Text("Best available prefers Premium, then Enhanced, then Standard. Within the highest available quality, it prefers a voice matching your iPhone region. You can also pin any installed English accent manually.")
                    }
                }
                #if MURAL_TTS_EXPERIMENT
                Section("Experiments") {
                    NavigationLink("Speech comparison") {
                        TTSComparisonView(audio: coordinator.localAudio)
                    }
                    .disabled(coordinator.isRunning || coordinator.localResourcesBusy)
                    .accessibilityIdentifier("tts-comparison")
                }
                #endif
                Section {
                    LearningLanguagePicker(coordinator: coordinator)
                    Toggle("Meaning subtitles", isOn: Binding(get: { store.preferences.meaningVisible }, set: { value in
                        if value != store.preferences.meaningVisible { coordinator.toggleMeaning() }
                    }))
                    SettingsMenuRow(title: "Meaning language", value: store.preferences.meaningLanguage,
                                    options: MeaningLanguages.all, identifier: "settings-meaning-language") {
                        Picker("Meaning language", selection: Binding(get: { store.preferences.meaningLanguage }, set: { coordinator.selectMeaningLanguage($0) })) {
                            ForEach(MeaningLanguages.all, id: \.self) { Text($0) }
                        }
                    }
                    .disabled(coordinator.isLocal && (coordinator.isRunning || coordinator.localResourcesBusy))
                    LabeledContent("Corrections", value: "Gently, as we talk")
                    TextField("A few things you enjoy", text: Binding(get: { store.preferences.interests }, set: { value in store.updatePreferences { $0.interests = String(value.prefix(500)) } }), axis: .vertical)
                } header: { Text("Just your pace") } footer: { Text(coordinator.isRunning ? "End this conversation to switch languages. Each language keeps its own words and progress." : "Each language keeps its own words and progress. Mural finds your pace through conversation.") }
                if ManagedAccountConfiguration.load() != nil {
                    Section {
                        NavigationLink { ManagedAccountView() } label: {
                            Label("Account", systemImage: "person.crop.circle")
                        }.disabled(coordinator.isRunning).accessibilityIdentifier("managed-account-settings")
                    }
                }
                Section {
                    DisclosureGroup(isExpanded: $showingAPIKey) {
                        if hasKey { Label("Your key is saved on this iPhone", systemImage: "checkmark.shield") }
                        SecureField(hasKey ? "Replace OpenAI key" : "OpenAI API key", text: $key)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("api-key")
                        Button(hasKey ? "Save replacement key" : "Save key") {
                            do { try CredentialStore.save(key); key = ""; hasKey = true; message = "Saved securely. Start a conversation to connect." }
                            catch { message = error.localizedDescription }
                        }.disabled(key.isEmpty || coordinator.isRunning)
                        Link("Open OpenAI API keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        if hasKey {
                            Button("Remove key", role: .destructive) {
                                do { try CredentialStore.delete(); hasKey = false; message = "Your key has been removed." }
                                catch { message = error.localizedDescription }
                            }.disabled(coordinator.isRunning)
                        }
                        Text("Your OpenAI account pays for usage. The key stays in this iPhone’s Keychain and is sent only to OpenAI.")
                            .font(.footnote).foregroundStyle(MuralColor.secondary)
                    } label: { Label("Use your own API key", systemImage: "key").accessibilityIdentifier("advanced-api-key") }
                    if let message { Text(message).font(.footnote).foregroundStyle(MuralColor.secondary) }
                } header: { Text("Advanced") }
                Section {
                    if !coordinator.isLocal {
                        SettingsMenuRow(title: "Conversation limit", value: "\(store.preferences.sessionMinutes) minutes",
                                        options: [5, 10, 15, 20, 30, 60].map { "\($0) minutes" }, identifier: "settings-conversation-limit") {
                            Picker("Conversation limit", selection: Binding(get: { store.preferences.sessionMinutes }, set: { value in store.updatePreferences { $0.sessionMinutes = value } })) {
                                ForEach([5, 10, 15, 20, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                            }
                        }
                    }
                    LabeledContent("GPT-Live voice time", value: "\(Int(totalVoiceSeconds / 60)) min \(Int(totalVoiceSeconds) % 60) sec")
                    LabeledContent("Voice estimate", value: String(format: "$%.2f USD", totalVoiceSeconds / 60 * 0.05))
                    LabeledContent("Search calls recorded", value: "\(store.sessions.reduce(0) { $0 + $1.searchCalls })")
                    Link("OpenAI usage and billing", destination: URL(string: "https://platform.openai.com/usage")!)
                } header: { Text("Keep it comfortable") } footer: {
                    if coordinator.isLocal {
                        Text("On-device practice is not billed voice time.")
                    } else {
                        Text("Voice estimate uses $0.05/min as of 11 September 2026. Translation, teaching and search cost extra. Interrupted requests can be billed without a usage record here. Your OpenAI dashboard is authoritative. The time limit is local, not a billing cap.")
                    }
                }
                Section {
                    Button("Export learning backup", systemImage: "square.and.arrow.up") {
                        do { backup = BackupDocument(data: try store.exportData()); exporting = true } catch { message = error.localizedDescription }
                    }
                    Button("Import learning backup", systemImage: "square.and.arrow.down") { importing = true }.disabled(coordinator.isRunning)
                    Button("Delete all conversations and learning", role: .destructive) { deleting = true }.disabled(coordinator.isRunning)
                } header: { Text("Your words belong to you") } footer: {
                    Text("Backups include transcripts and learning evidence, never your API key. Import adds conversations with new IDs. Existing conversations stay unchanged. There is no cloud sync.")
                }
                Section {
                    Link("Privacy policy", destination: URL(string: "https://mural.chat/privacy/")!)
                        .accessibilityIdentifier("settings-privacy-policy")
                    Link("Terms of use", destination: URL(string: "https://mural.chat/terms/")!)
                        .accessibilityIdentifier("settings-terms")
                    Link("Contact support", destination: URL(string: "https://mural.chat/support/")!)
                        .accessibilityIdentifier("settings-support")
                } header: { Text("Help and privacy") }
                Section {
                    Text("Mural 0.1 · Personal build").font(.footnote)
                    Text("GPT-Live: GPT-Live-1 voice · GPT-5.6 Luna teacher").font(.footnote)
                    Link("OpenAI data controls", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                    Text("In GPT-Live mode, audio and selected text go to OpenAI while you practise. Requests disable provider storage where supported; abuse-monitoring retention may still apply. Raw audio is not saved by Mural.").font(.footnote)
                    Button("Open-source notices") { notices = true }
                }
            }.scrollContentBackground(.hidden).background(MuralColor.cream).tint(MuralColor.secondary)
                .navigationTitle("Make yourself comfortable").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { key = ""; dismiss() } } }
        }
        .onAppear { refreshLocalVoices() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshLocalVoices() } }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in refreshLocalVoices() }
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "Mural-learning-backup") { result in if case .failure(let error) = result { message = error.localizedDescription } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
                try store.importData(Archive.readImportData(from: url)); message = "Your backup has been imported."
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Delete all learning data on this phone?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete all learning data", role: .destructive) { coordinator.deleteLearningData() }
        } message: { Text("This removes conversations, vocabulary and progress. Export a backup first if you want to keep them. Your API key and preferences remain.") }
        .sheet(isPresented: $notices) {
            NavigationStack {
                ScrollView { Text(Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Notices unavailable.").font(.footnote).padding(24).textSelection(.enabled) }
                    .navigationTitle("Open-source notices").navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showingVoiceUpgrade) { LocalVoiceUpgradeView(refresh: refreshLocalVoices) }
    }

    private func refreshLocalVoices() {
        OnDeviceSpeechVoiceCatalog.logEnglishCatalog()
        let refreshed = OnDeviceSpeechVoiceCatalog.availableOptions()
        localVoiceOptions = refreshed
        if !localVoiceIdentifier.isEmpty, !refreshed.isEmpty,
           !refreshed.contains(where: { $0.id == localVoiceIdentifier }) {
            localVoiceIdentifier = ""
        }
    }
}

private struct LocalVoicePickerView: View {
    @Binding var selection: String
    @Binding var options: [OnDeviceSpeechVoiceCatalog.Option]
    @State private var search = ""

    private var visibleOptions: [OnDeviceSpeechVoiceCatalog.Option] {
        guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return options }
        return options.filter { $0.searchText.localizedCaseInsensitiveContains(search) }
    }

    private var languages: [String] {
        visibleOptions.reduce(into: [String]()) { result, option in
            if !result.contains(option.language) { result.append(option.language) }
        }
    }

    var body: some View {
        List {
            Section {
                Button { selection = "" } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Best available")
                            if let best = OnDeviceSpeechVoiceCatalog.bestAvailableOption(from: options) {
                                Text("\(best.label) · \(best.localeName)")
                                    .font(.caption).foregroundStyle(MuralColor.secondary)
                            }
                        }
                        Spacer()
                        if selection.isEmpty { Image(systemName: "checkmark").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("local-voice-best-available")
            } header: { Text("Automatic") } footer: {
                Text("Best available prefers Premium, then Enhanced, then Standard. Within the highest available quality, your iPhone region wins the tie.")
            }

            ForEach(languages, id: \.self) { language in
                let localeOptions = visibleOptions.filter { $0.language == language }
                Section(localeOptions.first?.localeName ?? language) {
                    ForEach(localeOptions) { option in
                        Button { selection = option.id } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.name)
                                    HStack(spacing: 6) {
                                        Text(option.qualityLabel)
                                        Text(option.language)
                                    }.font(.caption).foregroundStyle(MuralColor.secondary)
                                }
                                Spacer()
                                if selection == option.id { Image(systemName: "checkmark").fontWeight(.semibold) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }

            if visibleOptions.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Find a voice or accent")
        .navigationTitle("On-device voice")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LocalVoiceUpgradeView: View {
    let refresh: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Apple installs Enhanced, Premium and Siri system voices through iPhone Settings. Mural can select voices after iOS makes them available to third-party speech synthesis, but it cannot download Apple’s voice files itself.")
                        .accessibilityIdentifier("local-voice-upgrade-instructions")
                }
                Section("On your iPhone") {
                    Text("1. Open Settings.")
                    Text("2. Go to Accessibility → Read & Speak. On some iOS versions this may be called Spoken Content.")
                    Text("3. Tap Voices → English, then choose the English region or accent you want.")
                    Text("4. Download a Premium or Enhanced voice. You can also download a Siri voice if iOS offers one there.")
                    Text("5. Return to Mural. The installed voice list refreshes automatically.")
                }
                Section {
                    Button("I’ve downloaded a voice") {
                        refresh()
                        dismiss()
                    }
                    .accessibilityIdentifier("local-voice-upgrade-done")
                } footer: {
                    Text("Best available prefers the highest-quality English voice and uses your iPhone region as a tie-breaker. To pin Lee, another regional accent, or a Siri voice, select it explicitly after iOS exposes it.")
                }
            }
            .navigationTitle("Get more Apple voices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct LearningLanguagePicker: View {
    let coordinator: ConversationCoordinator
    var body: some View {
        SettingsMenuRow(title: "Learning language", value: coordinator.language.name,
                        options: LanguageRegistry.all.map(\.name), identifier: "learning-language-picker",
                        subtitle: coordinator.language.variety, subtitleOptions: LanguageRegistry.all.map(\.variety)) {
            Picker("Learning language", selection: Binding(get: { coordinator.language.id }, set: { coordinator.selectLanguage($0) })) {
                ForEach(LanguageRegistry.all) { language in Text(language.settingsTitle).tag(language.id) }
            }
        }
        .disabled(!coordinator.canChangeMode)
    }
}

/// A stable menu source, with optional secondary detail and a stacked accessibility layout.
private struct SettingsMenuRow<Content: View>: View {
    let title: String
    let value: String
    let options: [String]
    let identifier: String
    var subtitle: String? = nil
    var subtitleOptions: [String] = []
    @ViewBuilder let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                menu.frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                menu.fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var menu: some View {
        Menu { content } label: {
            HStack {
                // Size for every choice, not just the current value, including at larger text sizes.
                VStack(alignment: .trailing, spacing: 2) {
                    ZStack(alignment: .trailing) {
                        ForEach(options, id: \.self) { Text($0).hidden() }
                        Text(value)
                    }
                    if let subtitle {
                        ZStack(alignment: .trailing) {
                            ForEach(subtitleOptions, id: \.self) { Text($0).hidden() }
                            Text(subtitle)
                        }
                        .font(.footnote)
                        .foregroundStyle(MuralColor.secondary)
                    }
                }
                .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle.map { "\(value) · \($0)" } ?? value)
        .accessibilityIdentifier(identifier)
    }
}
