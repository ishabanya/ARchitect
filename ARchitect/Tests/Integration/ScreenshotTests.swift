import XCTest
import RealityKit
import ARKit
@testable import ARchitect

final class ScreenshotTests: XCTestCase {
    
    var app: XCUIApplication!
    var screenshotHelper: ScreenshotHelper!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        screenshotHelper = ScreenshotHelper()
        
        // Launch app with screenshot mode
        app.launchArguments.append("--screenshot-mode")
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
        screenshotHelper = nil
    }
    
    // MARK: - Main UI Screenshots
    
    func testMainInterfaceScreenshots() throws {
        // Take screenshot of main AR interface
        let mainView = app.otherElements["ARView"]
        XCTAssertTrue(mainView.waitForExistence(timeout: 5.0))
        
        screenshotHelper.takeScreenshot(
            name: "main_ar_interface",
            description: "Main AR interface with tools and controls"
        )
        
        // Test different UI states
        testToolPaletteScreenshots()
        testNavigationScreenshots()
    }
    
    private func testToolPaletteScreenshots() {
        let toolPalette = app.otherElements["ToolPalette"]
        if toolPalette.waitForExistence(timeout: 3.0) {
            
            // Tool palette closed
            screenshotHelper.takeScreenshot(
                name: "tool_palette_closed",
                description: "Tool palette in closed state"
            )
            
            // Tool palette expanded
            toolPalette.tap()
            screenshotHelper.takeScreenshot(
                name: "tool_palette_expanded",
                description: "Tool palette showing all available tools"
            )
            
            // Individual tool selections
            let measureTool = app.buttons["MeasureTool"]
            if measureTool.exists {
                measureTool.tap()
                screenshotHelper.takeScreenshot(
                    name: "measure_tool_selected",
                    description: "Measurement tool active state"
                )
            }
        }
    }
    
    private func testNavigationScreenshots() {
        // Test tab navigation screenshots
        let tabs = ["Scan", "Furniture", "Measure", "Settings"]
        
        for tab in tabs {
            let tabButton = app.buttons[tab]
            if tabButton.exists {
                tabButton.tap()
                
                screenshotHelper.takeScreenshot(
                    name: "tab_\(tab.lowercased())",
                    description: "\(tab) tab interface"
                )
            }
        }
    }
    
    // MARK: - Room Scanning Screenshots
    
    func testRoomScanningScreenshots() throws {
        navigateToRoomScanning()
        
        // Initial scanning interface
        let scanningView = app.otherElements["RoomScanningView"]
        XCTAssertTrue(scanningView.waitForExistence(timeout: 5.0))
        
        screenshotHelper.takeScreenshot(
            name: "room_scanning_initial",
            description: "Room scanning interface before starting scan"
        )
        
        // Start scanning
        let startButton = app.buttons["Start Scanning"]
        if startButton.exists {
            startButton.tap()
            
            // Wait for scanning state
            let scanningIndicator = app.otherElements["ScanningIndicator"]
            if scanningIndicator.waitForExistence(timeout: 3.0) {
                screenshotHelper.takeScreenshot(
                    name: "room_scanning_active",
                    description: "Active room scanning with progress indicators"
                )
            }
            
            // Scanning progress
            testScanningProgressScreenshots()
            
            // Settings during scan
            testScanSettingsScreenshots()
        }
    }
    
    private func testScanningProgressScreenshots() {
        // Progress indicators
        let progressView = app.otherElements["ScanProgress"]
        if progressView.exists {
            screenshotHelper.takeScreenshot(
                name: "scan_progress_display",
                description: "Scan progress with percentage and visual feedback"
            )
        }
        
        // Quality indicators
        let qualityIndicator = app.otherElements["ScanQualityIndicator"]
        if qualityIndicator.exists {
            screenshotHelper.takeScreenshot(
                name: "scan_quality_feedback",
                description: "Scan quality indicators and recommendations"
            )
        }
    }
    
    private func testScanSettingsScreenshots() {
        let settingsButton = app.buttons["Scan Settings"]
        if settingsButton.exists {
            settingsButton.tap()
            
            let settingsView = app.otherElements["ScanSettingsView"]
            if settingsView.waitForExistence(timeout: 3.0) {
                screenshotHelper.takeScreenshot(
                    name: "scan_settings",
                    description: "Room scanning settings and quality options"
                )
                
                // Close settings
                let closeButton = app.buttons["Close"] ?? app.buttons["Done"]
                closeButton?.tap()
            }
        }
    }
    
    // MARK: - Furniture Catalog Screenshots
    
    func testFurnitureCatalogScreenshots() throws {
        navigateToFurnitureCatalog()
        
        let catalogView = app.otherElements["FurnitureCatalogView"]
        XCTAssertTrue(catalogView.waitForExistence(timeout: 5.0))
        
        // Main catalog view
        screenshotHelper.takeScreenshot(
            name: "furniture_catalog_main",
            description: "Main furniture catalog with categories"
        )
        
        // Category filtering
        testCategoryFilterScreenshots()
        
        // Individual item details
        testFurnitureItemScreenshots()
        
        // Search functionality
        testFurnitureSearchScreenshots()
    }
    
    private func testCategoryFilterScreenshots() {
        let categories = ["Chair", "Table", "Sofa", "Bed"]
        
        for category in categories {
            let categoryButton = app.buttons[category]
            if categoryButton.exists {
                categoryButton.tap()
                
                screenshotHelper.takeScreenshot(
                    name: "furniture_category_\(category.lowercased())",
                    description: "\(category) furniture category view"
                )
            }
        }
    }
    
    private func testFurnitureItemScreenshots() {
        let firstItem = app.cells.firstMatch
        if firstItem.exists {
            firstItem.tap()
            
            let detailView = app.otherElements["FurnitureItemDetailView"]
            if detailView.waitForExistence(timeout: 3.0) {
                screenshotHelper.takeScreenshot(
                    name: "furniture_item_detail",
                    description: "Furniture item detail view with specifications"
                )
                
                let placeButton = app.buttons["Place in AR"]
                if placeButton.exists {
                    screenshotHelper.takeScreenshot(
                        name: "furniture_placement_ready",
                        description: "Furniture ready for AR placement"
                    )
                }
            }
        }
    }
    
    private func testFurnitureSearchScreenshots() {
        let searchField = app.searchFields["Search Furniture"]
        if searchField.exists {
            searchField.tap()
            searchField.typeText("chair")
            
            screenshotHelper.takeScreenshot(
                name: "furniture_search_active",
                description: "Active furniture search with keyword"
            )
            
            let searchButton = app.buttons["Search"]
            if searchButton.exists {
                searchButton.tap()
                
                screenshotHelper.takeScreenshot(
                    name: "furniture_search_results",
                    description: "Furniture search results display"
                )
            }
        }
    }
    
    // MARK: - AR Placement Screenshots
    
    func testARPlacementScreenshots() throws {
        // Navigate to placement mode
        navigateToFurnitureCatalog()
        
        let firstItem = app.cells.firstMatch
        if firstItem.exists {
            firstItem.tap()
            
            let placeButton = app.buttons["Place in AR"]
            if placeButton.waitForExistence(timeout: 3.0) {
                placeButton.tap()
                
                // AR placement interface
                let arView = app.otherElements["ARView"]
                if arView.waitForExistence(timeout: 3.0) {
                    screenshotHelper.takeScreenshot(
                        name: "ar_placement_mode",
                        description: "AR placement mode with furniture preview"
                    )
                    
                    testPlacementControlsScreenshots()
                    testManipulationScreenshots()
                }
            }
        }
    }
    
    private func testPlacementControlsScreenshots() {
        let placementControls = app.otherElements["PlacementControls"]
        if placementControls.exists {
            screenshotHelper.takeScreenshot(
                name: "placement_controls",
                description: "Furniture placement controls and options"
            )
        }
        
        let snapButton = app.buttons["Snap to Surface"]
        if snapButton.exists {
            snapButton.tap()
            screenshotHelper.takeScreenshot(
                name: "snap_mode_active",
                description: "Snap to surface mode with visual indicators"
            )
        }
    }
    
    private func testManipulationScreenshots() {
        let manipulationControls = app.otherElements["ManipulationControls"]
        if manipulationControls.exists {
            
            let rotateButton = app.buttons["Rotate"]
            if rotateButton.exists {
                rotateButton.tap()
                screenshotHelper.takeScreenshot(
                    name: "rotate_mode",
                    description: "Furniture rotation mode with controls"
                )
            }
            
            let scaleButton = app.buttons["Scale"]
            if scaleButton.exists {
                scaleButton.tap()
                screenshotHelper.takeScreenshot(
                    name: "scale_mode",
                    description: "Furniture scaling mode with handles"
                )
            }
        }
    }
    
    // MARK: - Measurement Screenshots
    
    func testMeasurementScreenshots() throws {
        let measureButton = app.buttons["Measurement Tools"]
        if measureButton.exists {
            measureButton.tap()
            
            let measurementView = app.otherElements["MeasurementToolsView"]
            if measurementView.waitForExistence(timeout: 3.0) {
                screenshotHelper.takeScreenshot(
                    name: "measurement_tools",
                    description: "Measurement tools interface"
                )
                
                testMeasurementModesScreenshots()
            }
        }
    }
    
    private func testMeasurementModesScreenshots() {
        let measurementModes = ["Distance", "Area", "Volume", "Angle"]
        
        for mode in measurementModes {
            let modeButton = app.buttons[mode]
            if modeButton.exists {
                modeButton.tap()
                
                screenshotHelper.takeScreenshot(
                    name: "measurement_\(mode.lowercased())",
                    description: "\(mode) measurement mode interface"
                )
            }
        }
    }
    
    // MARK: - Settings Screenshots
    
    func testSettingsScreenshots() throws {
        let settingsButton = app.buttons["Settings"]
        if settingsButton.exists {
            settingsButton.tap()
            
            let settingsView = app.otherElements["SettingsView"]
            if settingsView.waitForExistence(timeout: 3.0) {
                screenshotHelper.takeScreenshot(
                    name: "settings_main",
                    description: "Main settings interface"
                )
                
                testSettingsSectionsScreenshots()
            }
        }
    }
    
    private func testSettingsSectionsScreenshots() {
        let sections = ["AR Settings", "Display", "Performance", "Accessibility"]
        
        for section in sections {
            let sectionCell = app.cells[section]
            if sectionCell.exists {
                sectionCell.tap()
                
                screenshotHelper.takeScreenshot(
                    name: "settings_\(section.lowercased().replacingOccurrences(of: " ", with: "_"))",
                    description: "\(section) settings page"
                )
                
                // Go back
                let backButton = app.navigationBars.buttons.firstMatch
                if backButton.exists {
                    backButton.tap()
                }
            }
        }
    }
    
    // MARK: - Error States Screenshots
    
    func testErrorStateScreenshots() throws {
        // This would test various error states
        // In a real implementation, you might trigger errors programmatically
        
        // AR permission denied state
        testARPermissionDeniedScreenshot()
        
        // Network error state
        testNetworkErrorScreenshot()
        
        // Scanning failed state
        testScanningErrorScreenshot()
    }
    
    private func testARPermissionDeniedScreenshot() {
        // If AR permission is denied, capture that state
        let permissionAlert = app.alerts.firstMatch
        if permissionAlert.exists {
            screenshotHelper.takeScreenshot(
                name: "ar_permission_denied",
                description: "AR permission denied alert"
            )
        }
    }
    
    private func testNetworkErrorScreenshot() {
        // Test network error states if they occur
        let errorView = app.otherElements["NetworkErrorView"]
        if errorView.exists {
            screenshotHelper.takeScreenshot(
                name: "network_error",
                description: "Network connection error state"
            )
        }
    }
    
    private func testScanningErrorScreenshot() {
        // Test scanning error states
        let scanErrorView = app.otherElements["ScanErrorView"]
        if scanErrorView.exists {
            screenshotHelper.takeScreenshot(
                name: "scanning_error",
                description: "Room scanning error state"
            )
        }
    }
    
    // MARK: - Accessibility Screenshots
    
    func testAccessibilityScreenshots() throws {
        // Enable accessibility features for screenshots
        app.launchArguments.append("--accessibility-mode")
        
        // Take screenshots with accessibility overlays
        screenshotHelper.takeScreenshot(
            name: "accessibility_main",
            description: "Main interface with accessibility features"
        )
        
        // VoiceOver mode
        testVoiceOverScreenshots()
    }
    
    private func testVoiceOverScreenshots() {
        // Screenshots showing VoiceOver interactions
        if UIAccessibility.isVoiceOverRunning {
            screenshotHelper.takeScreenshot(
                name: "voiceover_active",
                description: "Interface with VoiceOver navigation active"
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func navigateToRoomScanning() {
        let scanButton = app.buttons["Start Room Scan"]
        if scanButton.exists {
            scanButton.tap()
        }
    }
    
    private func navigateToFurnitureCatalog() {
        let catalogButton = app.buttons["Furniture Catalog"]
        if catalogButton.exists {
            catalogButton.tap()
        }
    }
}

// MARK: - Screenshot Helper

class ScreenshotHelper {
    private var screenshotCount = 0
    private let dateFormatter: DateFormatter
    
    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    }
    
    func takeScreenshot(name: String, description: String) {
        screenshotCount += 1
        
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        
        let timestamp = dateFormatter.string(from: Date())
        attachment.name = "\(screenshotCount)_\(name)_\(timestamp)"
        attachment.lifetime = .keepAlways
        
        // Add description as metadata
        attachment.userInfo = [
            "description": description,
            "timestamp": timestamp,
            "test_name": name
        ]
        
        // Attach to test
        XCTContext.runActivity(named: "Screenshot: \(name)") { activity in
            activity.add(attachment)
        }
        
        print("📸 Screenshot captured: \(name) - \(description)")
    }
    
    func takeScreenshotWithDelay(name: String, description: String, delay: TimeInterval = 1.0) {
        Thread.sleep(forTimeInterval: delay)
        takeScreenshot(name: name, description: description)
    }
}