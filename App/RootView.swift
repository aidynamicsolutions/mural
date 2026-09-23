import SwiftUI
import AVFoundation
import MuralCore

struct RootView: View {
    @State private var coordinator: ConversationCoordinator
    @State private var tab = 0
    @State private var onboarding = false
    @State private var localProbe = false
    @Environment(\.scenePhase) private var scenePhase
    init(store: LearningStore) {
        let coordinator = ConversationCoordinator(store: store)
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--preview"), ProcessInfo.processInfo.arguments.contains("--preview-existing-user") {
            store.updatePreferences { $0.hasOnboarded = true }
        }
        if let screen = ScreenshotPreview.screen { coordinator.prepareScreenshot(screen) }
        _tab = State(initialValue: ScreenshotPreview.tab)
        #endif
        _coordinator = State(initialValue: coordinator)
    }
    var body: some View {
        @Bindable var coordinator = coordinator
        TabView(selection: $tab) {
            Tab("Talk", systemImage: "waveform", value: 0) { shell { TalkView(coordinator: coordinator) } }
            Tab("Themes", systemImage: "square.grid.2x2", value: 1) {
                shell { ThemesView(coordinator: coordinator) { theme in coordinator.chooseTheme(theme); tab = 0 } }
            }
            Tab("Words", systemImage: "book", value: 2) { shell { WordsView(coordinator: coordinator) } }
        }
        .tint(MuralColor.ink)
        .sheet(isPresented: $coordinator.showSettings) { SettingsView(coordinator: coordinator) }
        .sheet(item: $coordinator.speechDownloadOffer, onDismiss: { coordinator.dismissSpeechDownload() }) { offer in
            SpeechDownloadConfirmationView(offer: offer, confirm: coordinator.confirmSpeechDownload,
                                           decline: coordinator.dismissSpeechDownload)
        }
        .sheet(isPresented: $localProbe) { LocalTutorProbeView(audio: coordinator.localAudio) }
        .sheet(isPresented: $coordinator.showAIConsent, onDismiss: { coordinator.resumeAfterAIConsent() }) {
            AIConsentView(agree: { coordinator.acceptAIConsent() }, decline: { coordinator.declineAIConsent() })
        }
        .fullScreenCover(isPresented: $onboarding) { OnboardingView(coordinator: coordinator) { coordinator.store.updatePreferences { $0.hasOnboarded = true }; onboarding = false } }
        .alert(errorTitle, isPresented: Binding(get: { coordinator.error != nil || coordinator.store.error != nil }, set: { if !$0 { coordinator.error = nil; coordinator.store.error = nil } })) {
            Button("OK", role: .cancel) { coordinator.error = nil; coordinator.store.error = nil }
        } message: { Text(coordinator.error ?? coordinator.store.error ?? "") }
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            #if DEBUG && targetEnvironment(simulator)
            if arguments.contains("--preview") && arguments.contains("--preview-onboarding") {
                onboarding = !coordinator.store.preferences.hasOnboarded
                return
            }
            #endif
            onboarding = !coordinator.store.preferences.hasOnboarded && !arguments.contains("--preview") && !AudioVerification.requested
            #if DEBUG && targetEnvironment(simulator)
            if arguments.contains("--preview-thermal-stop") { coordinator.prepareThermalStopPreview() }
            #endif
            if !onboarding, scenePhase == .active { coordinator.resume() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { coordinator.background() }
            else if phase == .active { coordinator.resume() }
        }
        #if DEBUG
        .task {
            if AudioVerification.requested { await AudioVerification.run(coordinator) }
            else if ProcessInfo.processInfo.arguments.contains("--ended-conversation") { coordinator.prepareEndedPreview() }
        }
        #endif
    }
    private var errorTitle: String {
        if coordinator.thermalAlertPresented { return "Your iPhone needs to cool down" }
        return "A little interruption"
    }
    private func shell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content().background(MuralColor.cream).toolbar {
                ToolbarItem(placement: .topBarLeading) { Brand().fixedSize() }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Local tutor probe", systemImage: "flask") { localProbe = true }
                        .disabled(coordinator.isRunning || coordinator.localResourcesBusy)
                        .accessibilityIdentifier("local-tutor-probe")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { coordinator.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Settings")
                }
            }.toolbarBackground(MuralColor.cream, for: .navigationBar)
        }
    }
}

