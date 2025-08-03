import Foundation
import XCTest
import RealityKit
import ARKit
@testable import ARchitect

// MARK: - Test Configuration

struct TestConfiguration {
    static let shared = TestConfiguration()
    
    // Test timeouts
    let defaultTimeout: TimeInterval = 10.0
    let longTimeout: TimeInterval = 30.0
    let shortTimeout: TimeInterval = 3.0
    
    // Performance thresholds
    let maxFrameTime: TimeInterval = 0.016 // 60 FPS
    let maxMemoryGrowth: Int = 100 * 1024 * 1024 // 100MB
    let maxTestDuration: TimeInterval = 60.0 // 1 minute
    
    // AR test settings
    let testARViewSize = CGSize(width: 375, height: 812)
    let testEntityCount = 10
    let stressTestEntityCount = 100
    
    // Mock data settings
    let mockScanDuration: TimeInterval = 30.0
    let mockPlaneCount = 5
    let mockFurnitureCount = 20
    
    private init() {}
}

// MARK: - Test Utilities

class TestUtilities {
    
    // MARK: - Entity Creation
    
    static func createTestEntity(id: Int = 0, size: Float = 0.1) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: size)
        let material = SimpleMaterial(color: .systemBlue, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "TestEntity_\(id)"
        return entity
    }
    
    static func createTestEntities(count: Int, size: Float = 0.1) -> [ModelEntity] {
        return (0..<count).map { createTestEntity(id: $0, size: size) }
    }
    
    static func createComplexEntity(id: Int = 0) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: 0.15)
        
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = UIColor.random()
        material.metallic = 0.5
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.3)
        
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "ComplexEntity_\(id)"
        entity.components.set(GroundingShadowComponent(castsShadow: true))
        
        return entity
    }
    
    // MARK: - Mock Data Creation
    
    static func createMockFurnitureItems(count: Int) -> [FurnitureItem] {
        return (0..<count).map { i in
            FurnitureItem(
                name: "Test Furniture \(i)",
                category: FurnitureCategory.allCases.randomElement() ?? .chair,
                dimensions: FurnitureDimensions(
                    width: Float.random(in: 0.5...2.0),
                    height: Float.random(in: 0.5...2.0),
                    depth: Float.random(in: 0.5...2.0)
                ),
                modelResource: "test_model_\(i).usd"
            )
        }
    }
    
    static func createMockARPlanes(count: Int) -> [ARPlaneAnchor] {
        return (0..<count).map { i in
            let transform = simd_float4x4(
                simd_float4(1, 0, 0, 0),
                simd_float4(0, 1, 0, 0),
                simd_float4(0, 0, 1, 0),
                simd_float4(Float(i), 0, 0, 1)
            )
            
            return ARPlaneAnchor(
                identifier: UUID(),
                transform: transform,
                alignment: i % 2 == 0 ? .horizontal : .vertical,
                center: simd_float3(0, 0, 0),
                extent: simd_float3(
                    Float.random(in: 1.0...3.0),
                    0,
                    Float.random(in: 1.0...3.0)
                )
            )
        }
    }
    
    // MARK: - Memory Testing
    
    static func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
    
    static func forceGarbageCollection() async {
        for _ in 0..<10 {
            autoreleasepool {
                _ = Array(0..<1000).map { _ in NSObject() }
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }
    
    // MARK: - Performance Testing
    
    static func measureExecutionTime<T>(operation: () throws -> T) rethrows -> (result: T, time: TimeInterval) {
        let startTime = CACurrentMediaTime()
        let result = try operation()
        let endTime = CACurrentMediaTime()
        return (result, endTime - startTime)
    }
    
    static func measureAsyncExecutionTime<T>(operation: () async throws -> T) async rethrows -> (result: T, time: TimeInterval) {
        let startTime = CACurrentMediaTime()
        let result = try await operation()
        let endTime = CACurrentMediaTime()
        return (result, endTime - startTime)
    }
    
    // MARK: - File System Testing
    
    static func createTemporaryDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("ARchitectTests_\(UUID().uuidString)")
        
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir
    }
    
    static func cleanupTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Assertion Helpers
    
    static func assertMemoryGrowthWithinLimit(
        initial: Int,
        final: Int,
        limit: Int,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let growth = final - initial
        XCTAssertLessThan(growth, limit, 
                         "Memory grew by \(growth / 1024 / 1024)MB, limit is \(limit / 1024 / 1024)MB",
                         file: file, line: line)
    }
    
    static func assertExecutionTimeWithinLimit(
        _ time: TimeInterval,
        limit: TimeInterval,
        operation: String = "Operation",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertLessThan(time, limit,
                         "\(operation) took \(time)s, limit is \(limit)s",
                         file: file, line: line)
    }
}

