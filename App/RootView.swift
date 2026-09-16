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
        .sheet(isPresented: $localProbe) { LocalTutorProbeView() }
        .sheet(isPresented: $coordinator.showAIConsent, onDismiss: { coordinator.resumeAfterAIConsent() }) {
            AIConsentView(agree: { coordinator.acceptAIConsent() }, decline: { coordinator.declineAIConsent() })
        }
        .fullScreenCover(isPresented: $onboarding) { OnboardingView(coordinator: coordinator) { coordinator.store.updatePreferences { $0.hasOnboarded = true }; onboarding = false } }
        .alert("A little interruption", isPresented: Binding(get: { coordinator.error != nil || coordinator.store.error != nil }, set: { if !$0 { coordinator.error = nil; coordinator.store.error = nil } })) {
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
    @State private var typing = false
    @State private var transcript: SessionRecord?
    @State private var lookup: WordLookup?
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Picker("Conversation mode", selection: Binding(get: { coordinator.mode }, set: { coordinator.selectMode($0) })) {
                        ForEach(ConversationCoordinator.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).disabled(!coordinator.canChangeMode)
                        .accessibilityIdentifier("conversation-mode")
                    Text(coordinator.isLocal ? "English · Vietnamese support" : coordinator.selectedTheme?.title ?? coordinator.language.talkTitle)
                        .font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(MuralColor.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 9).background(MuralColor.butter.opacity(0.58), in: Capsule()).padding(.top, 12)
                    Spacer(minLength: 8)
                    MuralOrb(energy: max(coordinator.outputLevel, coordinator.inputLevel * 0.45), listening: coordinator.isLocal ? coordinator.localAudio.asrState == .recording : coordinator.state == .active && !coordinator.isMuted, active: coordinator.isLocal ? coordinator.isRunning : coordinator.state != .closing)
                        .frame(width: typeSize.isAccessibilitySize ? 170 : 220, height: typeSize.isAccessibilitySize ? 180 : 222).padding(.vertical, 8)
                    Text(coordinator.status).font(.system(.caption, design: .rounded)).foregroundStyle(MuralColor.secondary).multilineTextAlignment(.center)
                        .contentTransition(.numericText()).padding(.top, 6).padding(.bottom, 16).accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("conversation-status")
                    captionArea
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
                    if let notice = coordinator.notice {
                        Text(notice).font(.footnote).foregroundStyle(MuralColor.secondary).multilineTextAlignment(.center).padding(.bottom, 12)
                    }
                }.padding(.horizontal, 30).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
            }.scrollIndicators(.hidden)
        }
        .sheet(isPresented: $typing) { TypedReplyView(coordinator: coordinator) }
        .animation(.smooth(duration: 0.35), value: coordinator.state)
        .sheet(item: $transcript) { session in
            TranscriptView(session: session, meaningLanguage: coordinator.store.preferences.meaningLanguage)
        }
        .sheet(item: $lookup) { item in LookupView(item: item, coordinator: coordinator) }
        .onChange(of: coordinator.mode) { typing = false; lookup = nil; transcript = nil }
        .onChange(of: coordinator.session?.id) { typing = false; lookup = nil; transcript = nil }
        .onChange(of: coordinator.localResourcesBusy) { if !coordinator.localResourcesBusy { coordinator.refreshLocalMeaning() } }
        .onChange(of: coordinator.state) { if coordinator.isLocal && !coordinator.isRunning { typing = false; lookup = nil } }
    }
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
            if coordinator.isRunning {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { localTurnButtons }
                    VStack(spacing: 12) { localTurnButtons }
                }
                if coordinator.canRetryLocalReply {
                    Button("Retry reply") { coordinator.retryLocalReply() }.frame(minHeight: 44)
                }
            } else if coordinator.session == nil {
                Button("Prepare & start", systemImage: "play.fill") { coordinator.start() }
                    .buttonStyle(.borderedProminent).tint(MuralColor.orange).foregroundStyle(MuralColor.ink)
                    .controlSize(.large).disabled(coordinator.localResourcesBusy)
                    .accessibilityIdentifier("local-conversation-start")
            }
            if !coordinator.isRunning, coordinator.session != nil {
                Button("Transcript", systemImage: "text.bubble") { transcript = coordinator.session }
                    .frame(minHeight: 44).accessibilityIdentifier("local-conversation-transcript")
            }
            DisclosureGroup("On-device details & diagnostics") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PhoWhisper CS FP16 → Apple tutor → English system voice. Tap Record only after Mural finishes speaking; tap Send when done.")
                    Text("Microphone is off except while recording. On-device conversations do not end for inactivity; tap End when you are done.")
                    Text("Silence can produce invented text and an unsolicited tutor reply. Recognition is accepted for MVP with this known limitation; silence detection is not implemented.")
                    Text("Finalized turns, Vietnamese meanings, lookup, Help and typed replies stay on this iPhone. After you tap End, only your last reply is reviewed for up to two English words or phrases. Evidence is provisional; supported practice is not independent recall. Themes and search remain unavailable.")
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
                    Text("English, Vietnamese, or both. Up to 2,000 characters. Typed replies count as supported practice.")
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
private struct LocalTutorProbeView: View {
    @State private var audio = LocalConversationEngine()
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
                    Text("Speech recognition").tag(true)
                    Text("Apple tutor").tag(false)
                }.disabled(worker != nil || audio.asrBusy)
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
            .navigationTitle("Local conversation probe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { stop(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Stop") { stop() }.disabled(worker == nil && !audio.asrBusy && !audio.canRecord)
                }
            }
        }
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
                ForEach(LocalConversationEngine.ASRModel.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }.disabled(audio.asrBusy).accessibilityIdentifier("local-asr-model")
            Text("Record English, Vietnamese, or both. Send shows the selected model's uncorrected transcript. No tutor, TTS, saved conversation, or cloud inference is used.")
            if audio.asrModel == .phoWhisper {
                Text("PhoWhisper large-v2 + VI/EN code-switch LoRA · FP16 · auto language · 16 kHz mono · 30 seconds per turn. Recognition starts after Send.").font(.footnote)
                Text("Development-only local installation: 3.10 GB plus Core ML caches. Prepare verifies the installation, then warms the models. Keep the app open. Recognition is accepted for MVP with a known silence hallucination; silence can still produce invented text.").font(.footnote)
            } else if audio.asrModel == .parakeet {
                Text("Parakeet CTC 0.6B · Vietnamese–English · community Core ML conversion · 16 kHz mono. This test is limited to 15 seconds per turn; recognition starts after Send.").font(.footnote)
                Text("Prepare on Wi-Fi: about 1.19 GB plus Core ML caches. Keep the app open during first preparation. Whisper and Nemotron's cached files are kept.").font(.footnote)
            } else if audio.asrModel == .whisper {
                Text("Whisper large-v3-turbo · 626 MB variant · auto language · 16 kHz mono. Recognition starts after Send; Mixed-language recognition improved in testing but can still lose words or add text.").font(.footnote)
                Text("Prepare on Wi-Fi first: about 627 MB plus tokenizer and Core ML caches. First preparation can take several minutes. Nemotron's cached files are kept.").font(.footnote)
            } else {
                Text("Nemotron · full multilingual vocabulary · auto · 1120 ms · 16 kHz mono. Mixed-language recognition failed earlier tests.").font(.footnote)
                Text("Prepare on Wi-Fi first: about 664 MB plus preparation space, or reuse cached files. Whisper's cached files are kept.").font(.footnote)
            }
            Text("Only one speech model is loaded at a time.").font(.footnote)
            Button("Prepare speech models") { audio.prepareASR() }.disabled(!audio.canPrepare)
            if audio.asrError != nil, audio.canPrepare, audio.asrModel != .phoWhisper {
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
        Section("Finalized recognition · \(audio.asrModel.rawValue)") {
            Text(audio.asrText.isEmpty ? "No finalized text" : audio.asrText)
                .textSelection(.enabled).accessibilityIdentifier("local-asr-text")
            if let notice = audio.asrNotice { Text(notice).font(.footnote) }
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