struct TalkView: View {
    @Bindable var coordinator: ConversationCoordinator
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typing = false
    @State private var transcript: SessionRecord?
    @State private var lookup: WordLookup?
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Text(coordinator.isLocal ? "\(coordinator.language.name) · \(coordinator.store.preferences.meaningLanguage)" : coordinator.selectedTheme?.title ?? coordinator.language.talkTitle)
                        .font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(MuralColor.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 9).background(MuralColor.butter.opacity(0.58), in: Capsule()).padding(.top, 12)
                        .accessibilityIdentifier("conversation-language-pair")
                    Spacer(minLength: 8)
                    MuralOrb(energy: max(coordinator.outputLevel, coordinator.inputLevel * 0.45), listening: coordinator.isLocal ? coordinator.localAudio.asrState == .recording : coordinator.state == .active && !coordinator.isMuted, active: coordinator.isLocal ? coordinator.isRunning : coordinator.state != .closing)
                        .frame(width: compactOrb ? 170 : 220, height: compactOrb ? 180 : 222).padding(.vertical, 8)
                    Text(coordinator.status).font(.system(.caption, design: .rounded)).foregroundStyle(MuralColor.secondary).multilineTextAlignment(.center)
                        .contentTransition(.numericText()).padding(.top, 6).accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("conversation-status")
                        .opacity(coordinator.speechSetupProgress == nil ? 1 : 0)
                        .accessibilityHidden(coordinator.speechSetupProgress != nil)
                    if let notice = coordinator.notice {
                        Text(notice).font(.footnote).foregroundStyle(MuralColor.secondary).multilineTextAlignment(.center)
                            .padding(.top, 6).accessibilityIdentifier("conversation-notice")
                    }
                    if coordinator.speechSetupProgress == nil { captionArea.padding(.top, 16) }
                    Spacer(minLength: 12)
                    if coordinator.isLocal { localControls } else { controls }
                    HStack(spacing: 24) {
                        if coordinator.state == .active {
                            Button("Type instead", systemImage: "keyboard") { typing = true }
                                .frame(minHeight: 44).disabled(coordinator.isLocal && !coordinator.canRecordLocal)
                            Button("A little help", systemImage: "sparkles") { coordinator.help() }
                                .frame(minHeight: 44).disabled(coordinator.isLocal && !coordinator.canUseLocalSupport)
                        } else if coordinator.session == nil && !coordinator.isLocal {
                            Text("Reply in whichever language comes to you.").foregroundStyle(MuralColor.secondary)
                        } else if !coordinator.isRunning && coordinator.session != nil {
                            Button("New conversation", systemImage: "arrow.counterclockwise") { coordinator.resetConversation() }
                                .accessibilityIdentifier("new-conversation").disabled(!coordinator.canChangeMode)
                        }
                    }.font(.caption).padding(.top, 6).padding(.bottom, 12)
                }.padding(.horizontal, 30).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
            }.scrollIndicators(.hidden)
        }
        .sheet(isPresented: $typing) { TypedReplyView(coordinator: coordinator) }
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: coordinator.state)
        .sheet(item: $transcript) { session in
            TranscriptView(session: session, meaningLanguage: coordinator.store.preferences.meaningLanguage)
        }
        .sheet(item: $lookup) { item in LookupView(item: item, coordinator: coordinator) }
        .onChange(of: coordinator.mode) { typing = false; lookup = nil; transcript = nil }
        .onChange(of: coordinator.session?.id) { typing = false; lookup = nil; transcript = nil }
        .onChange(of: coordinator.localResourcesBusy) { if !coordinator.localResourcesBusy { coordinator.refreshLocalMeaning() } }
        .onChange(of: coordinator.state) { if coordinator.isLocal && !coordinator.isRunning { typing = false; lookup = nil } }
    }
    private var compactOrb: Bool { typeSize.isAccessibilitySize || coordinator.speechSetupProgress != nil }
    private var captionArea: some View {
        VStack(spacing: 12) {
            Text(linkedCaption).font(.system(coordinator.assistantPassage == nil ? .largeTitle : .title2, design: .rounded, weight: .medium))
                .tracking(-0.5).multilineTextAlignment(.center).tint(MuralColor.ink)
                .environment(\.openURL, OpenURLAction { url in
                    guard (!coordinator.isLocal || coordinator.canUseLocalSupport), url.scheme == "mural-word", let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let word = components.queryItems?.first?.value else { return .discarded }
                    lookup = WordLookup(word: word, sentence: coordinator.caption); return .handled
                }).accessibilityIdentifier("target-caption")
            if coordinator.store.preferences.meaningVisible && (!coordinator.isLocal || coordinator.assistantPassage != nil) {
                Text(coordinator.assistantPassage == nil ? MeaningLanguages.greeting(in: coordinator.store.preferences.meaningLanguage) : !coordinator.meaning.isEmpty ? coordinator.meaning : coordinator.translating ? "Finding the meaning…" : "")
                    .font(.subheadline).foregroundStyle(MuralColor.secondary).multilineTextAlignment(.center)
                    .accessibilityIdentifier("meaning-caption")
                if let error = coordinator.meaningError {
                    VStack(spacing: 6) {
                        Text(error).foregroundStyle(MuralColor.secondary)
                        Button("Try meaning again") { coordinator.retryMeaning() }
                            .disabled(coordinator.isLocal && !coordinator.canUseLocalSupport)
                    }.font(.caption).multilineTextAlignment(.center)
                }
            }
            if let help = coordinator.localAssistance, coordinator.isLocal {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A little help · \(coordinator.localSpeechPair.supportLanguage)").font(.caption)
                    Text(help).font(.subheadline).textSelection(.enabled)
                }.accessibilityIdentifier("local-learning-assistance")
            }
            if shouldShowWordHint {
                Text("Tap an English word for its meaning.").font(.caption).foregroundStyle(MuralColor.secondary)
                    .accessibilityIdentifier("word-meaning-hint")
            }
            if let user = coordinator.userPassage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("YOU").font(.system(.caption2, design: .rounded, weight: .medium))
                    Text(coordinator.isLocal ? user.text : String(user.text.suffix(160))).font(.caption).textSelection(.enabled)
                }.foregroundStyle(MuralColor.secondary).multilineTextAlignment(.center).padding(.top, 3)
            }
            if coordinator.working { ProgressView("Checking that for you…").font(.caption).tint(MuralColor.secondary) }
            if let sources = coordinator.session?.topics.last?.sources, !sources.isEmpty {
                Button("Sources", systemImage: "link") { transcript = coordinator.session }.font(.caption)
            }
        }.frame(minHeight: typeSize.isAccessibilitySize ? 100 : 105).frame(maxWidth: .infinity)
    }
    private var shouldShowWordHint: Bool {
        let assistantPassages = coordinator.session?.passages.filter { $0.speaker == .assistant } ?? []
        guard assistantPassages.count == 1, let first = assistantPassages.first else { return false }
        return !coordinator.isLocal || first.fragments.allSatisfy { $0.playbackCompleted == true }
    }
    private var linkedCaption: AttributedString {
        var result = AttributedString()
        for (i, word) in coordinator.caption.components(separatedBy: " ").enumerated() {
            var part = AttributedString((i > 0 ? " " : "") + word)
            var components = URLComponents(); components.scheme = "mural-word"; components.host = "lookup"
            components.queryItems = [URLQueryItem(name: "word", value: word)]
            if coordinator.assistantPassage != nil && (!coordinator.isLocal || coordinator.canUseLocalSupport) { part.link = components.url }
            part.foregroundColor = MuralColor.ink; result.append(part)
        }
        return result
    }
    private var localControls: some View {
        VStack(spacing: 12) {
            if coordinator.needsThermalResume {
                Button("Resume", systemImage: "play.fill") { coordinator.resumeAfterCooling() }
                    .buttonStyle(.borderedProminent).tint(MuralColor.orange).foregroundStyle(MuralColor.ink)
                    .controlSize(.large).disabled(coordinator.localResourcesBusy)
                    .accessibilityIdentifier("local-thermal-resume")
            }
            if let progress = coordinator.speechSetupProgress {
                SpeechSetupCard(progress: progress, canCancel: !coordinator.isStoppingSpeechSetup) { coordinator.end() }
            }
            if coordinator.isRunning, coordinator.speechSetupProgress == nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { localTurnButtons }
                    VStack(spacing: 12) { localTurnButtons }
                }
                if coordinator.canRetryLocalReply {
                    Button("Retry reply") { coordinator.retryLocalReply() }.frame(minHeight: 44)
                }
            } else if !coordinator.isRunning, coordinator.session == nil {
                Button("Prepare & start", systemImage: "play.fill") { coordinator.start() }
                    .buttonStyle(.borderedProminent).tint(MuralColor.orange).foregroundStyle(MuralColor.ink)
                    .controlSize(.large).disabled(coordinator.localResourcesBusy)
                    .accessibilityIdentifier("local-conversation-start")
            }
            if !coordinator.isRunning, coordinator.session != nil {
                Button("Transcript", systemImage: "text.bubble") { transcript = coordinator.session }
                    .frame(minHeight: 44).accessibilityIdentifier("local-conversation-transcript")
            }
            if let error = coordinator.speechSetupError {
                VStack(alignment: .leading, spacing: 8) {
                    Label("A little interruption", systemImage: "exclamationmark.circle").font(.subheadline.weight(.medium))
                    Text(error).font(.footnote).accessibilityIdentifier("speech-setup-error")
                    Button { coordinator.clearSpeechSetupError() } label: { Text("Dismiss").frame(minHeight: 44) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .background(MuralColor.butter.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
            }
            DisclosureGroup("On-device details & diagnostics") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ASR backend: \(coordinator.isStoppingSpeechSetup ? coordinator.localAudio.selectedConversationASRBackend : coordinator.localSpeechPair == .taiwanMandarinEnglish ? "Breeze PAL8 · WhisperKit / Core ML" : LocalConversationEngine.conversationASRBackend)")
                        .accessibilityIdentifier("local-asr-backend")
                    Text("\(coordinator.localSpeechPair.recognizerID) → Apple tutor → English speech. Tap Record only after Mural finishes speaking; tap Send when done.")
                        .accessibilityIdentifier("local-recognizer")
                    Text("Microphone is off except while recording. On-device conversations do not end for inactivity; tap End when you are done.")
                    Text("Speech-presence checks cannot guarantee that recognition is accurate. Review the transcript; reported preparation speed does not qualify a recognizer's language accuracy.")
                    Text("Finalized turns, \(coordinator.localSpeechPair.supportLanguage) meanings, lookup, Help and typed replies stay on this iPhone. Raw recognition is saved separately from display text; teaching never rewrites it. Themes and search remain unavailable.")
                    Text(coordinator.localSpeechPair == .taiwanMandarinEnglish
                         ? "Taiwan Mandarin–English is a user-test mode. Traditional Chinese Help is on screen; practice speech stays English. Automatic learning credit is disabled pending separate semantic qualification."
                         : "After End, only your last reply is reviewed for up to two English words or phrases. Evidence is provisional; supported practice is not independent recall.")
                    if coordinator.session != nil, !coordinator.localAudio.rawASRText.isEmpty {
                        DisclosureGroup("Raw recognition · not translated") {
                            Text(coordinator.localAudio.rawASRText).font(.footnote).textSelection(.enabled)
                                .accessibilityIdentifier("local-raw-asr")
                        }
                    }
                    if let seconds = coordinator.localAudio.preparationSeconds {
                        Text("Preparation: \(seconds, specifier: "%.1f") s").font(.caption).monospacedDigit()
                    }
                    if let seconds = coordinator.localReplySeconds {
                        Text("Send to reply: \(seconds, specifier: "%.2f") s").font(.caption).monospacedDigit()
                    }
                    if let seconds = coordinator.localAudio.sendToPlaybackSeconds {
                        Text("Send to audio: \(seconds, specifier: "%.2f") s").font(.caption).monospacedDigit()
                            .accessibilityIdentifier("local-response-gap")
                    }
                    if !coordinator.localAudio.preparationDetail.isEmpty { Text(coordinator.localAudio.preparationDetail) }
                    if let error = coordinator.speechSetupDiagnostic { Text(error).textSelection(.enabled) }
                    if let package = coordinator.speechModels.package {
                        Text("Managed package: \(package.id) · \(coordinator.speechModels.phase.rawValue)")
                    }
                    if let seconds = coordinator.localAudio.finalizeSeconds {
                        Text("ASR: \(seconds, specifier: "%.2f") s")
                    }
                    if let seconds = coordinator.localModelSeconds {
                        Text("Model: \(seconds, specifier: "%.2f") s")
                    }
                    if !coordinator.isRunning, coordinator.userPassage != nil {
                        if let assessment = coordinator.session?.assessments.last {
                            Text("Last-reply review: \(assessment.outcome.rawValue) · \(assessment.words.count) words · \(assessment.capability.isEmpty ? "no capability credit" : "provisional capability evidence")")
                        } else {
                            Text(coordinator.localAssessmentRunning ? "Last-reply review is pending." : "No verified last-reply evidence saved. The review may have been canceled or unavailable.")
                        }
                    }
                }.font(.footnote).padding(.top, 8)
            }.font(.footnote)
        }.foregroundStyle(MuralColor.ink)
    }

    @ViewBuilder private var localTurnButtons: some View {
        Button(coordinator.localAudio.asrState == .recording ? "Send" : "Record",
               systemImage: coordinator.localAudio.asrState == .recording ? "arrow.up" : "mic") {
            if coordinator.localAudio.asrState == .recording { coordinator.sendLocal() }
            else { coordinator.recordLocal() }
        }.buttonStyle(.borderedProminent).tint(MuralColor.orange).foregroundStyle(MuralColor.ink)
            .controlSize(.large)
            .disabled(!coordinator.canRecordLocal && coordinator.localAudio.asrState != .recording)
            .accessibilityIdentifier("local-conversation-record-send")
        Button("End", systemImage: "stop.fill") { coordinator.end() }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier("local-conversation-end")
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 27) {
            Color.clear.frame(width: 48, height: 48)
            Button {
                if coordinator.state == .active { coordinator.toggleMute() }
                else if !coordinator.isRunning { coordinator.start() }
            } label: {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.73, blue: 0.48), MuralColor.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    if coordinator.state == .connecting || coordinator.state == .closing { ProgressView().tint(MuralColor.ink) }
                    else { Image(systemName: coordinator.isMuted && coordinator.state == .active ? "mic.slash" : "mic").font(.system(size: 28, weight: .regular)).contentTransition(.symbolEffect(.replace)) }
                }.frame(width: 76, height: 76).shadow(color: MuralColor.orange.opacity(0.25), radius: 10, y: 6)
            }.buttonStyle(.plain).padding(.bottom, 18)
                .disabled(coordinator.state == .connecting || coordinator.state == .closing)
                .accessibilityLabel(coordinator.state == .active ? (coordinator.isMuted ? "Unmute microphone" : "Mute microphone") : "Start conversation")
                .accessibilityIdentifier("start-conversation")
            Button { if coordinator.isRunning { coordinator.end() } else { transcript = coordinator.session } } label: {
                VStack(spacing: 6) {
                    Image(systemName: coordinator.isRunning ? "phone.down" : "text.bubble").frame(width: 48, height: 48).modifier(SoftGlass())
                    Text(coordinator.isRunning ? "End" : "Transcript").font(.caption2)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(coordinator.isRunning ? "End conversation" : "Conversation transcript")
                .disabled(coordinator.session == nil)
        }.foregroundStyle(MuralColor.ink)
    }
}

