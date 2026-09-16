import XCTest

@MainActor
final class TripReelFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(at screen: String = "trips", premium: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-qaScreen", screen, "-qaNoHint"]
        if premium {
            app.launchArguments.append("-qaPremium")
        }
        app.launchEnvironment["TRIPREEL_DEVELOPMENT_AUTH_TOKEN"] = String(repeating: "u", count: 32)
        app.launch()
    }

    private func screen(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func button(startingWith label: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", label))
            .firstMatch
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMemoriesWelcomeShowsBrandStoryAndOneTimeSetup() {
        launchApp(at: "welcome")

        XCTAssertTrue(screen("welcome-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label ==[c] %@", "Memories"))
                .firstMatch
                .exists
        )
        XCTAssertTrue(app.staticTexts["Turn the photos that matter into a story."].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "become one animated story"))
                .firstMatch
                .exists
        )
        XCTAssertTrue(app.buttons["Get started"].exists)
    }

    func testCoreFilmCreationFlow() {
        launchApp(premium: true)
        XCTAssertTrue(screen("trips-screen").waitForExistence(timeout: 3))

        app.buttons["trip-row-demo-da-nang"].tap()
        XCTAssertTrue(screen("building-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("first-watch-screen").waitForExistence(timeout: 7))

        let skipToEnd = screen("first-watch-skip-button")
        XCTAssertTrue(skipToEnd.waitForExistence(timeout: 3))
        skipToEnd.tap()

        let changeIt = screen("first-watch-change-button")
        XCTAssertTrue(changeIt.waitForExistence(timeout: 6))
        changeIt.tap()
        XCTAssertTrue(screen("first-cut-options-screen").waitForExistence(timeout: 3))
        screen("edit-film-button").tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        let editMenu = screen("studio-edit-menu")
        XCTAssertTrue(editMenu.waitForExistence(timeout: 3))
        let firstClip = button(startingWith: "Clip 1,")
        XCTAssertTrue(firstClip.waitForExistence(timeout: 3))
        firstClip.tap()
        XCTAssertTrue(screen("studio-clip-remove").waitForExistence(timeout: 2))
        screen("studio-clip-remove").tap()
        XCTAssertTrue(screen("studio-undo-remove").waitForExistence(timeout: 2))
        screen("studio-undo-remove").tap()
        screen("studio-clip-done").tap()

        screen("studio-edit-menu").swipeLeft()
        screen("studio-tool-pace").tap()
        XCTAssertTrue(screen("pace-screen").waitForExistence(timeout: 3))

        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.72)
        app.buttons["Apply pace"].tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        screen("studio-edit-menu").swipeLeft()
        screen("studio-tool-style").tap()
        XCTAssertTrue(screen("film-style-sheet").waitForExistence(timeout: 3))
        let stylePreview = screen("film-style-live-preview")
        XCTAssertTrue(stylePreview.waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Journal")).firstMatch.tap()
        expectation(
            for: NSPredicate(format: "label CONTAINS[c] %@", "Journal"),
            evaluatedWith: stylePreview
        )
        waitForExpectations(timeout: 2)
        app.buttons["Done"].tap()

        let studioExport = screen("studio-export-button")
        XCTAssertTrue(studioExport.waitForExistence(timeout: 3))
        studioExport.tap()
        XCTAssertTrue(screen("export-screen").waitForExistence(timeout: 3))

        let standardExport = screen("export-standard")
        XCTAssertTrue(standardExport.waitForExistence(timeout: 2))
        standardExport.tap()
        XCTAssertTrue(screen("rendering-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("film-ready-screen").waitForExistence(timeout: 8))

        button(startingWith: "Save Video").tap()
        XCTAssertTrue(screen("cleanup-screen").waitForExistence(timeout: 3))
    }

    func testSingleMemoryCollectionRemovesUnhelpfulTabs() {
        launchApp()
        XCTAssertTrue(screen("trips-screen").waitForExistence(timeout: 3))
        XCTAssertFalse(screen("cloud-analysis-settings-card").exists)
        XCTAssertTrue(app.staticTexts["Your memories"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Overseas"].exists)
        XCTAssertFalse(app.buttons["Local"].exists)
        XCTAssertTrue(screen("trips-screen").exists)
    }

    func testFilmStudioOffersFullPreviewAndClipManager() {
        launchApp(at: "secondWatch")
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        screen("full-preview-button").tap()
        XCTAssertTrue(screen("full-film-preview").waitForExistence(timeout: 3))
        app.buttons["Close preview"].tap()

        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))
        screen("studio-tool-clips").tap()
        XCTAssertTrue(screen("film-moment-manager-sheet").waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))
    }

    func testStudioBackReturnsToFirstCutOptions() {
        launchApp(at: "secondWatch")
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        screen("app-back-button").tap()

        XCTAssertTrue(screen("first-cut-options-screen").waitForExistence(timeout: 3))
    }

    func testFirstCutEndsOnTheKeepOfferRatherThanARoutingScreen() {
        launchApp(at: "firstWatch")
        XCTAssertTrue(screen("first-watch-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("first-watch-audio").exists)
        XCTAssertTrue(app.buttons["Pause soundtrack"].waitForExistence(timeout: 2))
        XCTAssertFalse(screen("improve-with-ai-button").exists)
        XCTAssertFalse(screen("edit-film-button").exists)

        // Nothing is asked for while the film is still playing.
        XCTAssertFalse(screen("first-watch-keep-button").exists)
        XCTAssertFalse(screen("story-pass-sheet").exists)

        screen("first-watch-skip-button").tap()

        XCTAssertTrue(screen("first-watch-end-card").waitForExistence(timeout: 6))
        XCTAssertTrue(screen("first-watch-keep-button").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("first-watch-replay-button").exists)
        XCTAssertTrue(screen("first-watch-another-take-button").exists)
        XCTAssertTrue(screen("first-watch-change-button").exists)
        attachScreenshot(named: "First Watch keep offer")
    }

    func testKeepOfferRaisesTheStoryPassOverTheFilmAndKeepsTheFreeTrailer() {
        launchApp(at: "firstWatch")
        XCTAssertTrue(screen("first-watch-screen").waitForExistence(timeout: 3))

        screen("first-watch-skip-button").tap()
        XCTAssertTrue(screen("first-watch-keep-button").waitForExistence(timeout: 6))
        screen("first-watch-keep-button").tap()

        let sheet = screen("story-pass-sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["STORY PASS · THIS MEMORY"].exists)
        XCTAssertTrue(screen("story-pass-free-trailer-button").exists)
        // The film is still there underneath, not swapped for a paywall screen.
        XCTAssertTrue(screen("first-watch-screen").exists)
        attachScreenshot(named: "Story Pass over First Watch")

        screen("app-back-button").tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))
        XCTAssertTrue(screen("first-watch-keep-button").waitForExistence(timeout: 3))
    }

    func testChangeItStillReachesTheFirstCutOptions() {
        launchApp(at: "firstWatch")
        XCTAssertTrue(screen("first-watch-screen").waitForExistence(timeout: 3))

        screen("first-watch-skip-button").tap()
        XCTAssertTrue(screen("first-watch-change-button").waitForExistence(timeout: 6))
        screen("first-watch-change-button").tap()

        XCTAssertTrue(screen("first-cut-options-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("improve-with-ai-button").exists)
        XCTAssertTrue(screen("edit-film-button").exists)
        XCTAssertTrue(screen("export-first-cut-button").exists)
        XCTAssertTrue(app.staticTexts["Created privately on your iPhone"].exists)
    }

    func testSatisfiedUserCanExportFirstCutDirectlyAndReturn() {
        launchApp(at: "firstCutOptions")
        XCTAssertTrue(screen("first-cut-options-screen").waitForExistence(timeout: 3))

        screen("export-first-cut-button").tap()

        XCTAssertTrue(screen("export-screen").waitForExistence(timeout: 3))
        screen("app-back-button").tap()
        XCTAssertTrue(screen("first-cut-options-screen").waitForExistence(timeout: 3))
    }

    func testPaywallExplainsTheFreeLimitAndExportsItImmediately() {
        launchApp(at: "paywall")

        XCTAssertTrue(screen("paywall-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Keep every moment"].exists)
        XCTAssertTrue(screen("paywall-free-summary").exists)
        XCTAssertTrue(screen("full-story-highlight").exists)
        let freeExport = screen("export-free-from-paywall")
        XCTAssertTrue(freeExport.exists)

        freeExport.tap()
        XCTAssertTrue(screen("rendering-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("film-ready-screen").waitForExistence(timeout: 8))
    }

    func testAIConsentComesBeforeDirectionAndDeclineReturnsSafely() {
        launchApp(at: "firstCutOptions")
        XCTAssertTrue(screen("first-cut-options-screen").waitForExistence(timeout: 3))
        button(startingWith: "Improve with AI").tap()
        XCTAssertTrue(screen("cloud-analysis-consent").waitForExistence(timeout: 3))
        XCTAssertFalse(screen("ai-direction-screen").exists)
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "GPT-5.6 Luna"))
                .firstMatch
                .exists
        )
        attachScreenshot(named: "AI consent before direction")
        button(startingWith: "Not now").tap()

        XCTAssertTrue(screen("first-cut-options-screen").waitForExistence(timeout: 3))
    }

    func testAIConsentThenLetsUserChooseExactPhotos() {
        launchApp(at: "firstCutOptions")
        XCTAssertTrue(screen("first-cut-options-screen").waitForExistence(timeout: 3))
        button(startingWith: "Improve with AI").tap()
        XCTAssertTrue(screen("cloud-analysis-consent").waitForExistence(timeout: 3))

        button(startingWith: "Allow & continue").tap()

        XCTAssertTrue(screen("ai-direction-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Pick moments"].exists)
        XCTAssertTrue(screen("ai-setup-step-moments").exists)
        XCTAssertFalse(screen("ai-setup-step-story").exists)
        XCTAssertFalse(screen("ai-setup-step-direction").exists)
        attachScreenshot(named: "AI moments step")

        let photoPicker = button(startingWith: "Moments for AI")
        XCTAssertTrue(photoPicker.waitForExistence(timeout: 2))
        photoPicker.tap()

        XCTAssertTrue(screen("ai-photo-selection-sheet").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Deselect one moment to choose another"].exists)
        XCTAssertTrue(app.buttons["Best moments"].exists)
        let bulkSelection = app.buttons
            .matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "Select all", "Fill "))
            .firstMatch
        XCTAssertTrue(bulkSelection.exists)
        XCTAssertTrue(app.buttons["Clear"].exists)
        attachScreenshot(named: "AI exact photo selection")

        app.buttons["Done"].firstMatch.tap()
        XCTAssertFalse(screen("ai-photo-selection-sheet").waitForExistence(timeout: 2))
        XCTAssertTrue(screen("ai-setup-step-moments").waitForExistence(timeout: 2))
        XCTAssertTrue(button(startingWith: "Continue").waitForExistence(timeout: 2))
        button(startingWith: "Continue").tap()
        XCTAssertTrue(screen("ai-setup-step-story").waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["What happened?"].exists)
        XCTAssertFalse(screen("ai-setup-step-direction").exists)

        let requiredContinue = button(startingWith: "Continue")
        XCTAssertTrue(requiredContinue.waitForExistence(timeout: 2))
        XCTAssertFalse(requiredContinue.isEnabled)
        let clue = app.textFields.firstMatch
        XCTAssertTrue(clue.waitForExistence(timeout: 2))
        clue.tap()
        clue.typeText("Our students won the competition")
        XCTAssertTrue(requiredContinue.isEnabled)
        button(startingWith: "Continue").tap()
        XCTAssertTrue(screen("ai-setup-step-direction").waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Pick a style"].exists)
        XCTAssertTrue(screen("ai-direction-choice-dynamic").exists)
        attachScreenshot(named: "AI direction step")

        screen("app-back-button").tap()
        XCTAssertTrue(screen("ai-setup-step-story").waitForExistence(timeout: 2))
        screen("app-back-button").tap()
        XCTAssertTrue(screen("ai-setup-step-moments").waitForExistence(timeout: 2))
    }

    func testAICutComparisonKeepsExportAndEditAsDistinctRoutes() {
        launchApp(at: "aiComparison")
        XCTAssertTrue(screen("ai-comparison-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("compare-firstCut").exists)
        XCTAssertTrue(screen("compare-aiCut").exists)

        let export = screen("use-ai-cut-button")
        XCTAssertTrue(export.waitForExistence(timeout: 2))
        export.tap()
        XCTAssertTrue(screen("export-screen").waitForExistence(timeout: 3))

        screen("app-back-button").tap()
        XCTAssertTrue(screen("ai-comparison-screen").waitForExistence(timeout: 3))
        screen("edit-compared-cut-button").tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))
    }

    func testAICutComparisonKeepsRetiredGenerativeVideoOutOfTheFlow() {
        launchApp(at: "aiComparison")
        XCTAssertTrue(screen("ai-comparison-screen").waitForExistence(timeout: 3))
        XCTAssertFalse(screen("open-ai-video-button").exists)
        XCTAssertTrue(screen("use-ai-cut-button").exists)
        XCTAssertTrue(screen("edit-compared-cut-button").exists)
    }

    func testAIProcessingShowsSecureTransferAndCanCancel() {
        launchApp(at: "aiProcessing")
        XCTAssertTrue(screen("ai-processing-screen").waitForExistence(timeout: 3))
        let transfer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Original media"))
            .firstMatch
        XCTAssertTrue(transfer.waitForExistence(timeout: 2))

        let cancel = app.buttons["Cancel AI edit"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.tap()

        XCTAssertTrue(screen("first-cut-options-screen").waitForExistence(timeout: 3))
    }

    func testEveryTitleIsAvailableInTheVisualTimelineEditor() {
        launchApp(at: "secondWatch")
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        let editMenu = screen("studio-edit-menu")
        XCTAssertTrue(editMenu.waitForExistence(timeout: 3))
        screen("studio-tool-titles").tap()

        XCTAssertTrue(screen("title-editor-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("title-live-preview").exists)
        XCTAssertTrue(screen("title-timeline-opening").exists)
        XCTAssertTrue(screen("title-timeline-place").exists)
        XCTAssertTrue(screen("title-timeline-ending").exists)

        screen("title-timeline-place").tap()
        XCTAssertTrue(screen("title-main-text").exists)
        XCTAssertTrue(screen("title-subtitle-text").exists)
        screen("title-style-bold").tap()

        screen("title-timeline-ending").tap()
        XCTAssertTrue(screen("title-enabled-toggle").exists)
        app.buttons["Done"].tap()

        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))
    }

    func testExportOffersFreeAndStoryPassVideoChoices() {
        launchApp(at: "export")
        XCTAssertTrue(screen("export-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("export-standard").exists)
        XCTAssertTrue(screen("export-hd").exists)
        XCTAssertFalse(screen("export-project").exists)

        screen("export-standard").tap()
        XCTAssertTrue(screen("rendering-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("film-ready-screen").waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "doesn’t save exported videos"))
                .firstMatch
                .exists
        )
        XCTAssertTrue(button(startingWith: "Share Reel").exists)
        XCTAssertTrue(button(startingWith: "Save Video").exists)
    }

    func testCleanupShowsDestructiveWarningBeforePhotosRequest() {
        launchApp(at: "cleanup")
        XCTAssertTrue(screen("cleanup-screen").waitForExistence(timeout: 3))

        app.buttons["Review cut photos"].tap()

        let selectAll = screen("cleanup-select-all")
        XCTAssertTrue(selectAll.waitForExistence(timeout: 2))
        selectAll.tap()
        XCTAssertTrue(app.buttons["Delete 24 photos"].waitForExistence(timeout: 2))

        app.buttons["Delete 24 photos"].tap()
        let bulkWarning = app.alerts["Delete 24 original photos?"]
        XCTAssertTrue(bulkWarning.waitForExistence(timeout: 2))
        XCTAssertTrue(
            bulkWarning.staticTexts
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "including any thumbnail"))
                .firstMatch
                .exists
        )
        bulkWarning.buttons["Cancel"].tap()

        let clearAll = screen("cleanup-clear-all")
        XCTAssertTrue(clearAll.exists)
        clearAll.tap()
        XCTAssertTrue(app.buttons["Nothing selected"].waitForExistence(timeout: 2))

        let firstPhoto = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Select IMG_"))
            .firstMatch
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 2))
        firstPhoto.tap()
        app.buttons["Delete 1 photo"].tap()

        let warning = app.alerts["Delete 1 original photo?"]
        XCTAssertTrue(warning.waitForExistence(timeout: 2))
        XCTAssertTrue(warning.buttons["Delete from Photos"].exists)
        XCTAssertTrue(warning.buttons["Cancel"].exists)
        warning.buttons["Cancel"].tap()
    }
}
