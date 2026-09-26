import XCTest

final class MuralUITests: XCTestCase {
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

        setMeaningLanguage("French", app: app)
        XCTAssertEqual(languagePair.label, "English · French")
        let start = app.buttons["local-conversation-start"]
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        start.tap()
        let alert = app.alerts["A little interruption"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "supports English learning with Vietnamese or Traditional Chinese meanings")).firstMatch.exists)
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
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "supports English learning with Vietnamese or Traditional Chinese meanings")).firstMatch.exists)
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
        app.buttons["local-conversation-end"].tap()
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
        app.buttons["speech-setup-cancel"].tap()
        XCTAssertEqual(stage.label, "Setup cancelled")
        let start = app.buttons["local-conversation-start"]
        XCTAssertTrue(start.exists)
        XCTAssertFalse(start.isEnabled)
        XCTAssertFalse(app.buttons["local-speech-pair"].exists)
        XCTAssertFalse(app.buttons["local-tutor-probe"].isEnabled)
        setMeaningLanguage("Vietnamese", app: app)
        XCTAssertEqual(app.staticTexts["conversation-language-pair"].label, "English · Vietnamese")
        XCTAssertTrue(localRecognizer(app).label.contains("phowhisper"))
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
    func testMemoryPressurePausesSpeechUntilExplicitResumeAndPreservesTurns() {
        let app = setupPreview("memory-warning-drain")
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
    func testMemoryInterruptionDuringApprovedSetup() { verifySetupInterruption("memory-setup") }

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