/// This is stage progress, not an estimated percentage of native preparation.
private struct SpeechSetupCard: View {
    let progress: SpeechSetupProgress
    let canCancel: Bool
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                if progress.stage == .cancelled {
                    Image(systemName: "checkmark.circle").accessibilityHidden(true)
                } else if progress.fraction == nil {
                    ProgressView().tint(MuralColor.ink).padding(.top, 2).accessibilityHidden(true)
                }
                Text(progress.title).font(.system(.headline, design: .rounded))
                    .accessibilityIdentifier("speech-setup-stage").accessibilityAddTraits(.updatesFrequently)
            }
            if let fraction = progress.fraction {
                ProgressView(value: fraction).tint(MuralColor.ink)
                    .accessibilityLabel(progress.title).accessibilityIdentifier("speech-setup-download-progress")
                ViewThatFits(in: .horizontal) {
                    HStack { downloadSize; Spacer(); Text(fraction, format: .percent.precision(.fractionLength(0))) }
                    VStack(alignment: .leading) { downloadSize; Text(fraction, format: .percent.precision(.fractionLength(0))) }
                }.font(.caption).monospacedDigit()
            }
            Text(progress.detail).font(.footnote).foregroundStyle(MuralColor.secondary)
            if canCancel {
                Button(role: .cancel, action: cancel) { Text("Cancel setup").frame(minHeight: 44) }
                    .accessibilityIdentifier("speech-setup-cancel")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(MuralColor.butter.opacity(0.4), in: RoundedRectangle(cornerRadius: 22))
    }
    @ViewBuilder private var downloadSize: some View {
        if let done = progress.completedBytes, let total = progress.totalBytes {
            Text("\(ByteCountFormatter.string(fromByteCount: done, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
        } else { Text("This download") }
    }
}

