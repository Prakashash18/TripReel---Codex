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

        app.buttons["Refine it"].tap()
        XCTAssertTrue(screen("cut-screen").waitForExistence(timeout: 3))

        app.buttons["Cut photo"].tap()
        let doneCutting = app.buttons["Done cutting"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: doneCutting)
        waitForExpectations(timeout: 2)
        doneCutting.tap()
        XCTAssertTrue(screen("pace-screen").waitForExistence(timeout: 3))

        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.72)
        app.buttons["Watch it"].tap()
        XCTAssertTrue(screen("second-watch-screen").waitForExistence(timeout: 3))

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Style")).firstMatch.tap()
        XCTAssertTrue(screen("film-style-sheet").waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Journal")).firstMatch.tap()
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
}
