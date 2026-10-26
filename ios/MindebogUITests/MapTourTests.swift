import XCTest

// Kort video af verdenskortet under Rejser (til opslag på Instagram/Facebook).
// Workflowet optager simulatorens skærm, mens denne test kører (ios-screenshots.yml, trinnet "Video").
// Demo-familien har rejser i Danmark, Norge, Skotland, Italien og Portugal.
final class MapTourTests: XCTestCase {
    func testMapTour() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-demo", "-AppleLanguages", "(da)", "-AppleLocale", "da_DK"]
        app.launchEnvironment["DEMO_PHOTOS_DIR"] = ProcessInfo.processInfo.environment["DEMO_PHOTOS_DIR"] ?? ""
        app.launch()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 30))
        pause(3)

        app.tabBars.buttons["Familie"].tap(); pause(2)
        app.staticTexts["Rejser"].firstMatch.tap(); pause(2.5)
        if app.buttons["Kort"].exists { app.buttons["Kort"].tap() } else { app.staticTexts["Kort"].firstMatch.tap() }
        pause(4)   // kortet tegnes og zoomer ud, så alle rejser ses

        let map = app.maps.firstMatch
        guard map.waitForExistence(timeout: 10) else { return XCTFail("Kortet kom ikke frem") }
        // Rolig tur: zoom ind mod Skandinavien, glid ned mod Sydeuropa, zoom ud igen.
        map.pinch(withScale: 2.2, velocity: 0.6); pause(2)
        drag(map, from: CGVector(dx: 0.5, dy: 0.35), to: CGVector(dx: 0.5, dy: 0.6)); pause(2)
        drag(map, from: CGVector(dx: 0.5, dy: 0.7), to: CGVector(dx: 0.55, dy: 0.3)); pause(2)
        drag(map, from: CGVector(dx: 0.35, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5)); pause(2)
        map.pinch(withScale: 0.45, velocity: -0.6); pause(3)
    }

    private func drag(_ element: XCUIElement, from: CGVector, to: CGVector) {
        let a = element.coordinate(withNormalizedOffset: from)
        let b = element.coordinate(withNormalizedOffset: to)
        a.press(forDuration: 0.1, thenDragTo: b, withVelocity: 350, thenHoldForDuration: 0.2)
    }

    private func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }
}
