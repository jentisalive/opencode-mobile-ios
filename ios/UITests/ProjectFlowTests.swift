import XCTest

final class ProjectFlowTests: XCTestCase {
    func testCreateProjectEditFileAndReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let createProject = app.buttons["New project"]
        XCTAssertTrue(createProject.waitForExistence(timeout: 60))
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "Home screen"
        home.lifetime = .keepAlways
        add(home)
        createProject.tap()
        let name = "test-" + UUID().uuidString.prefix(8).lowercased()
        let projectName = app.textFields["Project name"]
        XCTAssertTrue(projectName.waitForExistence(timeout: 5))
        projectName.tap(); projectName.typeText(name)
        app.buttons["Create project"].tap()
        let project = app.buttons[name]
        XCTAssertTrue(project.waitForExistence(timeout: 5)); project.tap()
        let filename = app.textFields["Filename"]
        XCTAssertTrue(filename.waitForExistence(timeout: 5))
        filename.tap(); filename.typeText("notes.txt")
        app.buttons["Create"].tap()
        let file = app.buttons["notes.txt"]
        XCTAssertTrue(file.waitForExistence(timeout: 5)); file.tap()
        let editor = app.textViews["file-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("Saved on iOS")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(file.waitForExistence(timeout: 5)); file.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Saved on iOS")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Project file persisted"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
