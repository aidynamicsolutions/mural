#if MURAL_TTS_EXPERIMENT
import AVFoundation
import SwiftUI
import UIKit

struct TTSComparisonView: View {
    @State private var runner: TTSComparisonRunner
    @State private var selectedBackend: LocalTTSBackend = .apple
    @State private var phraseID = "06"
    @Environment(\.scenePhase) private var scenePhase

    init(audio: LocalConversationEngine? = nil) {
        let owner = audio ?? LocalConversationEngine()
        _runner = State(initialValue: TTSComparisonRunner(audio: owner))
        _selectedBackend = State(initialValue: owner.ttsBackend)
    }

    var body: some View {
        Form {
            Section {
                Text("Experimental speech comparison").font(.headline)
                Text("TTS only. No microphone, tutor or saved conversations. This does not change your Talk voice selection.").font(.footnote)
                #if targetEnvironment(simulator)
                Text("Simulator: Apple and synthetic playback only. Not a phone performance result.").font(.footnote)
                #endif
                Picker("Backend", selection: $selectedBackend) {
                    ForEach(LocalTTSBackend.allCases) { Text($0.label).tag($0) }
                }.disabled(runner.busy).accessibilityIdentifier("tts-backend")
                LabeledContent("Voice", value: runner.audio.ttsVoiceDescription)
                if runner.busy { ProgressView(runner.status).accessibilityIdentifier("tts-progress") }
                Button(runner.thermalStopped ? "Resume" : "Prepare", systemImage: "arrow.down.circle") { runner.prepare() }
                    .disabled(runner.busy).accessibilityIdentifier("tts-prepare")
                if selectedBackend != .apple {
                    Button("Use Apple voice") { selectedBackend = .apple }
                        .disabled(runner.busy)
                }
            }
            Section("Fixed English phrases") {
                Picker("Phrase", selection: $phraseID) {
                    ForEach(runner.phrases) { Text("\($0.id) · \($0.category)").tag($0.id) }
                }.disabled(runner.busy)
                if let phrase = runner.phrases.first(where: { $0.id == phraseID }) {
                    Text(phrase.text).accessibilityIdentifier("tts-phrase")
                }
                Button("Play selected phrase") { runner.play(phraseID: phraseID) }
                    .disabled(runner.busy || !runner.prepared).accessibilityIdentifier("tts-play")
                Button("Run smoke check (5 phrases)") { runner.runSmoke() }
                    .disabled(runner.busy || !runner.prepared).accessibilityIdentifier("tts-smoke")
                Button("Run corpus (30 phrases)") { runner.runCorpus() }
                    .disabled(runner.busy || !runner.prepared)
            }
            Section {
                Button("Play 24 kHz signal") { runner.playSignal(rate: 24_000) }
                    .disabled(runner.busy).accessibilityIdentifier("tts-signal24")
                Button("Play 44.1 kHz signal") { runner.playSignal(rate: 44_100) }
                    .disabled(runner.busy).accessibilityIdentifier("tts-signal44")
                Button("Check lifecycle (no audio)") { runner.checkLifecycle() }
                    .disabled(runner.busy || selectedBackend != .apple).accessibilityIdentifier("tts-lifecycle")
            } header: { Text("Synthetic PCM checks") } footer: {
                Text("Explicit Play only: one quiet second at 440 Hz. These are test signals, not synthesized speech.")
            }
            Section("Last run") {
                if runner.busy { ProgressView(runner.audio.speechDraining ? "Draining…" : "Working…") }
                Text(runner.status).accessibilityIdentifier("tts-status")
                if let error = runner.error { Label(error, systemImage: "exclamationmark.triangle").accessibilityIdentifier("tts-error") }
                Text(runner.summary).accessibilityIdentifier("tts-summary")
                if let url = runner.exportURL { ShareLink("Export test results", item: url) }
            }
        }
        .navigationTitle("Speech experiment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Stop", systemImage: "stop.fill") { runner.stop() }
                    .disabled(!runner.busy).accessibilityIdentifier("tts-stop")
            }
        }
        .onChange(of: selectedBackend) { _, backend in runner.select(backend) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { runner.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in runner.memoryWarning() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.didBecomeInactiveNotification)) { notification in
            let context = notification.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
            // Normal per-phrase release is not an interruption of the comparison batch.
            if context?.source != .app { runner.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { runner.stop() }
        }
        .onDisappear { runner.stop(leaving: true) }
    }
}
#endif
