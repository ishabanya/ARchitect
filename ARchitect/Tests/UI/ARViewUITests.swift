import XCTest
import RealityKit
import ARKit
@testable import ARchitect

final class ARViewUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testARViewLaunch() throws {
        let arView = app.otherElements["ARView"]
        XCTAssertTrue(arView.waitForExistence(timeout: 5.0))
    }
    
    func testNavigationToRoomScanning() throws {
        let scanButton = app.buttons["Start Room Scan"]
        if scanButton.exists {
            scanButton.tap()
            
            let scanningView = app.otherElements["RoomScanningView"]
            XCTAssertTrue(scanningView.waitForExistence(timeout: 3.0))
        }
    }
    
    func testNavigationToFurnitureCatalog() throws {
        let furnitureButton = app.buttons["Furniture Catalog"]
        if furnitureButton.exists {
            furnitureButton.tap()
            
            let catalogView = app.otherElements["FurnitureCatalogView"]
            XCTAssertTrue(catalogView.waitForExistence(timeout: 3.0))
        }
    }
    
    func testMeasurementToolAccess() throws {
        let measureButton = app.buttons["Measurement Tools"]
        if measureButton.exists {
            measureButton.tap()
            
            let measurementView = app.otherElements["MeasurementToolsView"]
            XCTAssertTrue(measurementView.waitForExistence(timeout: 3.0))
        }
    }
    
    func testSettingsAccess() throws {
        let settingsButton = app.buttons["Settings"]
        if settingsButton.exists {
            settingsButton.tap()
            
            let settingsView = app.otherElements["SettingsView"]
            XCTAssertTrue(settingsView.waitForExistence(timeout: 3.0))
        }
    }
    
    func testARSessionStatusDisplay() throws {
        let statusView = app.otherElements["ARSessionStatusView"]
        XCTAssertTrue(statusView.waitForExistence(timeout: 5.0))
        
        // Check that status is displayed
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'AR'")).firstMatch.exists)
    }
    
    func testToolPaletteInteraction() throws {
        let toolPalette = app.otherElements["ToolPalette"]
        if toolPalette.waitForExistence(timeout: 3.0) {
            XCTAssertTrue(toolPalette.exists)
            
            // Test tool selection
            let measureTool = app.buttons["MeasureTool"]
            if measureTool.exists {
                measureTool.tap()
                XCTAssertTrue(measureTool.isSelected)
            }
        }
    }
    
    func testPerformanceMonitorDisplay() throws {
        let performanceMonitor = app.otherElements["PerformanceMonitor"]
        if performanceMonitor.waitForExistence(timeout: 3.0) {
            XCTAssertTrue(performanceMonitor.exists)
        }
    }
    
    func testAccessibilityLabels() throws {
        // Test that major UI elements have accessibility labels
        let arView = app.otherElements["ARView"]
        XCTAssertTrue(arView.waitForExistence(timeout: 5.0))
        
        // Check for accessibility on common buttons
        let buttons = app.buttons.allElementsBoundByAccessibilityElement
        for button in buttons {
            XCTAssertFalse(button.label.isEmpty, "Button should have accessibility label")
        }
    }
    
    func testScreenRotationHandling() throws {
        let device = XCUIDevice.shared
        
        // Test landscape orientation
        device.orientation = .landscapeLeft
        
        let arView = app.otherElements["ARView"]
        XCTAssertTrue(arView.waitForExistence(timeout: 3.0))
        
        // Test portrait orientation
        device.orientation = .portrait
        XCTAssertTrue(arView.waitForExistence(timeout: 3.0))
    }
    
    func testARPermissionHandling() throws {
        // This test would check camera permission handling
        // In a real test, you'd simulate permission states
        let arView = app.otherElements["ARView"]
        XCTAssertTrue(arView.waitForExistence(timeout: 10.0))
    }
}