struct SpeechDownloadConfirmationView: View {
    let offer: ConversationCoordinator.SpeechDownloadOffer
    let confirm: () -> Void
    let decline: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "waveform").font(.largeTitle).foregroundStyle(MuralColor.ink).accessibilityHidden(true)
                    Text("A little setup, then let’s talk.").font(.system(.title, design: .rounded, weight: .semibold))
                    Text("Download the speech files you need for this language combination. We’ll get them ready and start your conversation automatically.")
                    VStack(alignment: .leading, spacing: 10) {
                        if let bytes = offer.recognitionBytes { storageRow("Speech download", bytes: bytes) }
                        if let storage = offer.recognitionStorageBytes { storageRow("Free space for speech setup", bytes: storage) }
                        if offer.needsVoice { Text("Mural’s voice also needs a download. Its size isn’t available in this version.") }
                        if offer.needsSpeechDetection { Text("Speech-detection files also need a download. Their size isn’t available in this version.") }
                        if let bytes = offer.availableBytes { Text("\(size(bytes)) available on your iPhone").foregroundStyle(MuralColor.secondary) }
                        if offer.needsVoice || offer.needsSpeechDetection {
                            Text("Allow extra storage for these files and their preparation.").foregroundStyle(MuralColor.secondary)
                        }
                    }.font(.subheadline).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(MuralColor.butter.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
                    Text("Wi-Fi recommended. Uses your current connection, including mobile data. Keep Mural open during setup; you can cancel at any time.")
                        .font(.footnote).foregroundStyle(MuralColor.secondary)
                    Button(action: confirm) {
                        Text("Download & continue").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).tint(MuralColor.orange).foregroundStyle(MuralColor.ink)
                        .accessibilityIdentifier("speech-download-confirm")
                    Button(action: decline) { Text("Not now").frame(maxWidth: .infinity, minHeight: 44) }
                        .accessibilityIdentifier("speech-download-decline")
                }.padding(26)
            }.background(MuralColor.cream).foregroundStyle(MuralColor.ink)
                .navigationTitle("Get ready to talk").navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    @ViewBuilder private func storageRow(_ title: String, bytes: Int64) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                Text(size(bytes)).fontWeight(.semibold)
            }.accessibilityElement(children: .combine)
        } else { LabeledContent(title, value: size(bytes)) }
    }
}