// MARK: - Test Base Classes

class ARchitectTestCase: XCTestCase {
    var arView: ARView!
    var initialMemory: Int = 0
    
    override func setUp() async throws {
        await TestUtilities.forceGarbageCollection()
        initialMemory = TestUtilities.getCurrentMemoryUsage()
        
        arView = ARView(frame: CGRect(origin: .zero, size: TestConfiguration.shared.testARViewSize))
    }
    
    override func tearDown() async throws {
        arView = nil
        
        await TestUtilities.forceGarbageCollection()
        let finalMemory = TestUtilities.getCurrentMemoryUsage()
        
        TestUtilities.assertMemoryGrowthWithinLimit(
            initial: initialMemory,
            final: finalMemory,
            limit: TestConfiguration.shared.maxMemoryGrowth
        )
    }
}

class PerformanceTestCase: ARchitectTestCase {
    
    func measurePerformance<T>(
        name: String,
        maxTime: TimeInterval = TestConfiguration.shared.maxFrameTime,
        operation: () throws -> T
    ) rethrows -> T {
        let (result, time) = try TestUtilities.measureExecutionTime(operation: operation)
        
        TestUtilities.assertExecutionTimeWithinLimit(time, limit: maxTime, operation: name)
        
        return result
    }
    
    func measureAsyncPerformance<T>(
        name: String,
        maxTime: TimeInterval = TestConfiguration.shared.maxFrameTime,
        operation: () async throws -> T
    ) async rethrows -> T {
        let (result, time) = try await TestUtilities.measureAsyncExecutionTime(operation: operation)
        
        TestUtilities.assertExecutionTimeWithinLimit(time, limit: maxTime, operation: name)
        
        return result
    }
}

// MARK: - Mock Classes

class MockARSessionManager: ARSessionManager {
    @Published var mockSessionState: ARSessionState = .running
    @Published var mockTrackingQuality: ARTrackingQuality = .normal
    @Published var mockDetectedPlanes: [ARPlaneAnchor] = []
    
    override var sessionState: ARSessionState { mockSessionState }
    override var trackingQuality: ARTrackingQuality { mockTrackingQuality }
    override var detectedPlanes: [ARPlaneAnchor] { mockDetectedPlanes }
    
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

// MARK: - Extensions for Testing

extension UIColor {
    static func random() -> UIColor {
        return UIColor(
            red: .random(in: 0...1),
            green: .random(in: 0...1),
            blue: .random(in: 0...1),
            alpha: 1.0
        )
    }
}

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

// MARK: - Test Data Providers

struct TestDataProvider {
    
    static func sampleFurnitureCategories() -> [FurnitureCategory] {
        return FurnitureCategory.allCases
    }
    
    static func sampleDimensions() -> [FurnitureDimensions] {
        return [
            FurnitureDimensions(width: 0.5, height: 0.8, depth: 0.5), // Chair
            FurnitureDimensions(width: 1.5, height: 0.75, depth: 0.8), // Table
            FurnitureDimensions(width: 2.0, height: 0.85, depth: 0.9), // Sofa
            FurnitureDimensions(width: 2.0, height: 0.5, depth: 1.5), // Bed
            FurnitureDimensions(width: 1.2, height: 0.75, depth: 0.6)  // Desk
        ]
    }
    
    static func samplePhysicsProperties() -> [PhysicsProperties] {
        return [
            PhysicsProperties(), // Default
            PhysicsProperties(mass: 5.0, friction: 0.8),
            PhysicsProperties(mass: 0.5, canSnap: false),
            PhysicsProperties(mass: 10.0, isKinematic: true),
            PhysicsProperties(castsShadows: false, receivesOcclusion: false)
        ]
    }
}