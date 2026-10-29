import XCTest

final class BitdriftCUJDemoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testReadingJourneySuccess() throws {
        let app = XCUIApplication()
        app.launchArguments += ProcessInfo().arguments
        app.launch()

        sleep(2)
        add(screenshot("01-launch"))

        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.waitForExistence(timeout: 5) {
            searchTab.tap()
        }
        sleep(1)
        add(screenshot("02-search-tab"))

        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 5) {
            searchField.tap()
            searchField.typeText("Dolly Parton")
        }
        sleep(2)
        add(screenshot("03-search-results"))

        // Search results render in a collection view (label "Search results"), not a table.
        let firstCell = app.collectionViews["Search results"].cells.firstMatch
        if firstCell.waitForExistence(timeout: 5) {
            firstCell.tap()
        }
        sleep(2)
        add(screenshot("04-article-opened"))

        app.swipeUp()
        sleep(1)
        app.swipeUp()
        sleep(1)
        add(screenshot("05-article-scrolled"))

        // Let bitdrift's periodic buffer upload flush before XCUITest tears the app down.
        sleep(10)
    }

    func testSearchAbandoned() throws {
        let app = XCUIApplication()
        app.launchArguments += ProcessInfo().arguments
        app.launch()

        sleep(2)

        let searchTab = app.tabBars.buttons["Search"]
        if searchTab.waitForExistence(timeout: 5) {
            searchTab.tap()
        }
        sleep(1)

        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 5) {
            searchField.tap()
            searchField.typeText("asteroid mining")
        }
        sleep(2)
        add(screenshot("abandoned-search-results"))

        let exploreTab = app.tabBars.buttons["Explore"]
        if exploreTab.waitForExistence(timeout: 5) {
            exploreTab.tap()
        }
        sleep(1)
        add(screenshot("abandoned-back-to-explore"))

        // Let bitdrift's periodic buffer upload flush before XCUITest tears the app down.
        sleep(10)
    }

    private func screenshot(_ name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
