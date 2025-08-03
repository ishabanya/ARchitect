import XCTest
import ARKit
import RealityKit
import Combine
@testable import ARchitect

final class RoomScannerTests: XCTestCase {
    
    var mockSessionManager: MockARSessionManager!
    var roomScanner: RoomScanner!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        mockSessionManager = MockARSessionManager()
        roomScanner = RoomScanner(sessionManager: mockSessionManager)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        roomScanner = nil
        mockSessionManager = nil
    }
    
    func testRoomScannerInitialization() {
        XCTAssertEqual(roomScanner.scanState, .notStarted)
        XCTAssertFalse(roomScanner.isScanning)
        XCTAssertTrue(roomScanner.detectedPlanes.isEmpty)
        XCTAssertTrue(roomScanner.mergedPlanes.isEmpty)
        XCTAssertNil(roomScanner.roomDimensions)
        XCTAssertNil(roomScanner.scanQuality)
        XCTAssertTrue(roomScanner.scanIssues.isEmpty)
    }
    
    func testStartScanning() {
        let expectation = XCTestExpectation(description: "Scanning starts")
        
        roomScanner.$scanState
            .dropFirst()
            .sink { state in
                if state == .initializing {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        roomScanner.startScanning(roomName: "Test Room")
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertTrue(roomScanner.isScanning)
        XCTAssertEqual(roomScanner.scanState, .initializing)
    }
    
    func testScanProgressInitialization() {
        roomScanner.startScanning()
        
        XCTAssertEqual(roomScanner.scanProgress.currentPhase, .floorDetection)
        XCTAssertEqual(roomScanner.scanProgress.completionPercentage, 0.0)
        XCTAssertEqual(roomScanner.scanProgress.detectedPlanes, 0)
        XCTAssertEqual(roomScanner.scanProgress.floorCoverage, 0.0)
        XCTAssertEqual(roomScanner.scanProgress.wallCoverage, 0.0)
    }
    
    func testStopScanning() {
        roomScanner.startScanning()
        XCTAssertTrue(roomScanner.isScanning)
        
        let expectation = XCTestExpectation(description: "Scanning stops")
        
        roomScanner.$scanState
            .dropFirst(2) // Skip initial and initializing states
            .sink { state in
                if state == .processing {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        roomScanner.stopScanning()
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertFalse(roomScanner.isScanning)
        XCTAssertEqual(roomScanner.scanState, .processing)
    }
    
    func testCancelScanning() {
        roomScanner.startScanning()
        XCTAssertTrue(roomScanner.isScanning)
        
        roomScanner.cancelScanning()
        
        XCTAssertFalse(roomScanner.isScanning)
        XCTAssertEqual(roomScanner.scanState, .cancelled)
        XCTAssertTrue(roomScanner.detectedPlanes.isEmpty)
        XCTAssertTrue(roomScanner.mergedPlanes.isEmpty)
    }
    
    func testGetCurrentScanWithoutData() {
        let scan = roomScanner.getCurrentScan(name: "Test")
        XCTAssertNil(scan)
    }
    
    func testScanStateTransitions() {
        let expectation = XCTestExpectation(description: "State transitions")
        expectation.expectedFulfillmentCount = 3
        
        var stateChanges: [ScanState] = []
        
        roomScanner.$scanState
            .sink { state in
                stateChanges.append(state)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        roomScanner.startScanning()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.roomScanner.stopScanning()
        }
        
        wait(for: [expectation], timeout: 3.0)
        
        XCTAssertTrue(stateChanges.contains(.notStarted))
        XCTAssertTrue(stateChanges.contains(.initializing))
        XCTAssertTrue(stateChanges.contains(.processing))
    }
    
    func testDoubleStartPrevention() {
        roomScanner.startScanning()
        XCTAssertTrue(roomScanner.isScanning)
        
        // Try to start again
        roomScanner.startScanning()
        
        // Should still be scanning (no change)
        XCTAssertTrue(roomScanner.isScanning)
    }
    
    func testProgressPhaseDetection() {
        // Test floor detection phase
        XCTAssertEqual(roomScanner.scanProgress.currentPhase, .floorDetection)
        
        // Test scan without sufficient data
        let scan = roomScanner.getCurrentScan(name: "Test")
        XCTAssertNil(scan)
    }
}

// MARK: - Mock Classes

class MockARSessionManager: ARSessionManager {
    @Published var mockSessionState: ARSessionState = .running
    @Published var mockTrackingQuality: ARTrackingQuality = .normal
    @Published var mockDetectedPlanes: [ARPlaneAnchor] = []
    
    override var sessionState: ARSessionState {
        return mockSessionState
    }
    
    override var trackingQuality: ARTrackingQuality {
        return mockTrackingQuality
    }
    
    override var detectedPlanes: [ARPlaneAnchor] {
        return mockDetectedPlanes
    }
    
    func simulateSessionStateChange(_ state: ARSessionState) {
        mockSessionState = state
    }
    
    func simulateTrackingQualityChange(_ quality: ARTrackingQuality) {
        mockTrackingQuality = quality
    }
    
    func simulatePlaneDetection(_ planes: [ARPlaneAnchor]) {
        mockDetectedPlanes = planes
    }
}

// MARK: - ARTrackingQuality Extension for Testing

extension ARTrackingQuality {
    var score: Float {
        switch self {
        case .notAvailable:
            return 0.0
        case .limited(_):
            return 0.3
        case .normal:
            return 0.8
        @unknown default:
            return 0.0
        }
    }
}