/// Optional storage action, not a prerequisite or a second download/setup flow.
struct SpeechStorageView: View {
    let coordinator: ConversationCoordinator
    @State private var confirmRemoval = false
    @State private var message: String?
    private var pair: LocalSpeechPair { coordinator.selectedLocalSpeechPair }
    var body: some View {
        Form {
            Section {
                Text(pair.title)
                Text("Prepare & start downloads missing speech files when you need them. You don’t need to manage them here.").font(.footnote)
            } header: { Text("Selected language combination") }
            Section {
                Button("Remove downloaded recognition files", role: .destructive) { confirmRemoval = true }
                    .disabled(!coordinator.canChangeMode).accessibilityIdentifier("speech-storage-remove")
                if let message { Text(message).font(.footnote) }
            } header: { Text("Free up space") } footer: {
                Text("Removes only managed recognition downloads for this language combination, including retained versions. Conversations, learning, voice files and system caches are kept. Development-staged files are not managed here.")
            }
        }.navigationTitle("Downloaded speech").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Remove recognition downloads for this language combination?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("Remove downloads", role: .destructive) {
                    guard coordinator.canChangeMode else { return }
                    coordinator.localAudio.stop()
                    do {
                        try coordinator.speechModels.removeManagedDownloads(for: pair)
                        message = "Managed recognition downloads removed."
                    } catch { message = error.localizedDescription }
                }
            } message: { Text("You’ll need to download them again before talking. Your conversations and learning won’t be removed.") }
    }
}

