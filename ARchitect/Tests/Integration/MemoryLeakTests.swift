import XCTest
import RealityKit
import ARKit
import Combine
@testable import ARchitect

final class MemoryLeakTests: XCTestCase {
    
    var initialMemory: Int = 0
    var memoryGrowthThreshold: Int = 50 * 1024 * 1024 // 50MB threshold
    
    override func setUp() async throws {
        // Force garbage collection before starting
        await forceGarbageCollection()
        initialMemory = getCurrentMemoryUsage()
        print("Initial memory usage: \(initialMemory / 1024 / 1024)MB")
    }
    
    override func tearDown() async throws {
        await forceGarbageCollection()
        let finalMemory = getCurrentMemoryUsage()
        let memoryDifference = finalMemory - initialMemory
        
        print("Final memory usage: \(finalMemory / 1024 / 1024)MB")
        print("Memory difference: \(memoryDifference / 1024 / 1024)MB")
        
        // Allow some memory growth, but not excessive
        XCTAssertLessThan(memoryDifference, memoryGrowthThreshold, 
                         "Memory grew by \(memoryDifference / 1024 / 1024)MB, threshold is \(memoryGrowthThreshold / 1024 / 1024)MB")
    }
    
    // MARK: - AR Session Memory Leak Tests
    
    func testARViewMemoryLeaks() async throws {
        weak var weakARView: ARView?
        weak var weakSession: ARSession?
        
        await autoreleasepool {
            let arView = ARView(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
            weakARView = arView
            weakSession = arView.session
            
            let config = ARWorldTrackingConfiguration()
            arView.session.run(config)
            
            // Add some entities
            for i in 0..<10 {
                let entity = createTestEntity(id: i)
                arView.scene.addAnchor(entity)
            }
            
            // Simulate usage
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // Clean up
            arView.session.pause()
            arView.scene.anchors.removeAll()
        }
        
        await forceGarbageCollection()
        
        XCTAssertNil(weakARView, "ARView should be deallocated")
        XCTAssertNil(weakSession, "ARSession should be deallocated")
    }
    
    func testARSessionManagerMemoryLeaks() async throws {
        weak var weakSessionManager: ARSessionManager?
        
        await autoreleasepool {
            let sessionManager = ARSessionManager()
            weakSessionManager = sessionManager
            
            // Initialize and use the session manager
            await sessionManager.initialize()
            
            let config = ARConfigurationOptions(
                planeDetection: [.horizontal, .vertical],
                sceneReconstruction: .mesh,
                environmentTexturing: .automatic
            )
            sessionManager.updateConfiguration(config)
            
            // Simulate running for a short time
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            
            await sessionManager.pause()
        }
        
        await forceGarbageCollection()
        
        XCTAssertNil(weakSessionManager, "ARSessionManager should be deallocated")
    }
    
    // MARK: - Physics System Memory Leak Tests
    
    func testPhysicsSystemMemoryLeaks() async throws {
        weak var weakPhysicsSystem: PhysicsSystem?
        var entityIds: [UUID] = []
        
        await autoreleasepool {
            let physicsSystem = await PhysicsSystem()
            weakPhysicsSystem = physicsSystem
            
            let arView = ARView(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
            await physicsSystem.initialize(with: arView)
            
            // Add entities and track their IDs
            for i in 0..<20 {
                let entity = createTestEntity(id: i)
                entityIds.append(entity.id)
                
                let properties = PhysicsProperties()
                try await physicsSystem.addEntity(entity, physicsProperties: properties)
            }
            
            // Remove entities
            for entityId in entityIds {
                await physicsSystem.removeEntity(entityId)
            }
            
            // Get final statistics
            let _ = await physicsSystem.getPhysicsStatistics()
        }
        
        await forceGarbageCollection()
        
        XCTAssertNil(weakPhysicsSystem, "PhysicsSystem should be deallocated")
    }
    
    // MARK: - Room Scanner Memory Leak Tests
    
    func testRoomScannerMemoryLeaks() async throws {
        weak var weakRoomScanner: RoomScanner?
        weak var weakSessionManager: ARSessionManager?
        
        await autoreleasepool {
            let sessionManager = ARSessionManager()
            weakSessionManager = sessionManager
            
            let roomScanner = RoomScanner(sessionManager: sessionManager)
            weakRoomScanner = roomScanner
            
            // Start scanning
            roomScanner.startScanning(roomName: "Test Room")
            
            // Simulate scanning for a short time
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Stop scanning
            roomScanner.stopScanning()
            
            // Wait for processing to complete
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        await forceGarbageCollection()
        
        XCTAssertNil(weakRoomScanner, "RoomScanner should be deallocated")
        XCTAssertNil(weakSessionManager, "ARSessionManager should be deallocated")
    }
    
    // MARK: - Entity Creation and Destruction Memory Leak Tests
    
    func testEntityCreationDestructionCycle() async throws {
        weak var weakARView: ARView?
        var weakEntities: [WeakReference<ModelEntity>] = []
        
        await autoreleasepool {
            let arView = ARView(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
            weakARView = arView
            
            // Create and destroy entities multiple times
            for cycle in 0..<5 {
                var entities: [ModelEntity] = []
                
                // Create entities
                for i in 0..<10 {
                    let entity = createTestEntity(id: cycle * 10 + i)
                    entities.append(entity)
                    weakEntities.append(WeakReference(entity))
                    arView.scene.addAnchor(entity)
                }
                
                // Use entities briefly
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                
                // Remove entities
                for entity in entities {
                    arView.scene.removeAnchor(entity)
                }
                
                entities.removeAll()
                
                // Force intermediate cleanup
                await forceGarbageCollection()
            }
        }
        
        await forceGarbageCollection()
        
        XCTAssertNil(weakARView, "ARView should be deallocated")
        
        // Check that all entities were deallocated
        for weakEntity in weakEntities {
            XCTAssertNil(weakEntity.object, "Entity should be deallocated")
        }
    }
    
    // MARK: - Combine Publishers Memory Leak Tests
    
    func testCombinePublishersMemoryLeaks() async throws {
        weak var weakSessionManager: ARSessionManager?
        var cancellables: Set<AnyCancellable> = []
        
        await autoreleasepool {
            let sessionManager = ARSessionManager()
            weakSessionManager = sessionManager
            
            // Subscribe to various publishers
            sessionManager.$sessionState
                .sink { _ in }
                .store(in: &cancellables)
            
            sessionManager.$trackingQuality
                .sink { _ in }
                .store(in: &cancellables)
            
            sessionManager.$detectedPlanes
                .sink { _ in }
                .store(in: &cancellables)
            
            // Simulate state changes
            await sessionManager.initialize()
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await sessionManager.pause()
            
            // Cancel subscriptions
            cancellables.removeAll()
        }
        
        await forceGarbageCollection()
        
        XCTAssertNil(weakSessionManager, "ARSessionManager should be deallocated")
    }
    
    // MARK: - Large Object Memory Leak Tests
    
    func testLargeObjectMemoryLeaks() async throws {
        let cycleCount = 10
        let objectsPerCycle = 50
        
        for cycle in 0..<cycleCount {
            weak var weakARView: ARView?
            
            await autoreleasepool {
                let arView = ARView(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
                weakARView = arView
                
                // Create many entities with complex materials
                for i in 0..<objectsPerCycle {
                    let entity = createComplexEntity(id: cycle * objectsPerCycle + i)
                    arView.scene.addAnchor(entity)
                }
                
                // Brief usage
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                
                // Remove all anchors
                arView.scene.anchors.removeAll()
            }
            
            await forceGarbageCollection()
            
            XCTAssertNil(weakARView, "ARView should be deallocated in cycle \(cycle)")
            
            // Check memory growth
            let currentMemory = getCurrentMemoryUsage()
            let memoryGrowth = currentMemory - initialMemory
            
            // Memory shouldn't grow linearly with cycles
            let maxExpectedGrowth = (cycle + 1) * 10 * 1024 * 1024 // 10MB per cycle max
            XCTAssertLessThan(memoryGrowth, maxExpectedGrowth, 
                             "Memory growth too high in cycle \(cycle): \(memoryGrowth / 1024 / 1024)MB")
        }
    }
    
    // MARK: - Timer and Callback Memory Leak Tests
    
    func testTimerMemoryLeaks() async throws {
        weak var weakObject: TestObjectWithTimer?
        
        await autoreleasepool {
            let testObject = TestObjectWithTimer()
            weakObject = testObject
            
            testObject.startTimer()
            
            // Let timer run briefly
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            
            testObject.stopTimer()
        }
        
        await forceGarbageCollection()
        
        XCTAssertNil(weakObject, "Test object with timer should be deallocated")
    }
    
    // MARK: - Delegate Memory Leak Tests
    
    func testDelegateMemoryLeaks() async throws {
        weak var weakDelegate: TestDelegate?
        weak var weakDelegator: TestDelegator?
        
        await autoreleasepool {
            let delegate = TestDelegate()
            let delegator = TestDelegator()
            
            weakDelegate = delegate
            weakDelegator = delegator
            
            delegator.delegate = delegate
            
            // Simulate delegate usage
            delegator.performAction()
        }
        
        await forceGarbageCollection()
        
        XCTAssertNil(weakDelegate, "Delegate should be deallocated")
        XCTAssertNil(weakDelegator, "Delegator should be deallocated")
    }
    
    // MARK: - Stress Test for Memory Leaks
    
    func testMemoryLeakUnderStress() async throws {
        let iterations = 100
        var peakMemory = initialMemory
        
        for i in 0..<iterations {
            await autoreleasepool {
                let arView = ARView(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
                
                // Quick entity creation and destruction
                let entity = createTestEntity(id: i)
                arView.scene.addAnchor(entity)
                arView.scene.removeAnchor(entity)
            }
            
            // Check memory every 10 iterations
            if i % 10 == 0 {
                await forceGarbageCollection()
                let currentMemory = getCurrentMemoryUsage()
                peakMemory = max(peakMemory, currentMemory)
                
                let memoryGrowth = currentMemory - initialMemory
                print("Iteration \(i): Memory growth: \(memoryGrowth / 1024 / 1024)MB")
                
                // Memory growth should be minimal
                XCTAssertLessThan(memoryGrowth, 20 * 1024 * 1024, 
                                 "Memory growth too high at iteration \(i)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestEntity(id: Int) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: 0.1)
        let material = SimpleMaterial(color: .blue, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "TestEntity_\(id)"
        return entity
    }
    
    private func createComplexEntity(id: Int) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: 0.15)
        
        // Complex material with textures
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = UIColor.random()
        material.metallic = 0.5
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.3)
        
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "ComplexEntity_\(id)"
        
        // Add components that might cause leaks
        entity.components.set(GroundingShadowComponent(castsShadow: true))
        
        return entity
    }
    
    private func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
    
    private func forceGarbageCollection() async {
        // Force garbage collection by creating and releasing objects
        for _ in 0..<10 {
            autoreleasepool {
                _ = Array(0..<1000).map { _ in NSObject() }
            }
        }
        
        // Give time for cleanup
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }
}

// MARK: - Helper Classes for Testing

class WeakReference<T: AnyObject> {
    weak var object: T?
    
    init(_ object: T) {
        self.object = object
    }
}

class TestObjectWithTimer {
    private var timer: Timer?
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.timerFired()
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func timerFired() {
        // Timer callback
    }
    
    deinit {
        stopTimer()
    }
}

protocol TestDelegateProtocol: AnyObject {
    func actionPerformed()
}

class TestDelegate: TestDelegateProtocol {
    func actionPerformed() {
        // Delegate method implementation
    }
}

class TestDelegator {
    weak var delegate: TestDelegateProtocol?
    
    func performAction() {
        delegate?.actionPerformed()
    }
}

// MARK: - Extensions

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