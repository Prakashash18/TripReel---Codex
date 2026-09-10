import XCTest

@MainActor
final class TripReelFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(at screen: String = "trips") {
        app = XCUIApplication()
        app.launchArguments = ["-qaScreen", screen, "-qaNoHint"]
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

    func testCoreFilmCreationFlow() {
        launchApp()
        XCTAssertTrue(screen("trips-screen").waitForExistence(timeout: 3))

        app.buttons["trip-row-demo-da-nang"].tap()
        XCTAssertTrue(screen("building-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("first-watch-screen").waitForExistence(timeout: 7))

        let continueButton = screen("first-cut-continue-button")
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        continueButton.tap()
        XCTAssertTrue(screen("first-cut-options-screen").waitForExistence(timeout: 3))
        screen("edit-film-button").tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        let editMenu = screen("studio-edit-menu")
        XCTAssertTrue(editMenu.waitForExistence(timeout: 3))
        screen("studio-tool-photos").tap()
        XCTAssertTrue(screen("cut-screen").waitForExistence(timeout: 3))

        app.buttons["Cut photo"].tap()
        let doneSelecting = screen("finish-photo-selection-button")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: doneSelecting)
        waitForExpectations(timeout: 2)
        doneSelecting.tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

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

        let standardExport = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Standard"))
            .firstMatch
        XCTAssertTrue(standardExport.waitForExistence(timeout: 2))
        standardExport.tap()
        XCTAssertTrue(screen("rendering-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("film-ready-screen").waitForExistence(timeout: 8))

        app.buttons["Save"].tap()
        XCTAssertTrue(screen("cleanup-screen").waitForExistence(timeout: 3))
    }

    func testTripsAndNearbyStayInOneCalmCollectionScreen() {
        launchApp()
        XCTAssertTrue(screen("trips-screen").waitForExistence(timeout: 3))
        XCTAssertFalse(screen("cloud-analysis-settings-card").exists)

        app.buttons["Nearby"].tap()

        XCTAssertTrue(app.staticTexts["Nearby moments"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["No nearby outings yet"].exists)
        XCTAssertTrue(screen("trips-screen").exists)
    }

    func testFilmStudioOffersFullPreviewAndPhotoSelectionLoop() {
        launchApp(at: "secondWatch")
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        screen("full-preview-button").tap()
        XCTAssertTrue(screen("full-film-preview").waitForExistence(timeout: 3))
        app.buttons["Close preview"].tap()

        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))
        screen("studio-tool-photos").tap()
        XCTAssertTrue(screen("cut-screen").waitForExistence(timeout: 3))
        screen("finish-photo-selection-button").tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))
    }

    func testStudioBackReturnsToFirstCutOptions() {
        launchApp(at: "secondWatch")
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        screen("app-back-button").tap()

        XCTAssertTrue(screen("first-cut-options-screen").waitForExistence(timeout: 3))
    }

    func testFirstCutPlaybackHasOneDecisionThenOffersTwoPaths() {
        launchApp(at: "firstWatch")
        XCTAssertTrue(screen("first-watch-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("first-cut-continue-button").exists)
        XCTAssertTrue(screen("first-watch-audio").exists)
        XCTAssertTrue(app.buttons["Pause soundtrack"].waitForExistence(timeout: 2))
        XCTAssertFalse(screen("improve-with-ai-button").exists)
        XCTAssertFalse(screen("edit-film-button").exists)

        screen("first-cut-continue-button").tap()

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

        button(startingWith: "Allow & choose photos").tap()

        XCTAssertTrue(screen("ai-direction-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Choose photos & direction"].exists)
        XCTAssertTrue(app.staticTexts["36 small previews will be sent to OpenAI’s GPT-5.6 Luna."].exists)
        attachScreenshot(named: "AI photo and direction choices")

        let photoPicker = button(startingWith: "Photos for AI")
        XCTAssertTrue(photoPicker.waitForExistence(timeout: 2))
        photoPicker.tap()

        XCTAssertTrue(screen("ai-photo-selection-sheet").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Deselect one photo to choose another"].exists)
        XCTAssertTrue(app.buttons["Suggested"].exists)
        XCTAssertTrue(app.buttons["Clear"].exists)
        attachScreenshot(named: "AI exact photo selection")
    }

    func testAICutComparisonKeepsBothVersionsEditable() {
        launchApp(at: "aiComparison")
        XCTAssertTrue(screen("ai-comparison-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("compare-firstCut").exists)
        XCTAssertTrue(screen("compare-aiCut").exists)

        screen("compare-firstCut").tap()
        XCTAssertTrue(screen("edit-compared-cut-button").exists)
        XCTAssertTrue(screen("use-ai-cut-button").exists)
    }

    func testAIProcessingShowsSecureTransferAndCanCancel() {
        launchApp(at: "aiProcessing")
        XCTAssertTrue(screen("ai-processing-screen").waitForExistence(timeout: 3))
        let transfer = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "reduced preview copies"))
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

    func testCapCutPathRendersACompatibleMovie() {
        launchApp(at: "export")
        XCTAssertTrue(screen("export-screen").waitForExistence(timeout: 3))

        screen("export-project").tap()
        let renderForCapCut = screen("render-capcut-video")
        XCTAssertTrue(renderForCapCut.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["CapCut, InShot, spreadsheets"].exists)

        renderForCapCut.tap()
        XCTAssertTrue(screen("rendering-screen").waitForExistence(timeout: 3))
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