struct WordLookup: Identifiable { var id = UUID(); var word: String; var sentence: String }
struct LookupView: View {
    let item: WordLookup
    let coordinator: ConversationCoordinator
    @State private var explanation: String?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(item.word).font(.system(.largeTitle, design: .rounded, weight: .medium))
                Text(item.sentence).font(.title3).foregroundStyle(MuralColor.secondary)
                if let explanation { Text(explanation).font(.body).textSelection(.enabled) }
                else if let error { Text(error).foregroundStyle(MuralColor.secondary) }
                else { ProgressView("Finding the meaning…") }
                Spacer()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(MuralColor.cream)
                .navigationTitle("A little meaning").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
            .task { do { let result = try await coordinator.lookup(word: item.word, sentence: item.sentence); try Task.checkCancellation(); explanation = result } catch is CancellationError { } catch { self.error = error.localizedDescription } }
    }
}

struct TypedReplyView: View {
    let coordinator: ConversationCoordinator
    @State private var text = ""
    @State private var sending = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Say it your way.").font(.system(.title, design: .rounded, weight: .semibold))
                TextField("Reply in \(coordinator.language.name) or another language", text: $text, axis: .vertical).lineLimit(3...6).focused($focused).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 22))
                Button { sending = true; Task { await coordinator.sendTyped(text); sending = false; dismiss() } } label: {
                    HStack { Text(sending ? "Sending…" : "Send reply"); Spacer(); Image(systemName: "arrow.up") }.padding(18).background(MuralColor.orange, in: Capsule())
                }.disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                           (coordinator.isLocal && (!coordinator.canRecordLocal || text.count > 2000)))
                if coordinator.isLocal {
                    Text("\(coordinator.localSpeechPair.inputDescription). Up to 2,000 characters. Typed replies count as supported practice.")
                        .font(.footnote).foregroundStyle(MuralColor.secondary)
                    if !coordinator.canRecordLocal { Text("Wait for Ready before sending.").font(.footnote) }
                }
                Spacer()
            }.padding(26).foregroundStyle(MuralColor.ink).background(MuralColor.cream)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.presentationDetents([.medium, .large]).onAppear { focused = true }
    }
}

/// Visible feasibility entry, including optimized device builds. Not a saved conversation.
struct LocalTutorProbeView: View {
    static var vadOnlyRequested: Bool {
        #if MURAL_VAD_PROBE
        ProcessInfo.processInfo.arguments.contains("--asr-vad-only")
        #else
        false
        #endif
    }

    private var retainingVADFixtures: Bool { Self.vadOnlyRequested && LocalConversationEngine.retainsVADFixtures }

    private var speechModels: [LocalConversationEngine.ASRModel] {
        #if MURAL_VAD_PROBE
        if Self.vadOnlyRequested { return [.vadOnly] }
        #endif
        return LocalConversationEngine.ASRModel.allCases
    }

