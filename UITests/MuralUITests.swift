import XCTest
import MuralCore

private func ownedTalkStopButton(_ app: XCUIApplication) -> XCUIElement {
    let cancel = app.buttons["speech-setup-cancel"]
    return cancel.exists ? cancel : app.buttons["local-conversation-end"]
}

private func replaceTranscriptText(_ text: String, input: XCUIElement, app: XCUIApplication) {
    input.tap()
    input.press(forDuration: 1)
    let selectAll = app.menuItems["Select All"].exists ? app.menuItems["Select All"] : app.buttons["Select All"]
    XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "Use native selection; do not assume the caret starts at the end")
    selectAll.tap()
    input.typeText(text)
    XCTAssertEqual(input.value as? String, text)
}

final class MuralUITests: XCTestCase {
    func testBreezeSimplifiedDisplayPreservesRawRolesAndEnglish() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-existing-user", "--preview-breeze-script"]
        app.launch()
        defer { app.terminate() }
        let transcript = app.buttons["local-conversation-transcript"]
        guard transcript.waitForExistence(timeout: 15) else {
            XCTFail("Real converter/archive fixture did not complete")
            return
        }
        for _ in 0..<8 where !transcript.isHittable { app.swipeUp() }
        guard transcript.isHittable else { XCTFail("Transcript is not reachable"); return }
        transcript.tap()
        XCTAssertTrue(app.staticTexts["后天 book a flight，谢谢！怎么 API"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Assistant 後天 API"].exists, "Assistant role must not be script-converted")
        XCTAssertTrue(app.staticTexts["Typed 後天 API"].exists, "Typed wording must remain exact")
        let disclosure = app.descendants(matching: .any).matching(identifier: "transcript-script-original").firstMatch
        for _ in 0..<8 where !disclosure.isHittable { app.swipeUp() }
        guard disclosure.isHittable else { XCTFail("Raw-recognition disclosure is not reachable"); return }
        disclosure.tap()
        let originals = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "後天 book a flight，謝謝！怎么 API"))
        XCTAssertTrue(originals.firstMatch.waitForExistence(timeout: 5), "Raw Traditional recognition must remain inspectable")
        keepScreenshot("Breeze Simplified display, unchanged roles and raw disclosure", app: app)
        disclosure.tap()
        XCTAssertTrue(app.staticTexts["后天 book a flight，谢谢！怎么 API"].exists)
        let transcriptView = app.scrollViews.matching(NSPredicate(format: "identifier BEGINSWITH 'transcript-session-'" )).firstMatch
        let sessionID = String(transcriptView.identifier.dropFirst("transcript-session-".count))
        _ = try XCTUnwrap(UUID(uuidString: sessionID))
        app.navigationBars["Our conversation"].buttons["Done"].tap()
        app.tabBars.buttons["Words"].tap()
        let history = app.buttons["Past conversations"]
        for _ in 0..<8 where !history.isHittable { app.swipeUp() }
        history.tap()
        let savedSession = app.buttons["history-session-\(sessionID)"]
        XCTAssertTrue(savedSession.waitForExistence(timeout: 5)); savedSession.tap()
        let savedTranscript = app.scrollViews["transcript-session-\(sessionID)"]
        let edit = savedTranscript.buttons.matching(identifier: "Edit").element(boundBy: 1) // This fixture's spoken passage, not its typed passage.
        for _ in 0..<8 where !edit.isHittable { app.swipeUp() }
        edit.tap()
        let input = app.descendants(matching: .any).matching(identifier: "transcript-edit-text").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "后天 book a flight，谢谢！怎么 API")
        replaceTranscriptText("Explicit API Kevin 17 edit.", input: input, app: app)
        app.navigationBars["What you said"].buttons["Save"].tap()
        XCTAssertTrue(savedTranscript.staticTexts["Explicit API Kevin 17 edit."].waitForExistence(timeout: 5))
        XCTAssertFalse(savedTranscript.staticTexts["后天 book a flight，谢谢！怎么 API"].exists)
        let original = savedTranscript.buttons["transcript-script-original"].firstMatch
        XCTAssertTrue(original.label.contains("edited wording"))
        for _ in 0..<8 where !original.isHittable { app.swipeUp() }
        original.tap()
        XCTAssertTrue(originals.firstMatch.waitForExistence(timeout: 5))
        keepScreenshot("Explicit edit removes projection and retains original recognition", app: app)
    }

    func testSimplifiedBreezeMissingAssetsDoesNotOfferFireRed() {
        let app = setupPreview("unavailable", meaningLanguage: "Simplified Chinese")
        defer { restorePremium(app) }
        let error = app.staticTexts["speech-setup-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("isn’t available to download"))
        XCTAssertFalse(app.buttons["speech-download-confirm"].exists)
        XCTAssertFalse(app.buttons["local-conversation-record-send"].exists)
        XCTAssertTrue(localRecognizer(app).label.contains("breeze-asr25-pal8-v1"))
        XCTAssertTrue(app.staticTexts["local-asr-backend"].label.contains("Simplified display"))
        keepScreenshot("Missing shared Breeze is not a FireRed download request", app: app)
    }

    private func setConversationMode(_ selection: String, app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        for _ in 0..<8 where !settings.isHittable { app.swipeDown() }
        settings.tap()
        let mode = app.buttons["settings-conversation-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        if mode.isEnabled {
            mode.tap()
            app.buttons[selection].tap()
        }
        app.buttons["Done"].tap()
    }
    private func selectSetting(_ rowID: String, option: String, app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        for _ in 0..<8 where !settings.isHittable { app.swipeDown() }
        settings.tap()
        let row = app.buttons[rowID]
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.isEnabled)
        row.tap()
        let choice = app.buttons[option]
        for _ in 0..<8 where !choice.isHittable { app.swipeUp() }
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertTrue(choice.isHittable)
        choice.tap()
        app.buttons["Done"].tap()
    }
    private func setLearningLanguage(_ selection: String, app: XCUIApplication) {
        selectSetting("learning-language-picker", option: selection, app: app)
    }
    private func setMeaningLanguage(_ selection: String, app: XCUIApplication) {
        selectSetting("settings-meaning-language", option: selection, app: app)
    }
    private func localRecognizer(_ app: XCUIApplication) -> XCUIElement {
        let details = app.buttons["On-device details & diagnostics"]
        for _ in 0..<8 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.isHittable)
        let recognizer = app.staticTexts["local-recognizer"]
        if !recognizer.exists { details.tap() }
        XCTAssertTrue(recognizer.waitForExistence(timeout: 5))
        return recognizer
    }
    private func setupPreview(_ scenario: String, meaningLanguage: String = "Traditional Chinese", largeText: Bool = false, clearSpeechPreparation: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-existing-user", "--preview-speech-setup=\(scenario)"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if clearSpeechPreparation { app.launchArguments.append("--preview-clear-speech-preparation") }
        app.launch()
        setConversationMode("On-device", app: app)
        setLearningLanguage("English · International", app: app)
        setMeaningLanguage(meaningLanguage, app: app)
        let start = app.buttons["local-conversation-start"]
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        start.tap()
        return app
    }
    private func restorePremium(_ app: XCUIApplication) {
        // Mode is a UserDefaults preference even when preview learning data is temporary.
        setConversationMode("GPT-Live", app: app)
    }
    private func keepScreenshot(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testTaiwanSpeechPackageUnavailableDoesNotStartOrSwitchModes() {
        let app = setupPreview("unavailable")
        defer { restorePremium(app) }
        let error = app.staticTexts["speech-setup-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("isn’t available to download"))
        XCTAssertFalse(app.buttons["speech-download-confirm"].exists)
        XCTAssertFalse(app.buttons["speech-models-open"].exists)
        XCTAssertFalse(app.buttons["local-conversation-end"].exists)
        let originalError = error.label
        app.buttons["local-conversation-start"].tap()
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, originalError)
        XCTAssertFalse(app.buttons["local-speech-pair"].exists)
        XCTAssertEqual(app.staticTexts["conversation-language-pair"].label, "English · Traditional Chinese")
        XCTAssertTrue(localRecognizer(app).label.contains("breeze-asr25-pal8-v1"))
        keepScreenshot("Start explains unavailable download", app: app)
    }
    func testMeaningLanguageSelectsOnDeviceRecognizerAndUnsupportedCombinationsFailClosed() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-existing-user"]
        app.launch()
        setConversationMode("On-device", app: app)
        setLearningLanguage("English · International", app: app)
        setMeaningLanguage("Vietnamese", app: app)
        let languagePair = app.staticTexts["conversation-language-pair"]
        XCTAssertEqual(languagePair.label, "English · Vietnamese")
        XCTAssertFalse(app.buttons["local-speech-pair"].exists)
        XCTAssertTrue(localRecognizer(app).label.contains("phowhisper"))

        setMeaningLanguage("Traditional Chinese", app: app)
        XCTAssertEqual(languagePair.label, "English · Traditional Chinese")
        XCTAssertTrue(localRecognizer(app).label.contains("breeze-asr25-pal8-v1"))

        setMeaningLanguage("Simplified Chinese", app: app)
        XCTAssertEqual(languagePair.label, "English · Simplified Chinese")
        XCTAssertTrue(localRecognizer(app).label.contains("breeze-asr25-pal8-v1"))
        XCTAssertTrue(app.staticTexts["local-asr-backend"].label.contains("Simplified display"))
        XCTAssertFalse(app.buttons["local-speech-pair"].exists)
        // No Prepare here: the changed Settings mapping is model-free. Missing shared
        // Breeze assets are covered through the setup fixture in the companion check.
        keepScreenshot("Meaning language selects Breeze plus Simplified display", app: app)

        setMeaningLanguage("French", app: app)
        XCTAssertEqual(languagePair.label, "English · French")
        let start = app.buttons["local-conversation-start"]
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        start.tap()
        let alert = app.alerts["A little interruption"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Vietnamese, Traditional Chinese, or Simplified Chinese meanings")).firstMatch.exists)
        alert.buttons["OK"].tap()

        setMeaningLanguage("Traditional Chinese", app: app)
        app.buttons["Settings"].tap()
        let learning = app.buttons["learning-language-picker"]
        for _ in 0..<8 where !learning.isHittable { app.swipeUp() }
        learning.tap()
        app.buttons["French · France"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(languagePair.label, "French · Traditional Chinese")
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Vietnamese, Traditional Chinese, or Simplified Chinese meanings")).firstMatch.exists)
        alert.buttons["OK"].tap()
    }
    func testSpeechSetupConsentThenAutomaticContinuation() {
        let app = setupPreview("download")
        defer { restorePremium(app) }
        XCTAssertTrue(app.buttons["speech-download-decline"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.progressIndicators["speech-setup-download-progress"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["speech-download-decline"].frame.height, 44)
        keepScreenshot("Download consent before any transfer", app: app)
        app.buttons["speech-download-decline"].tap()
        XCTAssertTrue(app.buttons["local-conversation-start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["local-conversation-transcript"].exists)
        app.buttons["local-conversation-start"].tap()
        XCTAssertTrue(app.buttons["speech-download-confirm"].waitForExistence(timeout: 5))
        app.buttons["speech-download-confirm"].tap()
        XCTAssertTrue(app.buttons["local-conversation-end"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["conversation-status"].label.contains("Ready"))
        XCTAssertFalse(app.staticTexts["speech-setup-stage"].exists)
        XCTAssertEqual(ownedTalkStopButton(app).identifier, "local-conversation-end")
        ownedTalkStopButton(app).tap()
        XCTAssertTrue(app.buttons["local-conversation-start"].waitForExistence(timeout: 5))
    }
    func testSpeechSetupCancelKeepsAdmissionClosedUntilDrain() {
        let app = setupPreview("drain")
        defer { restorePremium(app) }
        XCTAssertTrue(app.buttons["speech-download-confirm"].waitForExistence(timeout: 5))
        app.buttons["speech-download-confirm"].tap()
        let stage = app.staticTexts["speech-setup-stage"]
        expectation(for: NSPredicate(format: "label == %@", "Preparing encoder"), evaluatedWith: stage)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(app.progressIndicators["speech-setup-download-progress"].exists)
        keepScreenshot("Native setup has no fake percentage", app: app)
        XCTAssertGreaterThanOrEqual(app.buttons["speech-setup-cancel"].frame.height, 44)
        XCTAssertEqual(ownedTalkStopButton(app).identifier, "speech-setup-cancel")
        ownedTalkStopButton(app).tap()
        XCTAssertEqual(stage.label, "Setup cancelled")
        let start = app.buttons["local-conversation-start"]
        XCTAssertTrue(start.exists)
        XCTAssertFalse(start.isEnabled)
        XCTAssertFalse(app.buttons["local-speech-pair"].exists)
        XCTAssertFalse(app.buttons["local-tutor-probe"].isEnabled)
        setMeaningLanguage("Vietnamese", app: app)
        XCTAssertEqual(app.staticTexts["conversation-language-pair"].label, "English · Vietnamese")
        XCTAssertTrue(localRecognizer(app).label.contains("breeze-asr25-pal8-v1"))
        XCTAssertTrue(app.staticTexts["local-asr-backend"].label.contains("Breeze PAL8"))
        XCTAssertEqual(stage.label, "Setup cancelled")
        XCTAssertFalse(start.isEnabled) // Selecting a future pair must not release the old owner.
        keepScreenshot("Cancel acknowledges immediately; next language is selectable", app: app)
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.buttons["Settings"].isHittable)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings-conversation-mode"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.tabBars.buttons["Talk"].tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 40)
        XCTAssertTrue(start.isEnabled)
        XCTAssertFalse(app.buttons["local-conversation-transcript"].exists)
        XCTAssertFalse(app.buttons["local-conversation-end"].exists)
        XCTAssertTrue(app.buttons["local-tutor-probe"].isEnabled)
        // Retry is explicit, and cancelling the new consent does not resurrect the old draft.
        start.tap()
        XCTAssertTrue(app.buttons["speech-download-decline"].waitForExistence(timeout: 5))
        app.buttons["speech-download-decline"].tap()
        XCTAssertTrue(start.isEnabled)
        XCTAssertFalse(app.buttons["local-conversation-transcript"].exists)
    }
    func testSpeechSetupCancelAtLargeTextThenBackgroundAndRetry() {
        let app = setupPreview("drain", largeText: true)
        defer { restorePremium(app) }
        let confirm = app.buttons["speech-download-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        for _ in 0..<10 where !confirm.isHittable { app.swipeUp() }
        confirm.tap()
        let stage = app.staticTexts["speech-setup-stage"]
        expectation(for: NSPredicate(format: "label == %@", "Preparing encoder"), evaluatedWith: stage)
        waitForExpectations(timeout: 8)
        let cancel = app.buttons["speech-setup-cancel"]
        for _ in 0..<8 where !cancel.isHittable { app.swipeUp() }
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        XCTAssertEqual(stage.label, "Setup cancelled")
        let start = app.buttons["local-conversation-start"]
        XCTAssertFalse(start.isEnabled)
        XCTAssertFalse(app.buttons["local-tutor-probe"].isEnabled)
        keepScreenshot("Cancelled setup at largest text size", app: app)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.buttons["local-conversation-end"].exists)
        XCTAssertFalse(app.buttons["speech-download-confirm"].exists)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 40)
        XCTAssertFalse(app.buttons["local-conversation-transcript"].exists)
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        start.tap() // Explicit new start reuses completed files; cancellation does not erase them.
        XCTAssertFalse(app.buttons["speech-download-confirm"].exists)
        let cancelAgain = app.buttons["speech-setup-cancel"]
        XCTAssertTrue(cancelAgain.waitForExistence(timeout: 5))
        for _ in 0..<10 where !cancelAgain.isHittable { app.swipeUp() }
        cancelAgain.tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 40)
    }

    func testSpeechSetupCachedAndFailureRecovery() {
        var app = setupPreview("cached")
        XCTAssertFalse(app.buttons["speech-download-confirm"].exists)
        XCTAssertTrue(app.buttons["local-conversation-end"].waitForExistence(timeout: 5))
        app.buttons["local-conversation-end"].tap()
        restorePremium(app); app.terminate()
        app = setupPreview("failure")
        defer { restorePremium(app) }
        XCTAssertTrue(app.buttons["speech-download-confirm"].waitForExistence(timeout: 5))
        app.buttons["speech-download-confirm"].tap()
        XCTAssertTrue(app.staticTexts["speech-setup-error"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["local-conversation-start"].isEnabled)
        XCTAssertFalse(app.buttons["local-conversation-transcript"].exists)
        XCTAssertEqual(app.buttons["local-conversation-start"].label, "Resume setup")
        app.buttons["local-conversation-start"].tap()
        XCTAssertFalse(app.buttons["speech-download-confirm"].exists) // The verified fixture inventory survives.
        XCTAssertTrue(app.staticTexts["speech-setup-error"].waitForExistence(timeout: 8))
    }
    func testMemoryWarningKeepsTalkActiveAndPreservesTurns() {
        // The real notifications fire after two synthetic turns. Ready is shown only after
        // the four-second child drains. No ASR model is loaded, so microphone readiness is not asserted.
        let app = setupPreview("memory-warning-drain", meaningLanguage: "Simplified Chinese")
        defer { restorePremium(app) }
        let status = app.staticTexts["conversation-status"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Ready · Tap Record"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        XCTAssertTrue(app.buttons["local-conversation-record-send"].exists)
        XCTAssertFalse(app.buttons["local-memory-pressure-resume"].exists)
        XCTAssertFalse(app.staticTexts["conversation-notice"].exists)
        XCTAssertFalse(app.alerts["A little interruption"].exists)
        XCTAssertTrue(app.staticTexts["I went for a walk by the river."].exists)
        XCTAssertTrue(app.staticTexts["That sounds peaceful. What did you enjoy most?"].exists)
        keepScreenshot("Memory warning leaves Talk active without Resume", app: app)
        app.buttons["local-conversation-end"].tap()
        app.buttons["local-conversation-transcript"].tap()
        XCTAssertTrue(app.staticTexts["I went for a walk by the river."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["That sounds peaceful. What did you enjoy most?"].exists)
        app.buttons["Done"].tap()
    }

    func testMemoryCeilingPausesSpeechUntilExplicitResumeAndPreservesTurns() {
        let app = setupPreview("memory-ceiling-drain")
        defer { restorePremium(app) }

        let status = app.staticTexts["conversation-status"]
        let resume = app.buttons["local-memory-pressure-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        XCTAssertTrue(resume.isHittable, "Resume should be visible while speech is paused")
        XCTAssertEqual(status.label, "Speech paused · Tap Resume to continue")
        XCTAssertFalse(resume.isEnabled)
        XCTAssertFalse(app.staticTexts["conversation-notice"].exists)
        XCTAssertFalse(app.alerts["A little interruption"].exists)
        keepScreenshot("Speech paused quietly while the conversation stays visible", app: app)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(status.label, "Speech paused · Tap Resume to continue")
        app.tabBars.buttons["Words"].tap()
        app.tabBars.buttons["Talk"].tap()
        XCTAssertEqual(status.label, "Speech paused · Tap Resume to continue")

        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: resume)
        waitForExpectations(timeout: 8)
        resume.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Ready"), evaluatedWith: status)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.staticTexts["That sounds peaceful. What did you enjoy most?"].exists)
        XCTAssertTrue(app.staticTexts["I went for a walk by the river."].exists)
        keepScreenshot("Conversation after explicit speech resume", app: app)

        app.buttons["local-conversation-end"].tap()
        app.buttons["local-conversation-transcript"].tap()
        XCTAssertTrue(app.staticTexts["I went for a walk by the river."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["That sounds peaceful. What did you enjoy most?"].exists)
        app.buttons["Done"].tap()
    }

    func testSuccessfulSpeechPreparationResumesCompactlyWithoutHidingConversation() {
        let app = setupPreview("resume", clearSpeechPreparation: true)

        let stage = app.staticTexts["speech-setup-stage"]
        expectation(for: NSPredicate(format: "label == %@", "Preparing encoder"), evaluatedWith: stage)
        waitForExpectations(timeout: 5)

        let status = app.staticTexts["conversation-status"]
        let assistant = app.staticTexts["target-caption"]
        let learner = app.staticTexts.matching(NSPredicate(format: "label == %@", "I went for a walk by the river.")).firstMatch
        XCTAssertTrue(app.buttons["local-conversation-end"].waitForExistence(timeout: 10))
        XCTAssertTrue(assistant.waitForExistence(timeout: 5))
        XCTAssertTrue(learner.waitForExistence(timeout: 5))
        keepScreenshot("Conversation after first speech preparation", app: app)

        XCUIDevice.shared.press(.home)
        app.activate()

        let resuming = NSPredicate(format: "label == %@", "Getting your speech ready again…")
        expectation(for: resuming, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(stage.exists)
        XCTAssertTrue(app.buttons["local-conversation-end"].isEnabled)
        XCTAssertFalse(app.buttons["local-conversation-record-send"].isEnabled)
        XCTAssertFalse(app.buttons["Type instead"].isEnabled)
        XCTAssertFalse(app.buttons["A little help"].isEnabled)
        XCTAssertTrue(assistant.exists)
        XCTAssertTrue(learner.exists)
        keepScreenshot("Conversation stays visible during compact speech resume", app: app)

        expectation(for: NSPredicate(format: "label != %@", "Getting your speech ready again…"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(assistant.exists)
        XCTAssertTrue(learner.exists)
    }

    func testSpeechSetupBackgroundDoesNotRestartDownload() {
        let app = setupPreview("transitions")
        defer { restorePremium(app) }
        XCTAssertTrue(app.buttons["speech-download-confirm"].waitForExistence(timeout: 5))
        app.buttons["speech-download-confirm"].tap()
        waitForSetupStage("Preparing encoder", app: app)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(app.buttons["speech-download-confirm"].exists)
        XCTAssertFalse(app.buttons["local-conversation-start"].exists) // SAME owner continues without another tap.
        XCTAssertTrue(app.buttons["local-conversation-end"].waitForExistence(timeout: 25))
        app.buttons["local-conversation-end"].tap()
    }

    private func waitForSetupStage(_ title: String, app: XCUIApplication, timeout: TimeInterval = 15) {
        let stage = app.staticTexts["speech-setup-stage"]
        let matching = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", title), object: stage)
        XCTAssertEqual(XCTWaiter.wait(for: [matching], timeout: timeout), .completed, "Missing transition: \(title)")
    }

    func testSpeechSetupChecklistTransitionsUseOnlyDownloadPercentages() {
        let app = setupPreview("transitions")
        defer { restorePremium(app) }
        XCTAssertTrue(app.buttons["speech-download-confirm"].waitForExistence(timeout: 5))
        app.buttons["speech-download-confirm"].tap()
        waitForSetupStage("Downloading speech", app: app)
        XCTAssertEqual(app.descendants(matching: .any)["speech-setup-step-checking"].value as? String, "Complete")
        let downloadProgress = app.progressIndicators["speech-setup-download-progress"]
        XCTAssertTrue(downloadProgress.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["speech-setup-step-download"].value as? String, "Current")
        keepScreenshot("Managed speech download progress and checklist", app: app)
        waitForSetupStage("Preparing voice", app: app)
        XCTAssertFalse(app.progressIndicators["speech-setup-download-progress"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["speech-setup-step-download"].value as? String, "Complete")
        XCTAssertEqual(app.descendants(matching: .any)["speech-setup-step-verification"].value as? String, "Complete")
        waitForSetupStage("Preparing encoder", app: app)
        XCTAssertEqual(app.descendants(matching: .any)["speech-setup-step-voice"].value as? String, "Complete")
        XCTAssertFalse(app.progressIndicators["speech-setup-download-progress"].exists)
        XCTAssertTrue(app.staticTexts["speech-setup-away-policy"].label.contains("Keep Mural open"))
        waitForSetupStage("Preparing decoder", app: app)
        XCTAssertEqual(app.descendants(matching: .any)["speech-setup-step-recognition"].value as? String, "Current")
        XCTAssertFalse(app.progressIndicators["speech-setup-download-progress"].exists)
        XCTAssertTrue(app.buttons["local-conversation-end"].waitForExistence(timeout: 10))
        app.buttons["local-conversation-end"].tap()
    }

    func testSpeechSetupColdRelaunchRequiresResumeAndRechecksRetainedInventory() {
        let app = XCUIApplication()
        let run = UUID().uuidString
        app.launchArguments = ["--preview", "--preview-existing-user", "--preview-speech-setup=transitions", "--preview-setup-run=\(run)"]
        app.launch()
        setConversationMode("On-device", app: app)
        setLearningLanguage("English · International", app: app)
        setMeaningLanguage("Vietnamese", app: app)
        let start = app.buttons["local-conversation-start"]
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["speech-download-confirm"].waitForExistence(timeout: 5))
        app.buttons["speech-download-confirm"].tap()
        waitForSetupStage("Preparing encoder", app: app)
        app.terminate() // Never uninstall or clear application/model data.
        app.launch()
        // Preview learning preferences are intentionally in-memory; reselect only their identity.
        // No Start/Resume action is performed by these Settings changes.
        setConversationMode("On-device", app: app)
        setLearningLanguage("English · International", app: app)
        setMeaningLanguage("Vietnamese", app: app)
        defer { restorePremium(app) }
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(start.label, "Resume setup")
        XCTAssertFalse(app.buttons["local-conversation-end"].exists)
        XCTAssertFalse(app.buttons["speech-setup-cancel"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["speech-setup-step-voice"].exists) // No persisted Ready/checkmarks.
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertFalse(app.buttons["speech-download-confirm"].exists)
        waitForSetupStage("Preparing voice", app: app)
        XCTAssertFalse(app.progressIndicators["speech-setup-download-progress"].exists)
        XCTAssertTrue(app.buttons["local-conversation-end"].waitForExistence(timeout: 15))
        app.buttons["local-conversation-end"].tap()
    }

    func testSpeechSetupForegroundReturnWaitsForNativeDrain() {
        let app = setupPreview("drain")
        defer { restorePremium(app) }
        XCTAssertTrue(app.buttons["speech-download-confirm"].waitForExistence(timeout: 5))
        app.buttons["speech-download-confirm"].tap()
        waitForSetupStage("Preparing encoder", app: app)
        XCUIDevice.shared.press(.home); app.activate()
        waitForSetupStage("Finishing the current step", app: app)
        XCTAssertFalse(app.buttons["local-conversation-start"].exists)
        XCTAssertFalse(app.buttons["local-conversation-end"].exists)
        XCTAssertFalse(app.buttons["local-tutor-probe"].isEnabled)
        app.buttons["speech-setup-cancel"].tap()
        let start = app.buttons["local-conversation-start"]
        XCTAssertFalse(start.isEnabled)
        let drained = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [drained], timeout: 40), .completed)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(start.isEnabled)
        XCTAssertEqual(start.label, "Prepare & start") // Cancel never auto-resumes.
        XCTAssertFalse(app.buttons["local-conversation-end"].exists)
    }
    func testSpeechSetupConsentAtAccessibilityTextSize() {
        let app = setupPreview("download", largeText: true)
        defer { restorePremium(app) }
        let confirm = app.buttons["speech-download-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        for _ in 0..<10 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.isHittable)
        XCTAssertGreaterThanOrEqual(confirm.frame.minX, 0)
        XCTAssertLessThanOrEqual(confirm.frame.maxX, app.frame.maxX)
        keepScreenshot("Download consent at largest text size", app: app)
        let decline = app.buttons["speech-download-decline"]
        for _ in 0..<5 where !decline.isHittable { app.swipeUp() }
        XCTAssertTrue(decline.isHittable)
        decline.tap()
        XCTAssertTrue(app.buttons["local-conversation-start"].waitForExistence(timeout: 5))
    }

    func testThermalInterruptionDuringApprovedSetup() { verifySetupInterruption("thermal-setup") }
    func testAudioInterruptionDuringApprovedSetup() { verifySetupInterruption("audio-setup") }
    func testRouteInterruptionDuringApprovedSetup() { verifySetupInterruption("route-setup") }
    func testMemoryCeilingInterruptionDuringApprovedSetup() { verifySetupInterruption("memory-ceiling-setup") }

    func testMemoryWarningDuringApprovedSetupDoesNotInterrupt() {
        let app = setupPreview("memory-warning-setup", meaningLanguage: "Simplified Chinese")
        defer { restorePremium(app) }
        XCTAssertTrue(app.buttons["speech-download-confirm"].waitForExistence(timeout: 5))
        app.buttons["speech-download-confirm"].tap()
        let status = app.staticTexts["conversation-status"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Ready · Tap Record"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        XCTAssertTrue(app.buttons["local-conversation-record-send"].exists)
        XCTAssertFalse(app.buttons["local-memory-pressure-resume"].exists)
        XCTAssertFalse(app.buttons["speech-setup-cancel"].exists)
        XCTAssertFalse(app.staticTexts["speech-setup-error"].exists)
        XCTAssertFalse(app.alerts["A little interruption"].exists)
        keepScreenshot("Memory warning does not cancel approved speech setup", app: app)
        app.buttons["local-conversation-end"].tap()
    }

    private func verifySetupInterruption(_ scenario: String) {
        let app = setupPreview(scenario)
        defer { restorePremium(app) }
        XCTAssertTrue(app.buttons["speech-download-confirm"].waitForExistence(timeout: 5))
        app.buttons["speech-download-confirm"].tap()
        let thermal = scenario == "thermal-setup"
        if thermal {
            XCTAssertTrue(app.alerts["Your iPhone needs to cool down"].waitForExistence(timeout: 10))
            app.alerts.buttons["OK"].tap()
        }
        let resume = app.buttons[thermal ? "local-thermal-resume" : "local-conversation-start"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        XCTAssertFalse(resume.isEnabled) // The held child still owns admission.
        XCTAssertFalse(app.buttons["local-conversation-end"].exists)
        app.buttons["preview-finish-setup-drain"].tap()
        let drained = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: resume)
        XCTAssertEqual(XCTWaiter.wait(for: [drained], timeout: 15), .completed)
        if thermal {
            XCTAssertFalse(app.buttons["local-conversation-start"].exists) // Only one recovery action.
            XCTAssertEqual(app.staticTexts["speech-setup-stage"].label, "Resume setup")
        } else {
            XCTAssertEqual(app.buttons["local-conversation-start"].label, "Resume setup")
        }
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(resume.isEnabled) // Cooling/foreground return alone did not restart.
        XCTAssertFalse(app.buttons["local-conversation-end"].exists)
        keepScreenshot("Interrupted setup awaiting explicit resume - \(scenario)", app: app)
        resume.tap()
        XCTAssertFalse(app.buttons["speech-download-confirm"].exists) // Retained approval and inventory.
        XCTAssertTrue(app.buttons["local-conversation-end"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["speech-setup-cancel"].exists)
        XCTAssertFalse(app.staticTexts["speech-setup-stage"].exists)
        keepScreenshot("Setup resumed into conversation - \(scenario)", app: app)
        app.buttons["local-conversation-end"].tap()
    }

    func testThermalAlertAndExplicitResume() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-thermal-stop"]
        app.launch()
        let title = "Your iPhone needs to cool down"
        XCTAssertTrue(app.alerts[title].waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label == %@", "iOS reports that your iPhone is too warm. Mural has paused speech to protect performance. Let your phone cool down, then tap Resume.")).firstMatch.exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Thermal pause alert"; image.lifetime = .keepAlways; add(image)
        app.alerts.buttons["OK"].tap()
        let resume = app.buttons["local-thermal-resume"]
        XCTAssertTrue(resume.isEnabled)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts[title].exists) // Foregrounding did not attempt recovery.
        resume.tap()
        XCTAssertTrue(app.alerts[title].waitForExistence(timeout: 5)) // Still hot: no inference.
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["local-conversation-record-send"].isEnabled)
        app.buttons["local-conversation-end"].tap()
    }

    func testMuralVoiceSelectionPersists() {
        let app = launch(ended: true)
        func openVoice() -> XCUIElement {
            app.buttons["Settings"].tap()
            let backend = app.buttons["tts-talk-backend"]
            backend.tap(); app.buttons["Mural Voice"].tap()
            let picker = app.buttons["tts-supertonic-voice"]
            for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
            return picker
        }
        var picker = openVoice()
        picker.tap()
        XCTAssertTrue(app.staticTexts["Female voices"].exists)
        XCTAssertTrue(app.staticTexts["Male voices"].exists)
        for voice in ["Bella", "Clara", "Maya", "Nora", "Zoe", "Adam", "Jack", "Leo", "Ethan", "Theo"] {
            XCTAssertTrue(app.buttons[voice].exists)
        }
        let menuImage = XCTAttachment(screenshot: app.screenshot())
        menuImage.name = "Mural Voice groups"; menuImage.lifetime = .keepAlways; add(menuImage)
        app.buttons["Bella"].tap()
        XCTAssertTrue(picker.label.contains("Bella") || (picker.value as? String ?? "").contains("Bella"))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Mural Voice settings"; image.lifetime = .keepAlways; add(image)
        app.terminate(); app.launch()
        picker = openVoice()
        XCTAssertTrue(picker.label.contains("Bella") || (picker.value as? String ?? "").contains("Bella"))
        picker.tap(); app.buttons["Theo"].tap()
        XCTAssertTrue(picker.label.contains("Theo") || (picker.value as? String ?? "").contains("Theo"))

        var speed = app.buttons["tts-supertonic-speed"]
        for _ in 0..<3 where !speed.isHittable { app.swipeUp() }
        speed.tap(); app.buttons["1.5× · Very fast"].tap()
        XCTAssertTrue(speed.label.contains("1.5") || (speed.value as? String ?? "").contains("1.5"))
        app.terminate(); app.launch()
        _ = openVoice()
        speed = app.buttons["tts-supertonic-speed"]
        for _ in 0..<3 where !speed.isHittable { app.swipeUp() }
        XCTAssertTrue(speed.label.contains("1.5") || (speed.value as? String ?? "").contains("1.5"))
        speed.tap(); app.buttons["1.0× · Normal"].tap()
    }

    func testOnDeviceVoiceSelectionPersists() {
        let app = launch(ended: true)
        func openBackend() -> XCUIElement {
            app.buttons["Settings"].tap()
            return app.buttons["tts-talk-backend"]
        }
        var picker = openBackend()
        XCTAssertTrue(picker.isEnabled)
        let menuWidth = picker.frame.width
        picker.tap(); app.buttons["Apple"].tap()
        XCTAssertEqual(picker.frame.width, menuWidth, accuracy: 0.5)
        assertReselectingVoiceKeepsRowStable("Apple", picker: picker, app: app)
        app.terminate(); app.launch()
        picker = openBackend()
        XCTAssertTrue(picker.label.contains("Apple") || (picker.value as? String ?? "").contains("Apple"), picker.debugDescription)
        picker.tap(); app.buttons["Mural Voice"].tap()
        XCTAssertEqual(picker.frame.width, menuWidth, accuracy: 0.5)
        assertReselectingVoiceKeepsRowStable("Mural Voice", picker: picker, app: app)
        app.terminate(); app.launch()
        picker = openBackend()
        XCTAssertTrue(picker.label.contains("Mural Voice") || (picker.value as? String ?? "").contains("Mural Voice"), picker.debugDescription)
    }

    private func assertReselectingVoiceKeepsRowStable(_ voice: String, picker: XCUIElement, app: XCUIApplication) {
        let frame = picker.frame
        for _ in 0..<2 {
            picker.tap()
            app.buttons[voice].tap()
            XCTAssertEqual(picker.frame, frame)
            XCTAssertTrue(picker.label.contains(voice) || (picker.value as? String ?? "").contains(voice))
        }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Reselected \(voice)"; image.lifetime = .keepAlways; add(image)
    }

    #if MURAL_TTS_EXPERIMENT
    func testTTSExperimentSmokeContinuesAfterAudioSessionRelease() {
        let app = XCUIApplication()
        app.launchArguments = ["--tts-comparison"]
        app.launch()
        XCTAssertTrue(app.buttons["tts-prepare"].waitForExistence(timeout: 10))
        app.buttons["tts-prepare"].tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["tts-play"])
        waitForExpectations(timeout: 10)
        for _ in 0..<3 where !app.buttons["tts-smoke"].isHittable { app.swipeUp() }
        app.buttons["tts-smoke"].tap()
        for _ in 0..<3 where !app.staticTexts["tts-summary"].isHittable { app.swipeUp() }
        expectation(for: NSPredicate(format: "label == %@", "5 completed; 0 failed or cancelled."), evaluatedWith: app.staticTexts["tts-summary"])
        waitForExpectations(timeout: 90)
        // Let the final app-initiated deactivation arrive: preparation must remain usable.
        expectation(for: NSPredicate(format: "label == %@", "Finished."), evaluatedWith: app.staticTexts["tts-status"])
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["tts-error"].exists)
    }

    func testTTSExperimentLifecycleAndPCM() {
        let app = XCUIApplication()
        app.launchArguments = ["--tts-comparison"]
        app.launch()
        XCTAssertTrue(app.buttons["tts-prepare"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["tts-play"].isEnabled)
        for _ in 0..<3 where !app.buttons["tts-lifecycle"].isHittable { app.swipeUp() }
        app.buttons["tts-lifecycle"].tap()
        let status = app.staticTexts["tts-status"]
        expectation(for: NSPredicate(format: "label == %@", "Lifecycle checks passed. No audio or models used."), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        for id in ["tts-signal24", "tts-signal44"] {
            app.buttons[id].tap()
            expectation(for: NSPredicate(format: "label == %@", "Finished."), evaluatedWith: status)
            waitForExpectations(timeout: 10)
            XCTAssertFalse(app.staticTexts["tts-error"].exists)
        }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "TTS PCM completed"; image.lifetime = .keepAlways; add(image)
    }
    #endif

    private func launch(ended: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--preview"] + (ended ? ["--ended-conversation"] : [])
        app.launch()
        if !ended { setConversationMode("GPT-Live", app: app) }
        return app
    }
    func testGreetingAndMeaningToggle() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Hei!")
        XCTAssertFalse(app.buttons["Hide meaning subtitles"].exists)
        app.buttons["Settings"].tap()
        let meaningToggle = app.switches["Meaning subtitles"]
        XCTAssertTrue(meaningToggle.waitForExistence(timeout: 5))
        meaningToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["meaning-caption"])
        waitForExpectations(timeout: 5)
        app.buttons["Settings"].tap()
        app.switches["Meaning subtitles"].coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "Hi!")
    }
    func testThemeSurvivesNavigationToWords() {
        let app = launch()
        app.tabBars.buttons["Themes"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A coffee?")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["A coffee?"].exists)
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts["Your words."].exists)
        app.tabBars.buttons["Talk"].tap()
        XCTAssertTrue(app.staticTexts["A coffee?"].exists)
    }
    func testSettingsOfferSecureKeyEntryAndBackups() {
        let app = launch()
        app.buttons["Settings"].tap()
        if app.buttons["managed-account-settings"].exists {
            app.buttons["managed-account-settings"].tap()
            XCTAssertTrue(app.staticTexts["managed-sign-in-agreement"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["managed-google-sign-in"].isHittable || app.buttons["managed-apple-sign-in"].isHittable)
            XCTAssertFalse(app.staticTexts["managedAccountMessage"].exists)
            XCTAssertFalse(app.buttons["Buy credits"].exists)
            let accountScreen = XCTAttachment(screenshot: app.screenshot())
            accountScreen.name = "Configured account signup"; accountScreen.lifetime = .keepAlways; add(accountScreen)
            app.navigationBars["Account"].buttons.element(boundBy: 0).tap()
        }
        XCTAssertFalse(app.secureTextFields["api-key"].exists)
        let apiKeyDisclosure = app.buttons["advanced-api-key"]
        for _ in 0..<10 where !apiKeyDisclosure.exists { app.swipeUp() }
        XCTAssertTrue(apiKeyDisclosure.waitForExistence(timeout: 5))
        for _ in 0..<5 where !apiKeyDisclosure.isHittable { app.swipeUp() }
        apiKeyDisclosure.tap()
        if !app.secureTextFields["api-key"].exists { app.swipeUp() }
        XCTAssertTrue(app.secureTextFields["api-key"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["start-conversation"].exists)
    }

    func testSettingsKeepLicensesInNoticesWithoutTransportDetails() {
        let app = launch()
        app.buttons["Settings"].tap()
        for _ in 0..<6 {
            if app.buttons["Open-source notices"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["Open-source notices"].isHittable)
        XCTAssertFalse(app.staticTexts["WebRTC distribution by stasel, BSD 3-Clause. WebRTC includes third-party open-source components."].exists)
        XCTAssertFalse(app.links["WebRTC licenses"].exists)
        app.buttons["Open-source notices"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Google WebRTC")).firstMatch.waitForExistence(timeout: 5))
    }

    func testExistingUserCanDeclineThenAcceptAIConsentWithoutRepeatingOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-existing-user"]
        app.launch()
        setConversationMode("GPT-Live", app: app)
        XCTAssertTrue(app.buttons["start-conversation"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding-language-fr"].exists)
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.staticTexts["ai-consent-title"].waitForExistence(timeout: 5))
        app.buttons["ai-consent-decline"].tap()
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.staticTexts["ai-consent-title"].waitForExistence(timeout: 5))
        app.buttons["ai-consent-agree"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["ai-consent-title"].exists)
        XCTAssertFalse(app.buttons["onboarding-language-fr"].exists)
    }

    func testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding", "-mural.conversationMode", "GPT-Live"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-language-fr"].waitForExistence(timeout: 10))
        let languageScreen = XCTAttachment(screenshot: app.screenshot())
        languageScreen.name = "Onboarding - language"; languageScreen.lifetime = .keepAlways; add(languageScreen)
        app.buttons["onboarding-language-fr"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["onboarding-ai-consent"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "onboarding-privacy-policy").firstMatch.exists)
        XCTAssertEqual(app.buttons["onboarding-continue"].label, "Continue")
        app.buttons["onboarding-meaning-picker"].tap()
        app.buttons["Spanish"].tap()
        XCTAssertEqual(app.staticTexts["onboarding-meaning-example"].label, "¡Hola!")
        let meaningScreen = XCTAttachment(screenshot: app.screenshot())
        meaningScreen.name = "Onboarding - meanings and consent"; meaningScreen.lifetime = .keepAlways; add(meaningScreen)
        app.buttons["onboarding-continue"].tap()
        let targetCaption = app.staticTexts["target-caption"]
        let expectedGreeting = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Salut !"), object: targetCaption)
        XCTAssertEqual(XCTWaiter.wait(for: [expectedGreeting], timeout: 10), .completed)
        XCTAssertEqual(targetCaption.label, "Salut !")
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "¡Hola!")
        XCTAssertFalse(app.secureTextFields["api-key"].exists)
    }

    func testEnglishOnboardingOffersOtherMeaningsAndPreservesAnExplicitChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding", "-mural.conversationMode", "GPT-Live"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-language-en"].waitForExistence(timeout: 10))
        app.buttons["onboarding-language-en"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["onboarding-meaning-example"].label, "Hi!")
        app.buttons["onboarding-meaning-picker"].tap()
        app.buttons["Spanish"].tap()
        app.buttons["onboarding-back"].tap()
        app.buttons["onboarding-language-fr"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertEqual(app.staticTexts["onboarding-meaning-example"].label, "¡Hola!")
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "¡Hola!")
    }

    func testOnDeviceDefaultsOnFirstLaunchAndModeLivesInSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "-mural.conversationMode", ""]
        app.launch()
        XCTAssertFalse(app.buttons["conversation-mode"].exists)
        app.buttons["Settings"].tap()
        let mode = app.buttons["settings-conversation-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(mode.label.contains("On-device") || (mode.value as? String ?? "").contains("On-device"))
        app.buttons["Done"].tap()
    }

    func testSettingsDropdownTransitions() {
        let app = launch(ended: true)
        XCTAssertFalse(app.buttons["conversation-mode"].exists)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings-conversation-mode"].waitForExistence(timeout: 5))
        for (title, choices) in [
            ("Conversation mode", ["On-device", "On-device", "GPT-Live", "GPT-Live"]),
            ("Learning language", ["English · International", "English · International", "French · France", "French · France"]),
            ("Meaning language", ["Vietnamese", "Vietnamese", "English", "English"])
        ] {
            let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            var menuWidth: CGFloat?
            for choice in choices {
                for _ in 0..<5 where !menu.isHittable { app.swipeUp() }
                XCTAssertTrue(menu.isHittable)
                menu.tap()
                app.buttons[choice].tap()
                XCTAssertTrue(menu.label.contains(choice) || (menu.value as? String ?? "").contains(choice))
                XCTAssertGreaterThanOrEqual(menu.frame.minX, 0)
                XCTAssertLessThanOrEqual(menu.frame.maxX, app.frame.maxX)
                if let menuWidth { XCTAssertEqual(menu.frame.width, menuWidth, accuracy: 0.5) }
                menuWidth = menu.frame.width
                if title == "Learning language" {
                    let label = app.staticTexts[title].frame
                    XCTAssertTrue(menu.frame.minY >= label.maxY || menu.frame.minX >= label.maxX, "Title and selection must not overlap")
                }
                let image = XCTAttachment(screenshot: app.screenshot())
                image.name = "\(title) - \(choice)"; image.lifetime = .keepAlways; add(image)
            }
        }
    }

    func testSettingsLanguageRowAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--ended-conversation", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["Settings"].tap()
        let menu = app.buttons["learning-language-picker"]
        for _ in 0..<10 where !menu.isHittable { app.swipeUp() }
        XCTAssertTrue(menu.isHittable)
        let title = app.staticTexts["Learning language"]
        XCTAssertGreaterThanOrEqual(menu.frame.minY, title.frame.maxY)
        XCTAssertGreaterThanOrEqual(menu.frame.minX, 0)
        XCTAssertLessThanOrEqual(menu.frame.maxX, app.frame.maxX)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Settings at accessibility text size"; image.lifetime = .keepAlways; add(image)
    }

    func testSettingsCanSwitchToEnglishAndFrench() {
        let app = launch()
        for (selection, greeting) in [("English · International", "Hi!"), ("French · France", "Salut !")] {
            app.buttons["Settings"].tap()
            app.buttons["learning-language-picker"].tap()
            app.buttons[selection].tap()
            app.buttons["Done"].tap()
            XCTAssertEqual(app.staticTexts["target-caption"].label, greeting)
        }
    }
    func testLanguageSwitchUpdatesGreetingThemesAndWords() {
        let app = launch()
        app.tabBars.buttons["Themes"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A coffee?")).firstMatch.tap()
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        app.buttons["Spanish · Spain"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "¡Hola!")
        XCTAssertTrue(app.staticTexts["A little everyday Spanish"].exists)
        app.tabBars.buttons["Themes"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Un café")).firstMatch.exists)
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Little by little · Spanish")).firstMatch.exists)
        app.tabBars.buttons["Talk"].tap()
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        app.buttons["Norwegian · Bokmål"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Hei!")
    }

    func testMeaningLabelWorksAfterEndingAndManualResetKeepsHistory() {
        let app = launch(ended: true)
        XCTAssertTrue(app.buttons["new-conversation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-conversation"].isHittable)
        XCTAssertTrue(app.buttons["start-conversation"].isHittable)
        XCTAssertTrue(app.buttons["Conversation transcript"].isHittable)
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "I like coffee.")
        XCTAssertFalse(app.buttons["Hide meaning subtitles"].exists)
        app.buttons["Settings"].tap()
        app.switches["Meaning subtitles"].coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["meaning-caption"])
        waitForExpectations(timeout: 5)
        app.buttons["Settings"].tap()
        app.switches["Meaning subtitles"].coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "I like coffee.")
        app.buttons["new-conversation"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Hei!")
        XCTAssertFalse(app.staticTexts["A coffee?"].exists)
        app.tabBars.buttons["Words"].tap()
        app.buttons["Past conversations"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A coffee?")).firstMatch.exists)
    }

    func testEndedConversationStaysUntilManualNewConversation() {
        let app = launch(ended: true)
        XCTAssertTrue(app.buttons["new-conversation"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Jeg liker kaffe.")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Jeg liker kaffe.")
        XCTAssertTrue(app.buttons["new-conversation"].exists)
        app.buttons["new-conversation"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Hei!")
    }

    func testThemeSearchFiltersLocally() {
        let app = launch()
        app.tabBars.buttons["Themes"].tap()
        let coffee = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A coffee?")).firstMatch
        XCTAssertTrue(coffee.waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        for _ in 0..<5 where !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.isHittable)
        search.tap(); search.typeText("coffee")
        XCTAssertTrue(coffee.waitForExistence(timeout: 5))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "zznomatch")
        XCTAssertTrue(coffee.waitForNonExistence(timeout: 5))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9) + "coffee")
        XCTAssertTrue(coffee.waitForExistence(timeout: 5))
        keepScreenshot("Local theme search survives system search slimming", app: app)
    }

    // Opt-in, multi-boot checks. Never include these in the ordinary preview suite.
    // Run Set, then Check in fresh slim and stock lifecycles, then Restore.
    private func launchLifecycleInstallation() throws -> XCUIApplication {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("Mural Lifecycle") == true else {
            throw XCTSkip("Requires an explicitly owned Mural Lifecycle synthetic simulator")
        }
        let app = XCUIApplication()
        app.launch() // Deliberately no --preview and no defaults/fixture injection.
        return app
        #else
        throw XCTSkip("Simulator-only lifecycle check; never run on a physical phone")
        #endif
    }

    private func assertLifecycleSettings(_ app: XCUIApplication, learning: String, meaning: String) {
        app.buttons["Settings"].tap()
        for (id, expected) in [("learning-language-picker", learning), ("settings-meaning-language", meaning)] {
            let picker = app.buttons[id]
            for _ in 0..<8 where !picker.isHittable { app.swipeUp() }
            XCTAssertTrue(picker.isHittable)
            XCTAssertEqual(picker.value as? String, expected, picker.debugDescription)
        }
        keepScreenshot("Disk-backed settings: \(learning), \(meaning)", app: app)
        app.buttons["Done"].tap()
    }

    func testSimulatorLifecycleSetRetainedSettings() throws {
        let app = try launchLifecycleInstallation()
        if app.buttons["onboarding-language-en"].waitForExistence(timeout: 5) {
            app.buttons["onboarding-language-en"].tap()
            app.buttons["onboarding-continue"].tap()
            app.buttons["onboarding-meaning-picker"].tap()
            app.buttons["Vietnamese"].tap()
            app.buttons["onboarding-continue"].tap()
        }
        // Establish a repeatable safe baseline through UI, never by editing a container.
        setLearningLanguage("English · International", app: app)
        setMeaningLanguage("Vietnamese", app: app)
        assertLifecycleSettings(app, learning: "English · International", meaning: "Vietnamese")
        setLearningLanguage("French · France", app: app)
        setMeaningLanguage("German", app: app)
        assertLifecycleSettings(app, learning: "French · France", meaning: "German")
        app.terminate(); app.launch()
        assertLifecycleSettings(app, learning: "French · France", meaning: "German")
    }

    func testSimulatorLifecycleCheckRetainedSettings() throws {
        let app = try launchLifecycleInstallation()
        XCTAssertFalse(app.buttons["onboarding-language-en"].exists)
        // Assert before selecting any value: this must come from the on-disk archive.
        assertLifecycleSettings(app, learning: "French · France", meaning: "German")
    }

    func testSimulatorLifecycleRestoreSettings() throws {
        let app = try launchLifecycleInstallation()
        assertLifecycleSettings(app, learning: "French · France", meaning: "German")
        setLearningLanguage("English · International", app: app)
        setMeaningLanguage("Vietnamese", app: app)
        assertLifecycleSettings(app, learning: "English · International", meaning: "Vietnamese")
    }

    func testOpenTranscriptRemainsReadableUntilManualNewConversation() {
        let app = launch(ended: true)
        XCTAssertTrue(app.buttons["new-conversation"].waitForExistence(timeout: 5))
        app.buttons["Conversation transcript"].tap()
        XCTAssertTrue(app.staticTexts["I like coffee."].exists)
        XCTAssertTrue(app.staticTexts["Jeg drakk kaffe."].exists)
        XCTAssertTrue(app.staticTexts["Jeg liker kaffe."].exists)
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Jeg liker kaffe.")
        XCTAssertTrue(app.buttons["new-conversation"].exists)
    }
}

// Deliberate physical-only opt-in. Ordinary suites skip before creating an app.
final class MuralPhysicalDeviceTests: XCTestCase {
    private var ownedApp: XCUIApplication?
    private var startedConversation = false
    private var originalMeaning: String?
    private var originalMeaningVisible: Bool?
    private var cleaningUp = false
    private var resourceTurnDeadline: TimeInterval?
    private var resourceStage: Bool {
        ["resource", "resource-check"].contains(ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"] ?? "")
    }

    private func checkResourceAbort() throws {
        guard resourceStage || ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"] == "provision" ||
            ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"]?.hasPrefix("breeze-") == true, !cleaningUp else { return }
        let run = ProcessInfo.processInfo.environment["MURAL_PLAYBACK_RUN"] ?? ""
        let abort = FileManager.default.temporaryDirectory.appendingPathComponent("mural-resource-abort-\(run).txt")
        if FileManager.default.fileExists(atPath: abort.path) ||
            resourceTurnDeadline.map({ ProcessInfo.processInfo.systemUptime >= $0 }) == true {
            XCTFail("Resource qualification aborted or turn budget exhausted; stop through native teardown")
            throw NSError(domain: "MuralPhysicalGate", code: 5)
        }
    }

    private func markTiming(_ phase: String) {
        print("MURAL_DEVICE_TIMING \(phase) \(ProcessInfo.processInfo.systemUptime)")
    }

    private func awaitPlaybackCompletion(_ index: Int, timeout: TimeInterval = 12, trailing: Bool = true) throws {
        let run = try XCTUnwrap(ProcessInfo.processInfo.environment["MURAL_PLAYBACK_RUN"])
        _ = try XCTUnwrap(UUID(uuidString: run))
        let token = UUID().uuidString
        let receipt = FileManager.default.temporaryDirectory
            .appendingPathComponent("mural-playback-\(run)-\(index).txt")
        defer {
            if FileManager.default.fileExists(atPath: receipt.path) {
                XCTAssertNoThrow(try FileManager.default.removeItem(at: receipt))
            }
        }
        if index == 0 {
            // Model-free transport qualification also proves stale content cannot
            // satisfy this fresh random token. Host overwrites only this test file.
            try "stale-token".write(to: receipt, atomically: true, encoding: .utf8)
        }
        print("MURAL_DEVICE_PLAYBACK_WAIT \(run) \(index) \(token)")
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            try checkResourceAbort()
            if (try? String(contentsOf: receipt, encoding: .utf8)) == token {
                print("MURAL_DEVICE_PLAYBACK_ACK_\(index) \(run) \(token)")
                if index > 0 && trailing { Thread.sleep(forTimeInterval: 0.75) }
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("Playback acknowledgment missing, stale or wrong-turn; refusing Send")
        throw NSError(domain: "MuralPhysicalGate", code: 3)
    }

    private func descendants(_ snapshot: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
        [snapshot] + snapshot.children.flatMap { descendants($0) }
    }

    private func waitForPreparedConversation(_ app: XCUIApplication) throws {
        // Real UI regression: completed checkmarks must never revert during greeting
        // synthesis. Observe the transition, not just the settled Record button.
        var completed = Set<String>(), regressed = Set<String>()
        var ready = false
        let deadline = ProcessInfo.processInfo.systemUptime + 90
        while ProcessInfo.processInfo.systemUptime < deadline {
            try checkResourceAbort()
            let elements = descendants(try app.snapshot())
            for step in elements where step.identifier.hasPrefix("speech-setup-step-") {
                if step.value as? String == "Complete" { completed.insert(step.identifier) }
                else if completed.contains(step.identifier), regressed.insert(step.identifier).inserted {
                    print("MURAL_DEVICE_CHECKLIST_REGRESSION \(step.identifier) \(step.value ?? "missing")")
                    let image = XCTAttachment(screenshot: app.screenshot())
                    image.name = "Completed setup step regressed"; image.lifetime = .keepAlways; add(image)
                }
            }
            if elements.contains(where: { $0.identifier == "local-conversation-record-send" && $0.label == "Record" && $0.isEnabled }) {
                ready = true; break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(ready, "Preparation did not reach the real Record-ready state")
        XCTAssertTrue(completed.contains("speech-setup-step-checking"), "Must observe actual checklist progress")
        XCTAssertTrue(completed.contains("speech-setup-step-voice"), "Must observe completed voice preparation")
        XCTAssertTrue(regressed.isEmpty, "Completed setup steps became unchecked: \(regressed.sorted())")
        print("MURAL_DEVICE_CHECKLIST_PASS")
    }

    private func meaningSetting(_ app: XCUIApplication, select: String? = nil,
                                preservingOriginal: Bool = false) throws -> String {
        let settings = app.buttons["Settings"]
        for _ in 0..<8 {
            if settings.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(settings.isHittable); settings.tap()
        let row = app.buttons["settings-meaning-language"]
        try reveal(row, app: app)
        let value = try XCTUnwrap(row.value as? String)
        if preservingOriginal {
            print("MURAL_DEVICE_ORIGINAL_MEANING=\(value)")
            originalMeaning = value // Before any mutation; verify restoration even if already selected.
        }
        if let select, select != value {
            XCTAssertTrue(row.isEnabled); row.tap()
            let choice = app.buttons[select]
            try reveal(choice, app: app); choice.tap()
            XCTAssertEqual(row.value as? String, select)
        }
        app.buttons["Done"].tap()
        return value
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical device only")
        #else
        guard ["baseline", "acoustic", "multi", "cancel", "restore-settings", "pair-check", "resource-check", "resource", "provision", "breeze-check", "breeze-acoustic", "breeze-multi", "breeze-traditional", "breeze-history", "breeze-support", "breeze-finish", "breeze-profile-check", "breeze-profile"].contains(ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"] ?? "") else {
            throw XCTSkip("Use the explicit agent-verify-device entrypoint")
        }
        #endif
    }

    private func wait(_ predicate: String, _ element: XCUIElement, seconds: TimeInterval) throws {
        if (resourceStage || ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"] == "provision" ||
            ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"]?.hasPrefix("breeze-") == true) && !cleaningUp {
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            let condition = NSPredicate(format: predicate)
            while ProcessInfo.processInfo.systemUptime < deadline {
                try checkResourceAbort()
                if condition.evaluate(with: element) { return }
                Thread.sleep(forTimeInterval: 0.25)
            }
            XCTFail("Resource UI phase timed out: \(predicate)")
            throw NSError(domain: "MuralPhysicalGate", code: 6)
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: predicate), object: element)], timeout: seconds)
        guard result == .completed else {
            XCTFail("Physical gate timed out: \(predicate), \(element.identifier)")
            throw NSError(domain: "MuralPhysicalGate", code: 1)
        }
    }

    private func scrollOwnedContent(_ app: XCUIApplication, towardTop: Bool) {
        // Keep touches in content, away from Notification Center and the Home edge.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.35 : 0.65))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.65 : 0.35))
        from.press(forDuration: 0.1, thenDragTo: to)
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) throws {
        for _ in 0..<12 {
            guard app.state == .runningForeground else {
                throw NSError(domain: "MuralPhysicalGate", code: 7, userInfo: [NSLocalizedDescriptionKey: "Mural left the foreground; refuse gestures on another app"])
            }
            if element.isHittable { return }
            scrollOwnedContent(app, towardTop: element.exists && element.frame.midY < app.frame.midY)
        }
        guard element.isHittable else {
            XCTFail("Missing physical control: \(element.identifier)")
            throw NSError(domain: "MuralPhysicalGate", code: 2)
        }
    }

    private func closeTranscriptSheets(_ app: XCUIApplication) throws {
        for title in ["Our conversation", "Past conversations"] {
            let bar = app.navigationBars[title]
            if bar.exists {
                bar.buttons["Done"].tap()
                try wait("exists == false", bar, seconds: 5)
            }
        }
    }

    override func tearDownWithError() throws {
        guard let app = ownedApp else { return }
        cleaningUp = true
        markTiming("cleanup_started")
        if startedConversation && app.buttons["speech-setup-cancel"].exists {
            let cancel = ownedTalkStopButton(app)
            try reveal(cancel, app: app); cancel.tap()
        }
        if app.buttons["Close"].exists && app.buttons["Close"].isHittable { app.buttons["Close"].tap() }
        try closeTranscriptSheets(app)
        app.tabBars.buttons["Talk"].tap()
        if startedConversation {
            let end = ownedTalkStopButton(app)
            if end.exists { try reveal(end, app: app); end.tap() }
            let idle = app.buttons["new-conversation"].exists
                ? app.buttons["new-conversation"] : app.buttons["local-conversation-start"]
            try wait("exists == true AND enabled == true", idle, seconds: 60)
        }
        if let originalMeaning {
            _ = try meaningSetting(app, select: originalMeaning)
            XCTAssertEqual(try meaningSetting(app), originalMeaning)
            print("MURAL_DEVICE_SETTINGS_RESTORED")
            if ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"] == "breeze-finish" {
                print("MURAL_DEVICE_FINAL_MEANING=\(originalMeaning)")
            }
        }
        if originalMeaningVisible != nil { try meaningVisibility(app, restoring: true) }
        print("MURAL_DEVICE_TERMINATE_REQUESTED")
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        print("MURAL_DEVICE_CLEANUP_PASS")
        markTiming("cleanup_finished")
    }

    private func assertRetainedTurns(_ turns: [String], app: XCUIApplication) throws {
        // The sheet leaves Talk's latest learner/caption in the accessibility tree.
        // MURAL speaker headings belong to Transcript, not the underlying Talk view.
        let transcripts = app.scrollViews.containing(.staticText, identifier: "MURAL")
        XCTAssertEqual(transcripts.count, 1)
        let transcript = transcripts.firstMatch
        for text in turns {
            let passage = transcript.staticTexts.matching(NSPredicate(format: "label == %@", text))
            try reveal(passage.firstMatch, app: app)
        }
        // One settled native snapshot, not a remote request for every label/count.
        // Visibility still requires the real scrolling above, including after relaunch.
        let snapshot = try transcript.snapshot()
        let hierarchy = XCTAttachment(string: String(describing: snapshot.dictionaryRepresentation))
        hierarchy.name = "Synthetic transcript hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        let labels = descendants(snapshot).filter { $0.elementType == .staticText }.map(\.label)
        for text in turns {
            XCTAssertEqual(labels.filter { $0 == text }.count, turns.filter { $0 == text }.count)
        }
        XCTAssertEqual(labels.filter { turns.contains($0) }, turns, "Exact synthetic turns must persist once and in order")
    }

    private func resourceAcknowledgmentBudget() throws -> TimeInterval {
        let text = try XCTUnwrap(ProcessInfo.processInfo.environment["MURAL_RESOURCE_ACK_SECONDS"])
        let value = try XCTUnwrap(TimeInterval(text))
        guard value.isFinite, (12...23).contains(value) else {
            throw NSError(domain: "MuralPhysicalGate", code: 7)
        }
        return value
    }

    private func runResourceConversation(_ app: XCUIApplication, start: XCUIElement) throws {
        startedConversation = true
        markTiming("preparation_requested"); start.tap()
        try waitForPreparedConversation(app)
        markTiming("ready")
        resourceTurnDeadline = ProcessInfo.processInfo.systemUptime + 90
        let record = app.buttons["local-conversation-record-send"]
        try reveal(record, app: app); record.tap()
        try wait("label == 'Send'", record, seconds: 90)
        print("MURAL_DEVICE_RECORD_UI_READY_1")
        try awaitPlaybackCompletion(1, timeout: resourceAcknowledgmentBudget())
        XCTAssertEqual(record.label, "Send"); record.tap()
        try wait("label CONTAINS 'Ready'", app.staticTexts["conversation-status"], seconds: 90)
        // The host additionally waits for tutor, actual speech completion and all
        // supporting work, not just this displayed status.
        try awaitPlaybackCompletion(2, timeout: 90, trailing: false)
        resourceTurnDeadline = nil
        markTiming("loaded_idle_started")
        let idleEnd = ProcessInfo.processInfo.systemUptime + 360
        while ProcessInfo.processInfo.systemUptime < idleEnd {
            try checkResourceAbort()
            Thread.sleep(forTimeInterval: 0.25)
        }
        let reply = app.staticTexts["target-caption"].label
        XCTAssertFalse(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let details = app.buttons["On-device details & diagnostics"]
        try reveal(details, app: app); details.tap()
        let raw = app.buttons["Raw recognition · not translated"]
        if !app.staticTexts["local-raw-asr"].exists { try reveal(raw, app: app); raw.tap() }
        let learner = app.staticTexts["local-raw-asr"].label
        XCTAssertFalse(learner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let rawEvidence = XCTAttachment(string: learner); rawEvidence.name = "FireRed raw recognition"
        rawEvidence.lifetime = .keepAlways; add(rawEvidence)
        print("MURAL_DEVICE_RESOURCE_RAW_BASE64 \(Data(learner.utf8).base64EncodedString())")
        try reveal(details, app: app); details.tap()
        let end = app.buttons["local-conversation-end"]
        try reveal(end, app: app); markTiming("end_requested"); end.tap()
        try awaitPlaybackCompletion(3, timeout: 60, trailing: false)
        try awaitPlaybackCompletion(4, timeout: 40, trailing: false)
        markTiming("release_observed")
        let transcript = app.buttons["local-conversation-transcript"]
        try reveal(transcript, app: app); transcript.tap()
        try assertRetainedTurns([learner, reply], app: app)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "FireRed native resource transcript"; image.lifetime = .keepAlways; add(image)
        try closeTranscriptSheets(app)
        print("MURAL_DEVICE_RESOURCE_UI_PASS")
    }

    // Acquisition acceptance before implementation: normal consent, nonempty partial
    // cancellation/drain, explicit retry/resume, verified activation, never Ready.
    private func runProvisioning(_ app: XCUIApplication, start: XCUIElement) throws {
        startedConversation = true
        start.tap()
        if ProcessInfo.processInfo.environment["MURAL_PROVISION_RESUME_JOB"]?.isEmpty == false {
            try awaitPlaybackCompletion(3, timeout: 120, trailing: false)
            try wait("exists == true AND enabled == true", start, seconds: 60)
            XCTAssertFalse(app.staticTexts["speech-setup-error"].exists)
            XCTAssertFalse(app.buttons["local-conversation-record-send"].exists)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "Retained graphs verified and missing tokens recovered"; image.lifetime = .keepAlways; add(image)
            print("MURAL_DEVICE_PROVISION_RECOVERY_UI_PASS")
            return
        }
        let confirm = app.buttons["speech-download-confirm"]
        try wait("exists == true", confirm, seconds: 15)
        try reveal(confirm, app: app); confirm.tap()
        try awaitPlaybackCompletion(1, timeout: 120, trailing: false) // First persisted network chunk, no playback.
        let cancel = app.buttons["speech-setup-cancel"]
        try reveal(cancel, app: app); cancel.tap()
        try wait("exists == true AND enabled == true", start, seconds: 60)
        XCTAssertFalse(app.buttons["local-conversation-record-send"].exists)
        print("MURAL_DEVICE_PROVISION_CANCELLED")
        // This attempt owns the cancelled setup. Never resume an unrelated initial job.
        try awaitPlaybackCompletion(2, timeout: 30, trailing: false) // Host saves drained partial inventory.
        try reveal(start, app: app); start.tap()
        if confirm.waitForExistence(timeout: 10) { try reveal(confirm, app: app); confirm.tap() }
        try awaitPlaybackCompletion(3, timeout: 900, trailing: false) // Verified activation and native admission stop.
        try wait("exists == true AND enabled == true", start, seconds: 60)
        XCTAssertFalse(app.buttons["local-conversation-record-send"].exists)
        XCTAssertFalse(app.buttons["local-conversation-transcript"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Managed FireRed verified; native preparation deferred"; image.lifetime = .keepAlways; add(image)
        print("MURAL_DEVICE_PROVISION_UI_PASS")
    }

    private func meaningVisibility(_ app: XCUIApplication, restoring: Bool = false) throws {
        let settings = app.buttons["Settings"]
        try reveal(settings, app: app); settings.tap()
        let toggle = app.switches["Meaning subtitles"]
        try reveal(toggle, app: app)
        let value = try XCTUnwrap(toggle.value as? String) == "1"
        if originalMeaningVisible == nil { originalMeaningVisible = value }
        let desired = restoring ? try XCTUnwrap(originalMeaningVisible) : true
        if value != desired { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, desired ? "1" : "0")
        app.buttons["Done"].tap()
    }

    private func keepBreezeScreen(_ name: String, app: XCUIApplication) throws {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }

    private func verifyBreezeHistoryEdit(_ app: XCUIApplication, sessionID: String,
                                         expectedTurns: [String], rawTurns: [String]) throws {
        var turns = expectedTurns
        print("MURAL_DEVICE_MODEL_PHASE_COMPLETE")
        _ = try meaningSetting(app, select: "Traditional Chinese") // Future Settings must not rewrite this saved Simplified session.
        app.terminate(); app.launch(); startedConversation = false
        app.tabBars.buttons["Words"].tap()
        let history = app.buttons["Past conversations"]
        try reveal(history, app: app); history.tap()
        let savedSession = app.buttons["history-session-\(sessionID)"]
        XCTAssertTrue(savedSession.waitForExistence(timeout: 5)); savedSession.tap()
        try assertRetainedTurns(turns, app: app)
        let savedTranscript = app.scrollViews["transcript-session-\(sessionID)"]
        let originals = savedTranscript.buttons.matching(identifier: "transcript-script-original")
        XCTAssertEqual(originals.count, rawTurns.count)
        for index in 0..<originals.count {
            let original = originals.element(boundBy: index)
            try reveal(original, app: app); original.tap()
            XCTAssertTrue(savedTranscript.staticTexts.matching(NSPredicate(format: "label == %@", rawTurns[index])).firstMatch.exists)
            original.tap()
        }
        try keepBreezeScreen("Saved Simplified display retained after preference change and relaunch", app: app)
        let firstEdit = savedTranscript.buttons["Edit"].firstMatch
        try reveal(firstEdit, app: app); firstEdit.tap()
        let input = app.descendants(matching: .any).matching(identifier: "transcript-edit-text").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, turns[0], "Editor starts from displayed wording")
        replaceTranscriptText("Breeze verification edit API Kevin 17.", input: input, app: app)
        app.navigationBars["What you said"].buttons["Save"].tap()
        try wait("exists == false", app.navigationBars["What you said"], seconds: 5)
        turns[0] = "Breeze verification edit API Kevin 17."
        try assertRetainedTurns(turns, app: app)
        let raw = savedTranscript.buttons["transcript-script-original"].firstMatch
        try reveal(raw, app: app)
        XCTAssertTrue(raw.label.contains("edited wording"), "Stale Simplified projection must be gone")
        raw.tap()
        XCTAssertTrue(savedTranscript.staticTexts.matching(NSPredicate(format: "label == %@", rawTurns[0])).firstMatch.exists)
        raw.tap()
        try closeTranscriptSheets(app)
        app.terminate(); app.launch()
        app.tabBars.buttons["Words"].tap(); try reveal(history, app: app); history.tap()
        XCTAssertTrue(savedSession.waitForExistence(timeout: 5)); savedSession.tap()
        try assertRetainedTurns(turns, app: app)
        try reveal(raw, app: app)
        XCTAssertTrue(raw.label.contains("edited wording"))
        raw.tap()
        XCTAssertTrue(savedTranscript.staticTexts.matching(NSPredicate(format: "label == %@", rawTurns[0])).firstMatch.exists)
        try keepBreezeScreen("Explicit edit persisted with original recognition retained", app: app)
        try closeTranscriptSheets(app)
        app.tabBars.buttons["Talk"].tap()
        print("MURAL_DEVICE_BREEZE_EDIT_PERSISTENCE_PASS")
    }

    @MainActor func testNativeBreezeDisplay() async throws {
        let stage = try XCTUnwrap(ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"])
        XCTAssertTrue(["breeze-check", "breeze-acoustic", "breeze-multi", "breeze-traditional", "breeze-history", "breeze-support", "breeze-finish", "breeze-profile-check", "breeze-profile"].contains(stage))
        XCTAssertEqual(ProcessInfo.processInfo.environment["MURAL_PHYSICAL_PAIR"], "breeze-zh-CN-en")
        let app = XCUIApplication(bundleIdentifier: "com.kevintruong.mural.dev")
        XCTAssertNotEqual(app.state, .notRunning)
        app.activate(); ownedApp = app; markTiming("activated")
        XCTAssertTrue(app.staticTexts["conversation-language-pair"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["local-conversation-end"].exists, "Refuse active personal Talk")
        XCTAssertFalse(app.buttons["local-conversation-transcript"].exists, "Refuse retained personal Talk")
        XCTAssertTrue(app.staticTexts["conversation-language-pair"].label.hasPrefix("English · "))
        let traditional = stage == "breeze-traditional"
        let meaning = traditional ? "Traditional Chinese" : "Simplified Chinese"
        _ = try meaningSetting(app, select: meaning, preservingOriginal: true)
        if stage == "breeze-check", let restore = ProcessInfo.processInfo.environment["MURAL_RESTORE_MEANING"], !restore.isEmpty {
            originalMeaning = restore // Exact logged preference from this verification's failed teardown.
        }
        if stage == "breeze-finish" {
            originalMeaning = "Simplified Chinese" // Explicit final preference from the feature handoff, not test restoration.
        }
        let start = app.buttons["local-conversation-start"]
        XCTAssertEqual(start.label, "Prepare & start", "Refuse pending or paused personal setup")
        let details = app.buttons["On-device details & diagnostics"]
        try reveal(details, app: app); details.tap()
        XCTAssertTrue(app.staticTexts["local-recognizer"].label.contains("breeze-asr25-pal8-v1"))
        XCTAssertTrue(app.staticTexts["local-asr-backend"].label.contains(traditional ? "WhisperKit / Core ML" : "Breeze PAL8 · Simplified display"))
        details.tap()
        if stage == "breeze-history" {
            let encoded = try XCTUnwrap(ProcessInfo.processInfo.environment["MURAL_BREEZE_HISTORY_BASE64"])
            let data = try XCTUnwrap(Data(base64Encoded: encoded))
            let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let sessionID = try XCTUnwrap(fixture["session"] as? String)
            _ = try XCTUnwrap(UUID(uuidString: sessionID))
            let savedTurns = try XCTUnwrap(fixture["turns"] as? [[String: String]])
            let raw = try savedTurns.map { try XCTUnwrap($0["raw"]) }
            let turns = try savedTurns.flatMap { [try XCTUnwrap($0["display"]), try XCTUnwrap($0["reply"])] }
            try awaitPlaybackCompletion(0, trailing: false)
            try verifyBreezeHistoryEdit(app, sessionID: sessionID, expectedTurns: turns, rawTurns: raw)
            print("MURAL_DEVICE_BREEZE_UI_PASS")
            return
        }
        if ["breeze-check", "breeze-finish", "breeze-profile-check"].contains(stage) {
            if stage == "breeze-finish" {
                let source = "怎麼 怎么 幺妹 軟體 滑鼠 API 17"
                let projection = try await ChineseScriptRenderer.shared.presentation(for: source, pair: .mainlandMandarinEnglish)
                XCTAssertEqual(projection?.text, "怎么 怎么 幺妹 软体 滑鼠 API 17")
                XCTAssertEqual(projection?.sourceText, source)
                print("MURAL_DEVICE_BREEZE_NATIVE_DICTIONARY_PASS")
            }
            for choice in ["Traditional Chinese", "Vietnamese", "Simplified Chinese"] {
                _ = try meaningSetting(app, select: choice)
                try reveal(details, app: app); details.tap()
                XCTAssertTrue(app.staticTexts["local-asr-backend"].label.contains(choice == "Vietnamese"
                    ? "Core AI GPU-preferred encoder + Core ML decoder (staged)" : "Breeze PAL8"))
                details.tap()
            }
            try reveal(details, app: app); details.tap()
            scrollOwnedContent(app, towardTop: false); scrollOwnedContent(app, towardTop: false)
            try reveal(start, app: app)
            XCTAssertTrue(start.isHittable, "Return to setup above expanded diagnostics without leaving Mural")
            try reveal(details, app: app); details.tap()
            try awaitPlaybackCompletion(0, trailing: false)
            try keepBreezeScreen("Breeze model-free pair and runner transport", app: app)
            print("MURAL_DEVICE_BREEZE_UI_PASS")
            return
        }
        if ["breeze-multi", "breeze-support"].contains(stage) { try meaningVisibility(app) }
        if stage == "breeze-profile" {
            // Host confirms the activated app still has the exact profiled PID.
            // No model is requested until that fresh nonce is acknowledged.
            try awaitPlaybackCompletion(0, trailing: false)
        }
        startedConversation = true
        try reveal(start, app: app); markTiming("preparation_requested"); start.tap()
        let record = app.buttons["local-conversation-record-send"]
        // Measured retained-file Breeze load was 167.76 s despite a receipt hit.
        // A VI-specific 90 s setup wait is not its contract. The existing 300 s
        // XCTest / 420 s host budgets and all fault/recording gates still apply.
        try wait("exists == true AND enabled == true AND label == 'Record'", record, seconds: 200)
        XCTAssertFalse(app.buttons["speech-download-confirm"].exists, "Never acquire ASR weights in this verification")
        markTiming("ready")
        if stage == "breeze-profile" {
            try keepBreezeScreen("Breeze preparation-only profile: ready without recording", app: app)
            let end = app.buttons["local-conversation-end"]
            try reveal(end, app: app); markTiming("end_requested"); end.tap()
            try wait("exists == true AND enabled == true", app.buttons["new-conversation"], seconds: 60)
            print("MURAL_DEVICE_BREEZE_PROFILE_PASS")
            print("MURAL_DEVICE_BREEZE_UI_PASS")
            return
        }
        let budget = try XCTUnwrap(TimeInterval(ProcessInfo.processInfo.environment["MURAL_BREEZE_ACK_SECONDS"] ?? ""))
        XCTAssertTrue((12...23).contains(budget))
        var rawTurns: [String] = [], turns: [String] = []
        for index in 1...(stage == "breeze-multi" ? 2 : 1) {
            try reveal(record, app: app); record.tap()
            try wait("label == 'Send'", record, seconds: 10)
            print("MURAL_DEVICE_RECORD_UI_READY_\(index)")
            try awaitPlaybackCompletion(index, timeout: budget)
            XCTAssertEqual(record.label, "Send"); markTiming("turn_\(index)_send_requested"); record.tap()
            try wait("exists == true AND enabled == true AND label == 'Record'", record, seconds: 90)
            markTiming("turn_\(index)_response_ready")
            try reveal(details, app: app); details.tap()
            let disclosure = app.buttons["Raw recognition · not translated"]
            if !app.staticTexts["local-raw-asr"].exists {
                guard disclosure.waitForExistence(timeout: 5) else {
                    try keepBreezeScreen("Breeze did not complete a recognized turn", app: app)
                    let notice = app.staticTexts["conversation-notice"]
                    let message = notice.exists ? notice.label : "no original recognition available"
                    XCTFail("Breeze recognition incomplete: \(message)")
                    return
                }
                try reveal(disclosure, app: app); disclosure.tap()
            }
            let raw = app.staticTexts["local-raw-asr"].label
            XCTAssertFalse(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let canonical = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let projection = try await ChineseScriptRenderer.shared.presentation(for: canonical,
                pair: traditional ? .taiwanMandarinEnglish : .mainlandMandarinEnglish)
            let display = projection?.text ?? canonical
            try reveal(details, app: app); details.tap()
            let reply = app.staticTexts["target-caption"].label
            XCTAssertFalse(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            rawTurns.append(raw); turns += [display, reply]
            let text = try JSONSerialization.data(withJSONObject: ["raw": raw, "display": display, "reply": reply])
            print("MURAL_DEVICE_BREEZE_TURN \(text.base64EncodedString())")
        }
        let hierarchy = XCTAttachment(string: String(describing: try app.snapshot().dictionaryRepresentation))
        hierarchy.name = "New Breeze conversation Talk hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        if ["breeze-multi", "breeze-support"].contains(stage) {
            let meaningCaption = app.staticTexts["meaning-caption"]
            try wait("exists == true AND label != '' AND NOT label CONTAINS 'Finding'", meaningCaption, seconds: 60)
            let meaningProjection = try await ChineseScriptRenderer.shared.presentation(for: meaningCaption.label, pair: .mainlandMandarinEnglish)
            XCTAssertEqual(meaningProjection?.text, meaningCaption.label, "Meaning must already be Simplified, not rewritten by the display layer")
            var support = ["meaning": meaningCaption.label]
            if stage == "breeze-support" {
                let caption = app.staticTexts["target-caption"]
                try reveal(caption, app: app)
                let word = caption.links.firstMatch // Actual Link role confirmed in the native hierarchy.
                try wait("exists == true", word, seconds: 5)
                try reveal(word, app: app); word.tap()
                let lookup = app.navigationBars["A little meaning"]
                try wait("exists == true", lookup, seconds: 10)
                let explanation = app.staticTexts["word-lookup-explanation"]
                try wait("exists == true AND label != ''", explanation, seconds: 45)
                XCTAssertFalse(app.staticTexts["word-lookup-error"].exists)
                let selected = app.staticTexts["word-lookup-selected"].label
                XCTAssertTrue(turns.last?.contains(selected) == true)
                let projected = try await ChineseScriptRenderer.shared.presentation(for: explanation.label, pair: .mainlandMandarinEnglish)
                XCTAssertEqual(projected?.text, explanation.label, "Lookup must already be Simplified")
                support["word"] = selected; support["lookup"] = explanation.label
                try keepBreezeScreen("Native Simplified English-word lookup", app: app)
                lookup.buttons["Done"].tap()
                markTiming("lookup_complete")
            }
            let help = app.buttons["A little help"]
            try reveal(help, app: app); try wait("enabled == true", help, seconds: 60); help.tap()
            let assistance = app.descendants(matching: .any).matching(identifier: "local-learning-assistance").firstMatch
            try wait("exists == true", assistance, seconds: 60)
            try reveal(assistance, app: app)
            let helpText = app.staticTexts["local-learning-assistance-text"]
            try wait("exists == true AND label != ''", helpText, seconds: 45)
            let helpProjection = try await ChineseScriptRenderer.shared.presentation(for: helpText.label, pair: .mainlandMandarinEnglish)
            XCTAssertEqual(helpProjection?.text, helpText.label, "On-screen Help must already be Simplified")
            support["help"] = helpText.label
            if stage == "breeze-support" {
                let data = try JSONSerialization.data(withJSONObject: support)
                print("MURAL_DEVICE_BREEZE_SUPPORT_BASE64 \(data.base64EncodedString())")
                markTiming("help_complete")
            }
            let helpEvidence = XCTAttachment(string: String(describing: try assistance.snapshot().dictionaryRepresentation))
            helpEvidence.name = "Simplified on-screen Help"; helpEvidence.lifetime = .keepAlways; add(helpEvidence)
            try keepBreezeScreen("Simplified meanings and on-screen Help", app: app)
        }
        let end = app.buttons["local-conversation-end"]
        try reveal(end, app: app); markTiming("end_requested"); end.tap()
        try wait("exists == true AND enabled == true", app.buttons["new-conversation"], seconds: 60)
        let transcriptButton = app.buttons["local-conversation-transcript"]
        try reveal(transcriptButton, app: app); transcriptButton.tap()
        try assertRetainedTurns(turns, app: app)
        let transcript = app.scrollViews.matching(NSPredicate(format: "identifier BEGINSWITH 'transcript-session-'" )).firstMatch
        XCTAssertTrue(transcript.exists)
        let sessionID = String(transcript.identifier.dropFirst("transcript-session-".count))
        _ = try XCTUnwrap(UUID(uuidString: sessionID))
        print("MURAL_DEVICE_BREEZE_SESSION \(sessionID)")
        if !traditional {
            let originals = transcript.buttons.matching(identifier: "transcript-script-original")
            XCTAssertEqual(originals.count, rawTurns.count)
            for index in 0..<originals.count {
                let original = originals.element(boundBy: index)
                try reveal(original, app: app); original.tap()
                XCTAssertTrue(transcript.staticTexts.matching(NSPredicate(format: "label == %@", rawTurns[index])).firstMatch.exists)
                original.tap()
            }
        }
        try keepBreezeScreen("Native Breeze display and original recognition", app: app)
        try closeTranscriptSheets(app)
        if stage == "breeze-multi" {
            try verifyBreezeHistoryEdit(app, sessionID: sessionID, expectedTurns: turns, rawTurns: rawTurns)
        }
        print("MURAL_DEVICE_BREEZE_UI_PASS")
    }

    func testNativeBaseline() throws {
        let stage = ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"] ?? ""
        let pair = ProcessInfo.processInfo.environment["MURAL_PHYSICAL_PAIR"] ?? "vi-en"
        guard (pair == "vi-en" && !resourceStage) || (pair == "zh-CN-en" && (stage == "pair-check" || stage == "provision" || resourceStage)) else {
            XCTFail("FireRed runtime is blocked pending resource review; unknown pairs are refused")
            throw NSError(domain: "MuralPhysicalGate", code: 4)
        }
        if resourceStage {
            XCTAssertEqual(ProcessInfo.processInfo.environment["MURAL_RESOURCE_CAPTURE_READY"], "YES", "Host must prove useful capture before models")
        }
        let meaning = pair == "zh-CN-en" ? "Simplified Chinese" : "Vietnamese"
        let app = XCUIApplication(bundleIdentifier: "com.kevintruong.mural.dev")
        // Host launches the real signed app with its scoped console attached first.
        // No previews, defaults, transcript injection or model substitutes.
        XCTAssertNotEqual(app.state, .notRunning, "Host must own the console-attached app")
        app.activate()
        ownedApp = app
        markTiming("activated")
        if ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"] == "restore-settings" {
            originalMeaning = try XCTUnwrap(ProcessInfo.processInfo.environment["MURAL_RESTORE_MEANING"],
                                               "Recovery requires the recorded original preference")
            try awaitPlaybackCompletion(0) // Transport only: no speech or models.
            _ = try meaningSetting(app, select: "Vietnamese") // Single visit, then restore the recorded original in teardown.
            // Reproduce the cleanup navigation gap without starting models: End and
            // Settings can be above expanded, scrolled diagnostics, not below them.
            let details = app.buttons["On-device details & diagnostics"]
            try reveal(details, app: app); details.tap()
            app.swipeUp(); app.swipeUp()
            try reveal(details, app: app); details.tap()
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "Cleanup returns from expanded diagnostics"; image.lifetime = .keepAlways; add(image)
            app.tabBars.buttons["Words"].tap()
            let history = app.buttons["Past conversations"]
            try reveal(history, app: app); history.tap()
            let newest = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "On-device conversation")).firstMatch
            XCTAssertTrue(newest.waitForExistence(timeout: 5)); newest.tap()
            XCTAssertTrue(app.navigationBars["Our conversation"].waitForExistence(timeout: 5))
            // Both sheets expose Done. Exercise precisely scoped dismissal during teardown.
            print("MURAL_DEVICE_RESTORE_ONLY")
            return // tearDown restores through UI; no Prepare/model/microphone action.
        }
        XCTAssertTrue(app.staticTexts["conversation-language-pair"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["local-conversation-end"].exists, "Refuse an active personal conversation")
        XCTAssertFalse(app.buttons["local-conversation-transcript"].exists, "Do not clear existing Talk")
        XCTAssertTrue(app.staticTexts["conversation-language-pair"].label.hasPrefix("English · "))
        _ = try meaningSetting(app, select: meaning, preservingOriginal: true)
        if stage == "pair-check", let restore = ProcessInfo.processInfo.environment["MURAL_RESTORE_MEANING"],
           !restore.isEmpty {
            originalMeaning = restore // Explicit recorded preference after a failed run, never guessed.
        }
        XCTAssertEqual(app.staticTexts["conversation-language-pair"].label, "English · \(meaning)")
        let start = app.buttons["local-conversation-start"]
        let recovery = stage == "provision" && ProcessInfo.processInfo.environment["MURAL_PROVISION_RESUME_JOB"]?.isEmpty == false
        XCTAssertEqual(start.label, recovery ? "Resume setup" : "Prepare & start", "Refuse unrelated paused/pending personal work")
        try reveal(start, app: app)
        XCTAssertTrue(start.isEnabled)
        let details = app.buttons["On-device details & diagnostics"]
        try reveal(details, app: app); details.tap()
        XCTAssertTrue(app.staticTexts["local-asr-backend"].label.contains(pair == "zh-CN-en"
            ? "FireRedASR2-AED" : "Core AI GPU-preferred encoder + Core ML decoder (staged)"))
        if stage == "pair-check" || stage == "resource-check" {
            // Never Prepare or inspect personal history. Exercise the actual pair,
            // scrolled diagnostics and nonce transport before admitting native work.
            originalMeaning = originalMeaning ?? meaning
            app.swipeUp(); app.swipeUp()
            try reveal(details, app: app); details.tap()
            try reveal(start, app: app)
            XCTAssertEqual(start.label, "Prepare & start")
            let acknowledgment = resourceStage ? try resourceAcknowledgmentBudget() : 12
            try awaitPlaybackCompletion(0, timeout: acknowledgment, trailing: false)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "Model-free selected pair \(pair)"; image.lifetime = .keepAlways; add(image)
            print("MURAL_DEVICE_PAIR_CHECK_PASS \(pair)")
            return // Teardown restores and independently reads the original preference.
        }
        details.tap()
        try reveal(start, app: app)
        if stage == "provision" {
            try runProvisioning(app, start: start)
            return
        }
        if stage == "resource" {
            try runResourceConversation(app, start: start)
            return
        }
        startedConversation = true
        markTiming("preparation_requested")
        start.tap()
        let record = app.buttons["local-conversation-record-send"]
        try waitForPreparedConversation(app)
        XCTAssertTrue(app.staticTexts["conversation-status"].label.contains("Ready"))
        markTiming("ready")
        let multi = ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"] == "multi"
        let cancelling = ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"] == "cancel"
        let phrases = (multi || cancelling) ? ["I bought three apples on Tuesday.", "My appointment is tomorrow morning."] : ["I bought three apples on Tuesday."]
        var retainedTurns: [String] = []
        for (index, phrase) in phrases.enumerated() {
        var learner = phrase
        if multi || cancelling || ProcessInfo.processInfo.environment["MURAL_PHYSICAL_E2E"] == "acoustic" {
            try reveal(record, app: app); record.tap()
            // Permission remains a human gate. No automatic alert approval.
            try wait("label == 'Send'", record, seconds: 90)
            markTiming("capture_\(index + 1)_ready")
            print("MURAL_DEVICE_RECORD_UI_READY_\(index + 1)")
            // Only a fresh nonce delivered after successful host playback can
            // release Send. Missing/wrong/late acknowledgments fail closed.
            try awaitPlaybackCompletion(index + 1)
            XCTAssertEqual(record.label, "Send")
            markTiming("capture_\(index + 1)_finished")
            if cancelling && index == 0 {
                let end = app.buttons["local-conversation-end"]
                try reveal(end, app: app); end.tap()
                try wait("exists == true AND enabled == true", start, seconds: 60)
                XCTAssertFalse(app.buttons["local-conversation-transcript"].exists)
                XCTAssertFalse(app.buttons["new-conversation"].exists)
                print("MURAL_DEVICE_CANCELLED_RECORDING")
                try reveal(start, app: app); start.tap()
                try wait("exists == true AND enabled == true AND label == 'Record'", record, seconds: 90)
                continue
            }
            markTiming("turn_\(index + 1)_send_requested")
            record.tap()
            try wait("exists == true AND enabled == true AND label == 'Record'", record, seconds: 90)
            markTiming("turn_\(index + 1)_response_ready")
            let details = app.buttons["On-device details & diagnostics"]
            try reveal(details, app: app); details.tap()
            let raw = app.buttons["Raw recognition · not translated"]
            if !app.staticTexts["local-raw-asr"].exists { try reveal(raw, app: app); raw.tap() }
            learner = app.staticTexts["local-raw-asr"].label
            let normalized = learner.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0) }
            XCTAssertEqual(String(String.UnicodeScalarView(normalized)).split(whereSeparator: { $0.isWhitespace }).map { $0 == "3" ? "three" : String($0) }.joined(separator: " "),
                           phrase.lowercased().replacingOccurrences(of: ".", with: ""))
            try reveal(details, app: app); details.tap()
        } else {
            let typing = app.buttons["Type instead"]
            try reveal(typing, app: app); typing.tap()
            let input = app.textFields["Reply in English or another language"]
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            input.tap(); input.typeText(learner)
            app.buttons["Send reply"].tap()
            try wait("exists == false", app.buttons["Send reply"], seconds: 60)
            try wait("exists == true AND enabled == true AND label == 'Record'", record, seconds: 60)
        }
        let reply = app.staticTexts["target-caption"].label
        XCTAssertFalse(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNotEqual(reply, "Hi! What did you do today?")
        retainedTurns += [learner, reply]
        markTiming("turn_\(index + 1)_verified")
        }
        markTiming("end_requested")
        let end = app.buttons["local-conversation-end"]
        try reveal(end, app: app); end.tap()
        try wait("exists == true AND enabled == true", app.buttons["new-conversation"], seconds: 60)
        let transcript = app.buttons["local-conversation-transcript"]
        try reveal(transcript, app: app); transcript.tap()
        try assertRetainedTurns(retainedTurns, app: app)
        markTiming("transcript_verified")
        if cancelling {
            let transcript = app.scrollViews.containing(.staticText, identifier: "MURAL").firstMatch
            XCTAssertEqual(transcript.staticTexts.matching(identifier: "YOU").count, 1)
            print("MURAL_DEVICE_CANCELLATION_PASS")
        }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Synthetic native transcript"; image.lifetime = .keepAlways; add(image)
        let text = XCTAttachment(string: retainedTurns.joined(separator: "\n"))
        text.name = "Synthetic turn text in order"; text.lifetime = .keepAlways; add(text)
        try closeTranscriptSheets(app)
        if multi {
            print("MURAL_DEVICE_MODEL_PHASE_COMPLETE")
            app.terminate(); app.launch() // Normal disk-backed launch, no setup or fixtures.
            app.tabBars.buttons["Words"].tap()
            let history = app.buttons["Past conversations"]
            try reveal(history, app: app); history.tap()
            // History is newest-first in production; open only this just-created synthetic record.
            let newest = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "On-device conversation")).firstMatch
            XCTAssertTrue(newest.waitForExistence(timeout: 5)); newest.tap()
            try assertRetainedTurns(retainedTurns, app: app)
            let saved = XCTAttachment(screenshot: app.screenshot())
            saved.name = "Synthetic transcript after normal relaunch"; saved.lifetime = .keepAlways; add(saved)
            markTiming("persistence_verified")
            print("MURAL_DEVICE_PERSISTENCE_PASS")
            try closeTranscriptSheets(app)
            app.tabBars.buttons["Talk"].tap()
            startedConversation = false // Relaunched only after explicit End and confirmed drain.
        }
        print("MURAL_DEVICE_BASELINE_UI_PASS")
    }
}
