import XCTest

// Tager App Store-skærmbilleder af demo-familien (issue #20).
//
// Køres af .github/workflows/ios-screenshots.yml på en simulator:
//   xcodebuild test … -only-testing:MindebogUITests \
//     TEST_RUNNER_SCREENSHOT_DIR=<mappe til png'er> \
//     TEST_RUNNER_DEMO_PHOTOS_DIR=<ios/Demo/photos>
// Appen startes med "-demo", så den viser den fiktive familie fra DemoFamily.swift
// (kun i hukommelsen — aldrig iCloud).
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var outDir: URL!
    private var shot = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        outDir = URL(fileURLWithPath: env["SCREENSHOT_DIR"] ?? NSTemporaryDirectory() + "/screenshots")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchArguments += ["-demo", "-AppleLanguages", "(da)", "-AppleLocale", "da_DK"]
        app.launchEnvironment["DEMO_PHOTOS_DIR"] = env["DEMO_PHOTOS_DIR"] ?? ""
        // Systemdialoger (fx notifikationer) må ikke stoppe turen.
        addUIInterruptionMonitor(withDescription: "Systemdialog") { alert in
            for title in ["Tillad", "Allow", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap(); return true
            }
            return false
        }
        app.launch()
    }

    func testScreenshots() throws {
        // 1. Hjem (billederne i "Seneste" og "På denne dag" hentes lidt efter listen)
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 30), "Hjem kom ikke frem")
        settle(5)
        snap("hjem")

        // 2. Børn
        tab("Børn"); settle()
        snap("boern")

        // 3. Barnets side (Nohr)
        tapText("Nohr"); settle()
        snap("barn")

        // 4. Højdepunkter
        tapText("Højdepunkter"); settle(2)
        snap("hoejdepunkter")
        back()

        // 5. Det årlige interview
        swipeUpIfNeeded(toFind: "Det årlige interview")
        tapText("Det årlige interview"); settle()
        snap("interview")
        back()

        // 6. Milepæle
        swipeUpIfNeeded(toFind: "Milepæle")
        tapText("Milepæle"); settle()
        snap("milepaele")
        back()

        // 7. Familie → Minder (kortet under billedet skal nå at blive tegnet)
        tab("Familie"); settle(6)
        snap("familie-minder")

        // 8. Opskrifter
        tapText("Opskrifter"); settle()
        snap("opskrifter")

        // 9. Traditioner
        tapText("Traditioner"); settle()
        snap("traditioner")

        // 10. Rejser (med kort)
        tapText("Rejser"); settle(5)
        snap("rejser")
        // Verdenskortet med alle rejserne (til opslag og landingsside).
        if app.buttons["Kort"].exists { app.buttons["Kort"].tap() } else { tapText("Kort") }
        settle(6)
        snap("rejser-kort")
        if app.buttons["Liste"].exists { app.buttons["Liste"].tap() }
        settle()

        // 11. Breve til barnet (landingssiden, #50) — Børn-fanen står stadig på Nohrs side.
        tab("Børn"); settle()
        if !app.staticTexts["Breve til dig"].exists { tapText("Nohr"); settle() }
        swipeUpIfNeeded(toFind: "Breve til dig")
        tapText("Breve til dig"); settle(2)
        snap("breve")
        back()

        // 12. Mindebogen som PDF (landingssiden, #50): menuen ••• → Lav mindebog → til skærm.
        app.swipeDown(); settle(1)
        let menu = app.navigationBars.buttons.element(boundBy: app.navigationBars.buttons.count - 1)
        if menu.waitForExistence(timeout: 5) {
            menu.tap(); settle(1)
            tapText("Lav mindebog (PDF)"); settle(1)
            tapText("Til skærm og hjemmeprint")
            settle(10)   // bogen bygges, og del-arket med forhåndsvisning åbner
            snap("bog")
        }
        // Søgning er taget ud: ét resultat og et stort tastatur gør sig dårligt i App Store.
    }

    // MARK: - Hjælpere

    private func tab(_ title: String) {
        let button = app.tabBars.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Fanen \(title) findes ikke")
        button.tap()
    }

    private func tapText(_ text: String) {
        let element = app.staticTexts[text].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\"\(text)\" findes ikke på skærmen")
        element.tap()
    }

    private func swipeUpIfNeeded(toFind text: String) {
        let element = app.staticTexts[text].firstMatch
        var tries = 0
        while !element.isHittable && tries < 4 { app.swipeUp(); tries += 1 }
    }

    private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.waitForExistence(timeout: 5) { button.tap() }
        settle(1)
    }

    private func settle(_ seconds: Double = 1.5) {
        _ = app.wait(for: .runningForeground, timeout: 5)
        Thread.sleep(forTimeInterval: seconds)
    }

    private func snap(_ name: String) {
        shot += 1
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let file = outDir.appendingPathComponent(String(format: "%02d-%@.png", shot, name))
        do { try png.write(to: file) } catch { XCTFail("Kunne ikke skrive \(file.path): \(error)") }
        let attachment = XCTAttachment(uniformTypeIdentifier: "public.png", name: file.lastPathComponent, payload: png)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