    @State private var audio: LocalConversationEngine
    init(audio: LocalConversationEngine? = nil) {
        _audio = State(initialValue: audio ?? LocalConversationEngine())
    }
    @State private var speechProbe = true
    @State private var text = ""
    @State private var reply = ""
    @State private var history: [String] = []
    @State private var worker: Task<Void, Never>?
    @State private var timeout: Task<Void, Never>?
    @State private var status = "Ready"
    @State private var error: String?
    @State private var availability = LocalTutorModel.availabilityMessage
    @State private var locales = LocalTutorModel.localeStatus
    @State private var timings = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Picker("Probe", selection: $speechProbe) {
                    Text(Self.vadOnlyRequested ? "Speech gate only (no ASR)" : "Speech recognition").tag(true)
                    Text("Apple tutor").tag(false)
                }.disabled(worker != nil || audio.asrBusy || Self.vadOnlyRequested)
                if speechProbe {
                    speechSections
                } else {
                Section("Phase 1 · Apple tutor") {
                    Text("Text → on-device Apple model → English system speech. This probe does not save conversations or award learning evidence.")
                    Text(locales).font(.footnote)
                    Text(availability ?? "Apple model available").accessibilityIdentifier("local-model-availability")
                    Button("Check availability again") { refresh() }.disabled(worker != nil)
                }
                Section("Your message") {
                    TextField("English, Vietnamese, or both", text: $text, axis: .vertical)
                        .lineLimit(3...8).focused($focused).autocorrectionDisabled()
                        .accessibilityIdentifier("local-probe-input")
                    Button("Send", systemImage: "arrow.up") { send() }
                        .disabled(worker != nil || availability != nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("local-probe-send")
                }
                Section("Actual reply") {
                    Text(status).accessibilityIdentifier("local-probe-status")
                    if !reply.isEmpty { Text(reply).textSelection(.enabled).accessibilityIdentifier("local-probe-reply") }
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("local-probe-error") }
                    if !timings.isEmpty { Text(timings).font(.footnote).monospacedDigit() }
                    Text(audio.voiceDescription).font(.footnote)
                    if let startup = audio.playbackStartSeconds {
                        Text("TTS delegate startup: \(startup, specifier: "%.2f") s").font(.footnote)
                    }
                    if let duration = audio.playbackDurationSeconds {
                        Text("TTS delegate duration: \(duration, specifier: "%.2f") s. Confirm audible speech by listening.").font(.footnote)
                    }
                }
                }
            }
            .navigationTitle(Self.vadOnlyRequested ? "Speech gate test" : "Local conversation probe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { stop(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Stop") { stop() }.disabled(worker == nil && !audio.asrBusy && !audio.canRecord)
                }
            }
        }
        #if MURAL_VAD_PROBE
        .onAppear {
            if Self.vadOnlyRequested { audio.selectASR(.vadOnly) }
        }
        #endif
        .onDisappear { stop() }
        .onChange(of: speechProbe) { stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stop() }
            else { refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange)) { _ in
            if audio.asrState == .recording { stop() }
        }
    }

    @ViewBuilder private var speechSections: some View {
        Section("Phase 2 · Microphone only") {
            Picker("Speech model", selection: Binding(get: { audio.asrModel }, set: { audio.selectASR($0) })) {
                ForEach(speechModels, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }.disabled(audio.asrBusy).accessibilityIdentifier("local-asr-model")
            if Self.vadOnlyRequested {
                Text("This checks only whether the current VAD gate accepts your recording. No words are recognized.")
                Text(retainingVADFixtures
                     ? "Private fixture retention is ON: up to 8 submitted recordings are saved locally for the approved test."
                     : "No audio is saved.")
            } else {
                Text("Send shows the selected model's uncorrected transcript. No tutor, TTS, saved conversation, or cloud inference is used.")
            }
            switch audio.asrModel {
            #if MURAL_VAD_PROBE
            case .vadOnly:
                Text("VAD-only diagnosis uses the normal microphone and converter, but loads only Silero. Send reports the current gate decision, not a transcript.").font(.footnote)
            #endif
            #if MURAL_FIRERED_FILE_PROBE
            case .fireRed:
                Text("FireRedASR2-AED · Mainland Mandarin and English · INT8 · CPU · 16 kHz mono · 30 seconds per turn. Recognition starts after Send.").font(.footnote)
                Text("Development-only probe with pinned local assets. No download, transcript correction, or cloud fallback. Stop and report memory warnings, errors, or excessive delay.").font(.footnote)
            #endif
            case .breeze:
                Text("Breeze ASR 25 · Taiwan Mandarin and English · PAL8 · auto language · 16 kHz mono · 30 seconds per turn. Recognition starts after Send.").font(.footnote)
                Text("Explicit Taiwan Mandarin–English test. Uses the fixed reviewed manifest pin and the same verified assets as Talk. Manage downloads from Talk; no cloud inference fallback. Stop and report warnings or unexpected results.").font(.footnote)
            case .phoWhisper:
                Text("PhoWhisper large-v2 + VI/EN code-switch LoRA · normal Talk backend · auto language · 16 kHz mono · 30 seconds per turn. Recognition starts after Send.").font(.footnote)
                Text("Uses the existing verified local Talk assets and speech-presence policy. No download or cloud fallback. Recognition can still lose words or invent text.").font(.footnote)
            case .parakeet:
                Text("Parakeet CTC 0.6B · Vietnamese–English · community Core ML conversion · 16 kHz mono. This test is limited to 15 seconds per turn; recognition starts after Send.").font(.footnote)
                Text("Prepare on Wi-Fi: about 1.19 GB plus Core ML caches. Keep the app open during first preparation. Whisper and Nemotron's cached files are kept.").font(.footnote)
            case .whisper:
                Text("Whisper large-v3-turbo · 626 MB variant · auto language · 16 kHz mono. Recognition starts after Send; Mixed-language recognition improved in testing but can still lose words or add text.").font(.footnote)
                Text("Prepare on Wi-Fi first: about 627 MB plus tokenizer and Core ML caches. First preparation can take several minutes. Nemotron's cached files are kept.").font(.footnote)
            case .nemotron:
                Text("Nemotron · full multilingual vocabulary · auto · 1120 ms · 16 kHz mono. Mixed-language recognition failed earlier tests.").font(.footnote)
                Text("Prepare on Wi-Fi first: about 664 MB plus preparation space, or reuse cached files. Whisper's cached files are kept.").font(.footnote)
            }
            Text(Self.vadOnlyRequested ? "Only the small Silero detector is loaded. ASR, tutor and TTS are off." : "Only one speech model is loaded at a time.").font(.footnote)
            Button(Self.vadOnlyRequested ? "Prepare speech gate" : "Prepare speech models") { audio.prepareASR() }.disabled(!audio.canPrepare)
            if audio.asrError != nil, audio.canPrepare, audio.asrModel.supportsRepairDownload {
                Button("Repair download") { audio.prepareASR(repairDownload: true) }
            }
            Text(audio.asrState.rawValue).accessibilityIdentifier("local-asr-status")
            if audio.asrBusy && audio.asrState != .recording { ProgressView() }
            if let seconds = audio.preparationSeconds {
                Text("Total preparation: \(seconds, specifier: "%.1f") s").font(.footnote)
            }
            if !audio.preparationDetail.isEmpty { Text(audio.preparationDetail).font(.footnote) }
        }
        Section("Your recording") {
            Text(audio.inputDescription).font(.footnote)
            Button("Record", systemImage: "mic") { audio.record() }.disabled(!audio.canRecord)
                .accessibilityIdentifier("local-asr-record")
            Button("Send recording", systemImage: "arrow.up") { audio.finishRecording() }
                .disabled(audio.asrState != .recording).accessibilityIdentifier("local-asr-send")
            Text("Speak for up to \(audio.recordingLimitSeconds) seconds, then tap Send recording. Stop discards an unfinished recording and unloads the models.").font(.footnote)
        }
        Section(Self.vadOnlyRequested ? "Current gate result (no ASR)" : "Finalized recognition · \(audio.asrModel.rawValue)") {
            if Self.vadOnlyRequested {
                Text(audio.asrNotice ?? "Record once, then tap Send recording to see Accept or Reject.")
                    .textSelection(.enabled).accessibilityIdentifier("local-asr-notice")
            } else {
                Text(audio.asrText.isEmpty ? "No finalized text" : audio.asrText)
                    .textSelection(.enabled).accessibilityIdentifier("local-asr-text")
                if let notice = audio.asrNotice { Text(notice).font(.footnote) }
            }
            if let error = audio.asrError { Text(error).foregroundStyle(.red) }
            if let seconds = audio.finalizeSeconds {
                Text("Captured audio: \(audio.capturedSeconds, specifier: "%.2f") s · Send to final: \(seconds, specifier: "%.2f") s").font(.footnote)
            }
        }
    }

    private func refresh() {
        availability = LocalTutorModel.availabilityMessage
        locales = LocalTutorModel.localeStatus
    }

    private func stop() {
        timeout?.cancel(); timeout = nil
        worker?.cancel(); audio.stop()
        if worker != nil { status = "Stopping…" }
    }

    private func send() {
        guard worker == nil else { return }
        refresh()
        guard availability == nil else { return }
        focused = false
        let input = text, context = history
        error = nil; reply = ""; timings = ""; status = "Thinking…"
        worker = Task { @MainActor in
            defer { timeout?.cancel(); timeout = nil; worker = nil }
            do {
                let result = try await LocalTutorModel().reply(to: input, history: context)
                try Task.checkCancellation()
                reply = result.text
                history = Array((context + ["Learner: \(input)", "Mural: \(result.text)"]).suffix(6))
                timings = String(format: "Model first output: %.2f s · full reply: %.2f s", result.firstOutputSeconds, result.fullResponseSeconds)
                timeout?.cancel(); timeout = nil
                status = "Speaking…"
                do { try await audio.speak(result.text) }
                catch is CancellationError { throw CancellationError() }
                catch { self.error = error.localizedDescription; status = "Speech unavailable"; return }
                try Task.checkCancellation()
                status = "Ready"
            } catch {
                if Task.isCancelled { status = "Stopped" }
                else { self.error = LocalTutorModel.message(for: error); status = "Reply unavailable" }
            }
        }
        timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            worker?.cancel(); audio.stop()
            error = "The Apple model took too long. Wait a moment and try Send again."
        }
    }
}
