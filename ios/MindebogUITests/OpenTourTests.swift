import XCTest

// Kort video af, at appen åbner med det samme (til opslaget om 1.3).
// Workflowet optager simulatorens skærm, mens denne test kører (ios-screenshots.yml, trinnet "Video").
// Appen startes i testen, så videoen viser selve åbningen.
final class OpenTourTests: XCTestCase {
    func testOpenTour() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-demo", "-AppleLanguages", "(da)", "-AppleLocale", "da_DK"]
        app.launchEnvironment["DEMO_PHOTOS_DIR"] = ProcessInfo.processInfo.environment["DEMO_PHOTOS_DIR"] ?? ""
        app.launch()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 30))
        pause(2.5)                       // familien står klar

        app.swipeUp(velocity: .slow); pause(1.5)
        app.swipeDown(velocity: .slow); pause(1)

        app.tabBars.buttons["Børn"].tap(); pause(1.5)
        let child = app.staticTexts["Nohr"].firstMatch
        XCTAssertTrue(child.waitForExistence(timeout: 10))
        child.tap(); pause(1.5)

        let highlights = app.staticTexts["Højdepunkter"].firstMatch
        XCTAssertTrue(highlights.waitForExistence(timeout: 10))
        highlights.tap(); pause(2)       // billederne er der med det samme
        app.swipeUp(velocity: .slow); pause(2)
    }

    private func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }
}
