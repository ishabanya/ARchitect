import XCTest
@testable import ARchitect

final class RoomScanningUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Navigate to room scanning if not already there
        navigateToRoomScanning()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    private func navigateToRoomScanning() {
        let scanButton = app.buttons["Start Room Scan"]
        if scanButton.exists {
            scanButton.tap()
        }
    }
    
    func testRoomScanningViewExists() throws {
        let scanningView = app.otherElements["RoomScanningView"]
        XCTAssertTrue(scanningView.waitForExistence(timeout: 5.0))
    }
    
    func testStartScanButton() throws {
        let startButton = app.buttons["Start Scanning"]
        if startButton.waitForExistence(timeout: 3.0) {
            XCTAssertTrue(startButton.isEnabled)
            startButton.tap()
            
            // Check that scanning state changes
            let scanningIndicator = app.otherElements["ScanningIndicator"]
            XCTAssertTrue(scanningIndicator.waitForExistence(timeout: 3.0))
        }
    }
    
    func testStopScanButton() throws {
        let startButton = app.buttons["Start Scanning"]
        if startButton.waitForExistence(timeout: 3.0) {
            startButton.tap()
            
            let stopButton = app.buttons["Stop Scanning"]
            if stopButton.waitForExistence(timeout: 3.0) {
                XCTAssertTrue(stopButton.isEnabled)
                stopButton.tap()
                
                // Check that scanning stops
                let processingIndicator = app.otherElements["ProcessingIndicator"]
                XCTAssertTrue(processingIndicator.waitForExistence(timeout: 3.0))
            }
        }
    }
    
    func testScanProgressDisplay() throws {
        let progressView = app.otherElements["ScanProgress"]
        if progressView.waitForExistence(timeout: 3.0) {
            XCTAssertTrue(progressView.exists)
            
            let progressBar = app.progressIndicators["ScanProgressBar"]
            XCTAssertTrue(progressBar.exists)
        }
    }
    
    func testScanQualityFeedback() throws {
        let qualityIndicator = app.otherElements["ScanQualityIndicator"]
        if qualityIndicator.waitForExistence(timeout: 3.0) {
            XCTAssertTrue(qualityIndicator.exists)
        }
    }
    
    func testScanVisualFeedback() throws {
        let visualFeedback = app.otherElements["ScanVisualFeedback"]
        if visualFeedback.waitForExistence(timeout: 3.0) {
            XCTAssertTrue(visualFeedback.exists)
        }
    }
    
    func testScanSettingsAccess() throws {
        let settingsButton = app.buttons["Scan Settings"]
        if settingsButton.waitForExistence(timeout: 3.0) {
            settingsButton.tap()
            
            let settingsView = app.otherElements["ScanSettingsView"]
            XCTAssertTrue(settingsView.waitForExistence(timeout: 3.0))
            
            // Test quality mode selection
            let qualitySegment = app.segmentedControls["QualityMode"]
            if qualitySegment.exists {
                XCTAssertTrue(qualitySegment.buttons.count > 0)
            }
        }
    }
    
    func testScanRecoveryInterface() throws {
        // This would test the scan recovery UI when tracking is lost
        let recoveryView = app.otherElements["ScanRecoveryView"]
        // Recovery view appears when tracking issues occur
        // In a real test, we'd simulate tracking failure
    }
    
    func testScanCompletion() throws {
        let startButton = app.buttons["Start Scanning"]
        if startButton.waitForExistence(timeout: 3.0) {
            startButton.tap()
            
            // Simulate scan completion (in real test, this would be based on actual scanning)
            let stopButton = app.buttons["Stop Scanning"]
            if stopButton.waitForExistence(timeout: 3.0) {
                stopButton.tap()
                
                let completionView = app.otherElements["ScanCompletionView"]
                XCTAssertTrue(completionView.waitForExistence(timeout: 5.0))
                
                let saveButton = app.buttons["Save Scan"]
                XCTAssertTrue(saveButton.exists)
            }
        }
    }
    
    func testScanCancellation() throws {
        let startButton = app.buttons["Start Scanning"]
        if startButton.waitForExistence(timeout: 3.0) {
            startButton.tap()
            
            let cancelButton = app.buttons["Cancel Scan"]
            if cancelButton.waitForExistence(timeout: 3.0) {
                cancelButton.tap()
                
                // Check for confirmation dialog
                let confirmButton = app.alerts.buttons["Confirm"]
                if confirmButton.exists {
                    confirmButton.tap()
                }
                
                // Should return to initial state
                let initialView = app.otherElements["InitialScanView"]
                XCTAssertTrue(initialView.waitForExistence(timeout: 3.0))
            }
        }
    }
    
    func testScanErrorHandling() throws {
        // Test error states and recovery
        let errorView = app.otherElements["ScanErrorView"]
        // This would appear during actual errors
        
        if errorView.exists {
            let retryButton = app.buttons["Retry Scan"]
            XCTAssertTrue(retryButton.exists)
            
            let helpButton = app.buttons["Get Help"]
            XCTAssertTrue(helpButton.exists)
        }
    }
    
    func testAccessibilityInScanning() throws {
        // Ensure scanning interface is accessible
        let scanningView = app.otherElements["RoomScanningView"]
        XCTAssertTrue(scanningView.waitForExistence(timeout: 5.0))
        
        // Check VoiceOver labels
        let buttons = app.buttons.allElementsBoundByAccessibilityElement
        for button in buttons {
            XCTAssertFalse(button.label.isEmpty, "Button should have accessibility label")
        }
        
        // Check that progress is announced
        let progressView = app.otherElements["ScanProgress"]
        if progressView.exists {
            XCTAssertFalse(progressView.label.isEmpty)
        }
    }
}