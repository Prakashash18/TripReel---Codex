import XCTest

final class TripReelFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-qaScreen", "trips", "-qaNoHint"]
        app.launch()
    }

    private func screen(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testCoreFilmCreationFlow() {
        XCTAssertTrue(screen("trips-screen").waitForExistence(timeout: 3))

        app.buttons["Da Nang, Vietnam, 84 photos"].tap()
        XCTAssertTrue(screen("building-screen").waitForExistence(timeout: 3))
        XCTAssertTrue(screen("first-watch-screen").waitForExistence(timeout: 7))

        screen("edit-film-button").tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        screen("photo-selection-button").tap()
        XCTAssertTrue(screen("cut-screen").waitForExistence(timeout: 3))

        app.buttons["Cut photo"].tap()
        let doneSelecting = screen("finish-photo-selection-button")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: doneSelecting)
        waitForExpectations(timeout: 2)
        doneSelecting.tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        app.buttons["Pace"].tap()
        XCTAssertTrue(screen("pace-screen").waitForExistence(timeout: 3))

        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.72)
        app.buttons["Apply pace"].tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Style")).firstMatch.tap()
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

        app.buttons["Export"].tap()
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
        XCTAssertTrue(screen("trips-screen").waitForExistence(timeout: 3))

        app.buttons["Nearby"].tap()

        XCTAssertTrue(app.staticTexts["Nearby moments"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["No nearby outings yet"].exists)
        XCTAssertTrue(screen("trips-screen").exists)
    }

    func testFilmStudioOffersFullPreviewAndPhotoSelectionLoop() {
        app.terminate()
        app.launchArguments = ["-qaScreen", "secondWatch", "-qaNoHint"]
        app.launch()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        screen("full-preview-button").tap()
        XCTAssertTrue(screen("full-film-preview").waitForExistence(timeout: 3))
        app.buttons["Close preview"].tap()

        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))
        screen("photo-selection-button").tap()
        XCTAssertTrue(screen("cut-screen").waitForExistence(timeout: 3))
        screen("finish-photo-selection-button").tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))
    }

    func testCleanupShowsDestructiveWarningBeforePhotosRequest() {
        app.terminate()
        app.launchArguments = ["-qaScreen", "cleanup", "-qaNoHint"]
        app.launch()
        XCTAssertTrue(screen("cleanup-screen").waitForExistence(timeout: 3))

        app.buttons["Review cut photos"].tap()
        let firstPhoto = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Select "))
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
