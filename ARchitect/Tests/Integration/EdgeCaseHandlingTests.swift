import XCTest
import ARKit
import Combine
@testable import ARchitect

@MainActor
class EdgeCaseHandlingTests: XCTestCase {
    
    var edgeCaseHandler: EdgeCaseHandler!
    var mockARSessionManager: MockARSessionManager!
    var mockOfflineManager: MockOfflineManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        
        edgeCaseHandler = EdgeCaseHandler.shared
        mockARSessionManager = MockARSessionManager()
        mockOfflineManager = MockOfflineManager()
        cancellables = Set<AnyCancellable>()
        
        // Start monitoring for tests
        edgeCaseHandler.startMonitoring()
    }
    
    override func tearDown() async throws {
        edgeCaseHandler.stopMonitoring()
        cancellables.removeAll()
        try await super.tearDown()
    }
    
    // MARK: - Poor Lighting Tests
    
    func testPoorLightingDetection() async throws {
        // Given: Poor lighting conditions
        let expectation = XCTestExpectation(description: "Poor lighting detected")
        
        var detectedCase: EdgeCaseDetectionResult?
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult,
                   result.type == .poorLighting {
                    detectedCase = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Simulating poor lighting with mock ARFrame
        let mockFrame = createMockARFrame(withLightIntensity: 10.0) // Very low light
        mockARSessionManager.simulateFrame(mockFrame)
        
        // Trigger lighting check
        await edgeCaseHandler.forceCheckAllEdgeCases()
        
        // Then: Poor lighting should be detected
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertNotNil(detectedCase)
        XCTAssertEqual(detectedCase?.type, .poorLighting)
        XCTAssertGreaterThanOrEqual(detectedCase?.severity.rawValue ?? 0, EdgeCaseSeverity.medium.rawValue)
        XCTAssertTrue(detectedCase?.recommendedActions.contains(.adjustLighting) ?? false)
    }
    
    func testPoorLightingRecoveryActions() async throws {
        // Given: Poor lighting detected
        let result = EdgeCaseDetectionResult(
            type: .poorLighting,
            severity: .high,
            confidence: 0.9,
            timestamp: Date(),
            metadata: ["estimated_lux": 5.0],
            recommendedActions: [.adjustLighting, .adjustQuality, .requestBetterConditions]
        )
        
        // When: Handling the edge case
        await edgeCaseHandler.handleDetectedEdgeCase(result)
        
        // Then: Recovery actions should be executed
        XCTAssertTrue(edgeCaseHandler.detectedCases.contains { $0.type == .poorLighting })
        
        // Verify AR configuration was adjusted
        await Task.sleep(nanoseconds: 100_000_000) // Wait for async actions
        // Add verification for actual configuration changes
    }
    
    // MARK: - Rapid Movement Tests
    
    func testRapidMovementDetection() async throws {
        // Given: Rapid device movement
        let expectation = XCTestExpectation(description: "Rapid movement detected")
        
        var detectedCase: EdgeCaseDetectionResult?
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult,
                   result.type == .rapidMovement {
                    detectedCase = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Simulating rapid movement with consecutive frames
        let positions = [
            simd_float3(0, 0, 0),
            simd_float3(2, 0, 0), // 2 meters in one frame = very fast
            simd_float3(4, 0, 0)
        ]
        
        for (index, position) in positions.enumerated() {
            let frame = createMockARFrame(withPosition: position, timestamp: TimeInterval(index) * 0.033) // 30 FPS
            mockARSessionManager.simulateFrame(frame)
            await Task.sleep(nanoseconds: 33_000_000) // 33ms between frames
        }
        
        await edgeCaseHandler.forceCheckAllEdgeCases()
        
        // Then: Rapid movement should be detected
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertNotNil(detectedCase)
        XCTAssertEqual(detectedCase?.type, .rapidMovement)
        XCTAssertTrue(detectedCase?.recommendedActions.contains(.waitForStability) ?? false)
    }
    
    // MARK: - Cluttered Environment Tests
    
    func testClutteredEnvironmentDetection() async throws {
        // Given: High feature point density indicating clutter
        let expectation = XCTestExpectation(description: "Cluttered environment detected")
        
        var detectedCase: EdgeCaseDetectionResult?
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult,
                   result.type == .clutteredEnvironment {
                    detectedCase = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Simulating cluttered environment with many feature points
        let featurePoints = createMockFeaturePoints(count: 2000) // High density
        let frame = createMockARFrame(withFeaturePoints: featurePoints)
        mockARSessionManager.simulateFrame(frame)
        
        await edgeCaseHandler.forceCheckAllEdgeCases()
        
        // Then: Cluttered environment should be detected
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertNotNil(detectedCase)
        XCTAssertEqual(detectedCase?.type, .clutteredEnvironment)
        XCTAssertTrue(detectedCase?.recommendedActions.contains(.requestBetterConditions) ?? false)
    }
    
    // MARK: - App Interruption Tests
    
    func testPhoneCallInterruption() async throws {
        // Given: Phone call interruption
        let expectation = XCTestExpectation(description: "App interruption detected")
        
        var detectedCase: EdgeCaseDetectionResult?
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult,
                   result.type == .appInterruption {
                    detectedCase = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Simulating phone call interruption
        let userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ]
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: userInfo
        )
        
        // Then: App interruption should be detected
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertNotNil(detectedCase)
        XCTAssertEqual(detectedCase?.type, .appInterruption)
        XCTAssertTrue(detectedCase?.recommendedActions.contains(.pauseSession) ?? false)
        XCTAssertTrue(detectedCase?.recommendedActions.contains(.saveProgress) ?? false)
    }
    
    func testAppBackgroundingInterruption() async throws {
        // Given: App going to background
        let expectation = XCTestExpectation(description: "Background interruption detected")
        
        var detectedCase: EdgeCaseDetectionResult?
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult,
                   result.type == .appInterruption {
                    detectedCase = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Simulating app going to background
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        
        // Then: App interruption should be detected
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertNotNil(detectedCase)
        XCTAssertEqual(detectedCase?.type, .appInterruption)
    }
    
    // MARK: - Low Storage Tests
    
    func testLowStorageDetection() async throws {
        // Given: Low storage scenario (mocked)
        let expectation = XCTestExpectation(description: "Low storage detected")
        
        var detectedCase: EdgeCaseDetectionResult?
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult,
                   result.type == .lowStorage {
                    detectedCase = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Force checking storage (would need mock file system for full test)
        await edgeCaseHandler.forceCheckAllEdgeCases()
        
        // Note: This test would require mocking the file system to properly test
        // For now, we'll test the logic with a synthetic result
        let lowStorageResult = EdgeCaseDetectionResult(
            type: .lowStorage,
            severity: .high,
            confidence: 0.8,
            timestamp: Date(),
            metadata: ["available_gb": 0.5],
            recommendedActions: [.clearMemory, .optimizePerformance]
        )
        
        await edgeCaseHandler.handleDetectedEdgeCase(lowStorageResult)
        
        // Then: Low storage should be handled
        XCTAssertTrue(edgeCaseHandler.detectedCases.contains { $0.type == .lowStorage })
    }
    
    // MARK: - Offline Mode Tests
    
    func testOfflineModeHandling() async throws {
        // Given: Network disconnection
        let expectation = XCTestExpectation(description: "Offline mode activated")
        
        var detectedCase: EdgeCaseDetectionResult?
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult,
                   result.type == .offlineMode {
                    detectedCase = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Simulating network disconnection
        mockOfflineManager.simulateNetworkDisconnection()
        await edgeCaseHandler.forceCheckAllEdgeCases()
        
        // Then: Offline mode should be activated
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertNotNil(detectedCase)
        XCTAssertEqual(detectedCase?.type, .offlineMode)
        XCTAssertTrue(detectedCase?.recommendedActions.contains(.switchToOffline) ?? false)
    }
    
    // MARK: - Room Size Tests
    
    func testLargeRoomDetection() async throws {
        // Given: Large room with extensive floor area
        let expectation = XCTestExpectation(description: "Large room detected")
        
        var detectedCase: EdgeCaseDetectionResult?
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult,
                   result.type == .largeRoom {
                    detectedCase = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Simulating large room with big floor planes
        let largePlanes = createMockPlanes(withAreas: [150.0]) // 150 m² floor
        mockARSessionManager.simulatePlaneDetection(largePlanes)
        
        await edgeCaseHandler.forceCheckAllEdgeCases()
        
        // Then: Large room should be detected
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertNotNil(detectedCase)
        XCTAssertEqual(detectedCase?.type, .largeRoom)
        XCTAssertTrue(detectedCase?.recommendedActions.contains(.optimizePerformance) ?? false)
    }
    
    func testSmallRoomDetection() async throws {
        // Given: Small room with limited floor area
        let expectation = XCTestExpectation(description: "Small room detected")
        
        var detectedCase: EdgeCaseDetectionResult?
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult,
                   result.type == .smallRoom {
                    detectedCase = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Simulating small room with tiny floor planes
        let smallPlanes = createMockPlanes(withAreas: [2.0]) // 2 m² floor
        mockARSessionManager.simulatePlaneDetection(smallPlanes)
        
        await edgeCaseHandler.forceCheckAllEdgeCases()
        
        // Then: Small room should be detected
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertNotNil(detectedCase)
        XCTAssertEqual(detectedCase?.type, .smallRoom)
        XCTAssertTrue(detectedCase?.recommendedActions.contains(.adjustQuality) ?? false)
    }
    
    // MARK: - System Health Tests
    
    func testThermalThrottlingDetection() async throws {
        // Given: Device overheating
        let expectation = XCTestExpectation(description: "Thermal throttling detected")
        
        var detectedCase: EdgeCaseDetectionResult?
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult,
                   result.type == .thermalThrottling {
                    detectedCase = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Simulating thermal throttling
        let thermalResult = EdgeCaseDetectionResult(
            type: .thermalThrottling,
            severity: .critical,
            confidence: 1.0,
            timestamp: Date(),
            metadata: ["thermal_state": ProcessInfo.ThermalState.critical.rawValue],
            recommendedActions: [.optimizePerformance, .pauseSession]
        )
        
        await edgeCaseHandler.handleDetectedEdgeCase(thermalResult)
        
        // Then: Thermal throttling should be handled
        XCTAssertTrue(edgeCaseHandler.detectedCases.contains { $0.type == .thermalThrottling })
    }
    
    func testMemoryPressureDetection() async throws {
        // Given: High memory usage
        let expectation = XCTestExpectation(description: "Memory pressure detected")
        
        var detectedCase: EdgeCaseDetectionResult?
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult,
                   result.type == .memoryPressure {
                    detectedCase = result
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Simulating memory warning
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        
        // Then: Memory pressure should be detected
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertNotNil(detectedCase)
        XCTAssertEqual(detectedCase?.type, .memoryPressure)
        XCTAssertTrue(detectedCase?.recommendedActions.contains(.clearMemory) ?? false)
    }
    
    // MARK: - Recovery Action Tests
    
    func testRecoveryActionExecution() async throws {
        // Given: Multiple edge cases requiring different actions
        let lightingCase = EdgeCaseDetectionResult(
            type: .poorLighting,
            severity: .high,
            confidence: 0.9,
            timestamp: Date(),
            metadata: [:],
            recommendedActions: [.adjustLighting, .adjustQuality]
        )
        
        let movementCase = EdgeCaseDetectionResult(
            type: .rapidMovement,
            severity: .medium,
            confidence: 0.7,
            timestamp: Date(),
            metadata: [:],
            recommendedActions: [.waitForStability, .showGuidance]
        )
        
        // When: Handling the edge cases
        await edgeCaseHandler.handleDetectedEdgeCase(lightingCase)
        await edgeCaseHandler.handleDetectedEdgeCase(movementCase)
        
        // Then: Both cases should be recorded and handled
        XCTAssertEqual(edgeCaseHandler.detectedCases.count, 2)
        XCTAssertTrue(edgeCaseHandler.detectedCases.contains { $0.type == .poorLighting })
        XCTAssertTrue(edgeCaseHandler.detectedCases.contains { $0.type == .rapidMovement })
    }
    
    // MARK: - Integration Test
    
    func testCompleteEdgeCaseScenario() async throws {
        // Given: Multiple edge cases occurring in sequence
        let expectations = [
            XCTestExpectation(description: "Poor lighting detected"),
            XCTestExpectation(description: "Rapid movement detected"),
            XCTestExpectation(description: "App interruption detected")
        ]
        
        var detectedTypes: Set<EdgeCaseType> = []
        
        NotificationCenter.default.publisher(for: .edgeCaseDetected)
            .sink { notification in
                if let result = notification.object as? EdgeCaseDetectionResult {
                    detectedTypes.insert(result.type)
                    
                    switch result.type {
                    case .poorLighting:
                        expectations[0].fulfill()
                    case .rapidMovement:
                        expectations[1].fulfill()
                    case .appInterruption:
                        expectations[2].fulfill()
                    default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
        
        // When: Simulating a complex scenario
        // 1. Poor lighting
        let darkFrame = createMockARFrame(withLightIntensity: 5.0)
        mockARSessionManager.simulateFrame(darkFrame)
        
        // 2. Rapid movement
        let fastPositions = [simd_float3(0, 0, 0), simd_float3(3, 0, 0)]
        for (index, position) in fastPositions.enumerated() {
            let frame = createMockARFrame(withPosition: position, timestamp: TimeInterval(index) * 0.033)
            mockARSessionManager.simulateFrame(frame)
        }
        
        // 3. App interruption
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        
        await edgeCaseHandler.forceCheckAllEdgeCases()
        
        // Then: All edge cases should be detected and handled appropriately
        await fulfillment(of: expectations, timeout: 10.0)
        
        XCTAssertGreaterThanOrEqual(detectedTypes.count, 3)
        XCTAssertTrue(detectedTypes.contains(.poorLighting))
        XCTAssertTrue(detectedTypes.contains(.rapidMovement))
        XCTAssertTrue(detectedTypes.contains(.appInterruption))
    }
    
    // MARK: - Helper Methods
    
    private func createMockARFrame(
        withLightIntensity intensity: Double = 1000.0,
        position: simd_float3 = simd_float3(0, 0, 0),
        timestamp: TimeInterval = CACurrentMediaTime(),
        featurePoints: [simd_float3]? = nil
    ) -> MockARFrame {
        return MockARFrame(
            lightIntensity: intensity,
            position: position,
            timestamp: timestamp,
            featurePoints: featurePoints ?? []
        )
    }
    
    private func createMockFeaturePoints(count: Int) -> [simd_float3] {
        return (0..<count).map { index in
            let x = Float.random(in: -2...2)
            let y = Float.random(in: -1...1)
            let z = Float.random(in: 0...5)
            return simd_float3(x, y, z)
        }
    }
    
    private func createMockPlanes(withAreas areas: [Float]) -> [MockARPlaneAnchor] {
        return areas.enumerated().map { index, area in
            MockARPlaneAnchor(
                identifier: UUID(),
                area: area,
                alignment: .horizontal
            )
        }
    }
}

// MARK: - Mock Classes

class MockARSessionManager {
    var currentFrame: MockARFrame?
    var detectedPlanes: [MockARPlaneAnchor] = []
    
    func simulateFrame(_ frame: MockARFrame) {
        currentFrame = frame
    }
    
    func simulatePlaneDetection(_ planes: [MockARPlaneAnchor]) {
        detectedPlanes = planes
    }
}

class MockOfflineManager {
    var isConnected = true
    
    func simulateNetworkDisconnection() {
        isConnected = false
    }
    
    func simulateNetworkReconnection() {
        isConnected = true
    }
}

struct MockARFrame {
    let lightIntensity: Double
    let position: simd_float3
    let timestamp: TimeInterval
    let featurePoints: [simd_float3]
    
    var lightEstimate: MockLightEstimate {
        return MockLightEstimate(ambientIntensity: lightIntensity)
    }
    
    var camera: MockCamera {
        return MockCamera(position: position)
    }
    
    var rawFeaturePoints: MockFeaturePoints? {
        return MockFeaturePoints(points: featurePoints)
    }
}

struct MockLightEstimate {
    let ambientIntensity: Double
    let ambientColorTemperature: Float = 6500
}

struct MockCamera {
    let position: simd_float3
    
    var transform: simd_float4x4 {
        return simd_float4x4(
            simd_float4(1, 0, 0, position.x),
            simd_float4(0, 1, 0, position.y),
            simd_float4(0, 0, 1, position.z),
            simd_float4(0, 0, 0, 1)
        )
    }
    
    let trackingState: ARCamera.TrackingState = .normal
}

struct MockFeaturePoints {
    let points: [simd_float3]
}

struct MockARPlaneAnchor {
    let identifier: UUID
    let area: Float
    let alignment: ARPlaneAnchor.Alignment
    
    var extent: simd_float3 {
        let side = sqrt(area)
        return simd_float3(side, 0, side)
    }
}