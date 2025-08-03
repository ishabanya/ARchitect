import XCTest
import RealityKit
import ARKit
@testable import ARchitect

final class StressTests: XCTestCase {
    
    var arView: ARView!
    var physicsSystem: PhysicsSystem!
    var performanceManager: PerformanceManager!
    
    override func setUp() async throws {
        arView = ARView(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        physicsSystem = await PhysicsSystem()
        performanceManager = PerformanceManager()
        
        await physicsSystem.initialize(with: arView)
    }
    
    override func tearDown() {
        arView = nil
        physicsSystem = nil
        performanceManager = nil
    }
    
    // MARK: - Object Count Stress Tests
    
    func testMassiveFurnitureCount() async throws {
        let startTime = CACurrentMediaTime()
        let targetCount = 500
        var placedCount = 0
        
        for i in 0..<targetCount {
            autoreleasepool {
                let entity = createFurnitureEntity(id: i)
                arView.scene.addAnchor(entity)
                
                Task {
                    let properties = PhysicsProperties()
                    try? await physicsSystem.addEntity(entity, physicsProperties: properties)
                }
                
                placedCount += 1
                
                // Check performance every 50 objects
                if i % 50 == 0 {
                    let currentTime = CACurrentMediaTime()
                    let duration = currentTime - startTime
                    
                    // Should not take more than 1 second per 50 objects
                    XCTAssertLessThan(duration / Double(i + 1) * 50, 1.0, 
                                    "Performance degraded with \(i + 1) objects")
                }
            }
        }
        
        let endTime = CACurrentMediaTime()
        let totalDuration = endTime - startTime
        
        XCTAssertEqual(placedCount, targetCount)
        XCTAssertLessThan(totalDuration, 30.0, "Should place 500 objects in under 30 seconds")
        
        // Check memory usage
        let memoryUsage = getCurrentMemoryUsage()
        XCTAssertLessThan(memoryUsage, 500 * 1024 * 1024, "Memory usage should stay under 500MB")
        
        let statistics = await physicsSystem.getPhysicsStatistics()
        XCTAssertEqual(statistics.totalEntities, targetCount)
    }
    
    func testExtremeFurnitureCount() async throws {
        let extremeCount = 1000
        var successfulPlacements = 0
        let startMemory = getCurrentMemoryUsage()
        
        for i in 0..<extremeCount {
            autoreleasepool {
                do {
                    let entity = createLightweightEntity(id: i)
                    arView.scene.addAnchor(entity)
                    
                    let properties = PhysicsProperties(mass: 0.1) // Lighter objects
                    try await physicsSystem.addEntity(entity, physicsProperties: properties)
                    
                    successfulPlacements += 1
                    
                    // Monitor memory growth
                    if i % 100 == 0 {
                        let currentMemory = getCurrentMemoryUsage()
                        let memoryGrowth = currentMemory - startMemory
                        
                        // Memory growth should be linear, not exponential
                        let expectedMaxGrowth = (i + 1) * 1024 * 50 // 50KB per object max
                        XCTAssertLessThan(memoryGrowth, expectedMaxGrowth, 
                                        "Memory growth too steep at \(i + 1) objects")
                    }
                } catch {
                    // Count failures but don't fail test immediately
                    print("Failed to place object \(i): \(error)")
                }
            }
        }
        
        // Should successfully place at least 80% of objects
        XCTAssertGreaterThan(successfulPlacements, Int(0.8 * Double(extremeCount)))
        
        let statistics = await physicsSystem.getPhysicsStatistics()
        print("Final statistics: \(statistics)")
    }
    
    // MARK: - Concurrent Operations Stress Tests
    
    func testConcurrentPlacement() async throws {
        let concurrentCount = 100
        let groupSize = 10
        
        await withTaskGroup(of: Void.self) { group in
            for batch in 0..<(concurrentCount / groupSize) {
                group.addTask {
                    await self.placeBatchOfObjects(
                        startIndex: batch * groupSize,
                        count: groupSize
                    )
                }
            }
        }
        
        let statistics = await physicsSystem.getPhysicsStatistics()
        XCTAssertGreaterThanOrEqual(statistics.totalEntities, concurrentCount / 2) // Allow some failures
    }
    
    private func placeBatchOfObjects(startIndex: Int, count: Int) async {
        for i in 0..<count {
            let objectIndex = startIndex + i
            let entity = createFurnitureEntity(id: objectIndex)
            
            await MainActor.run {
                arView.scene.addAnchor(entity)
            }
            
            let properties = PhysicsProperties()
            try? await physicsSystem.addEntity(entity, physicsProperties: properties)
            
            // Small delay to simulate realistic usage
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
    
    // MARK: - Physics Stress Tests
    
    func testMassiveCollisionDetection() async throws {
        let objectCount = 200
        var entities: [ModelEntity] = []
        
        // Create clustered objects to increase collision probability
        for i in 0..<objectCount {
            let entity = createFurnitureEntity(id: i)
            
            // Position in a grid with some overlap
            let gridSize = 10
            let x = Float(i % gridSize) * 0.8 // Slight overlap
            let z = Float(i / gridSize) * 0.8
            entity.position = simd_float3(x, 0, z)
            
            arView.scene.addAnchor(entity)
            entities.append(entity)
            
            let properties = PhysicsProperties()
            try await physicsSystem.addEntity(entity, physicsProperties: properties)
        }
        
        // Force collision detection updates
        let startTime = CACurrentMediaTime()
        
        for _ in 0..<60 { // Simulate 1 second at 60 FPS
            let statistics = await physicsSystem.getPhysicsStatistics()
            
            // Frame time should stay reasonable even with many collisions
            XCTAssertLessThan(statistics.frameTime, 0.016, "Frame time too high: \(statistics.frameTime)s")
            
            try await Task.sleep(nanoseconds: 16_666_667) // ~60 FPS
        }
        
        let endTime = CACurrentMediaTime()
        let averageFrameTime = (endTime - startTime) / 60.0
        
        XCTAssertLessThan(averageFrameTime, 0.02, "Average frame time too high")
    }
    
    func testRapidObjectManipulation() async throws {
        let entity = createFurnitureEntity(id: 0)
        arView.scene.addAnchor(entity)
        
        let properties = PhysicsProperties()
        try await physicsSystem.addEntity(entity, physicsProperties: properties)
        
        let operationCount = 1000
        let startTime = CACurrentMediaTime()
        
        for i in 0..<operationCount {
            let force = simd_float3(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            )
            
            await physicsSystem.applyForce(force, to: entity.id)
            
            // Occasional snapping
            if i % 10 == 0 {
                await physicsSystem.snapToSurface(entity.id)
            }
        }
        
        let endTime = CACurrentMediaTime()
        let totalTime = endTime - startTime
        
        XCTAssertLessThan(totalTime, 5.0, "1000 physics operations should complete in under 5 seconds")
    }
    
    // MARK: - Memory Stress Tests
    
    func testMemoryPressure() async throws {
        let cycles = 10
        let objectsPerCycle = 100
        
        for cycle in 0..<cycles {
            var entities: [ModelEntity] = []
            
            // Create objects
            for i in 0..<objectsPerCycle {
                let entity = createFurnitureEntity(id: cycle * objectsPerCycle + i)
                arView.scene.addAnchor(entity)
                entities.append(entity)
                
                let properties = PhysicsProperties()
                try await physicsSystem.addEntity(entity, physicsProperties: properties)
            }
            
            // Force memory usage
            let _ = await physicsSystem.getPhysicsStatistics()
            
            // Remove all objects
            for entity in entities {
                await physicsSystem.removeEntity(entity.id)
                arView.scene.removeAnchor(entity)
            }
            
            // Force cleanup
            for _ in 0..<5 {
                autoreleasepool {
                    _ = Array(0..<1000).map { _ in NSObject() }
                }
            }
            
            let memoryUsage = getCurrentMemoryUsage()
            
            // Memory should not grow significantly between cycles
            if cycle > 0 {
                XCTAssertLessThan(memoryUsage, 200 * 1024 * 1024, 
                                "Memory usage too high after cycle \(cycle)")
            }
        }
    }
    
    // MARK: - Rendering Stress Tests
    
    func testComplexSceneRendering() throws {
        let objectCount = 300
        
        // Create diverse objects with different materials and effects
        for i in 0..<objectCount {
            let entity = createComplexEntity(id: i)
            
            // Distribute in 3D space
            let radius = Float(i % 50) * 0.5
            let angle = Float(i) * 0.1
            entity.position = simd_float3(
                cos(angle) * radius,
                Float(i % 10) * 0.2,
                sin(angle) * radius
            )
            
            arView.scene.addAnchor(entity)
        }
        
        // Test rendering performance
        let startTime = CACurrentMediaTime()
        
        // Force multiple renders
        for _ in 0..<30 {
            arView.snapshot(saveToHDR: false) { _ in }
            Thread.sleep(forTimeInterval: 0.033) // ~30 FPS
        }
        
        let endTime = CACurrentMediaTime()
        let renderTime = endTime - startTime
        
        XCTAssertLessThan(renderTime, 2.0, "Complex scene rendering too slow")
    }
    
    // MARK: - System Resource Tests
    
    func testCPUIntensiveOperations() async throws {
        let entity = createFurnitureEntity(id: 0)
        arView.scene.addAnchor(entity)
        
        let properties = PhysicsProperties()
        try await physicsSystem.addEntity(entity, physicsProperties: properties)
        
        // Simulate CPU-intensive operations
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 { // Use multiple cores
                group.addTask {
                    for _ in 0..<1000 {
                        await self.physicsSystem.applyImpulse(
                            simd_float3(1, 0, 0), 
                            to: entity.id
                        )
                    }
                }
            }
        }
        
        let statistics = await physicsSystem.getPhysicsStatistics()
        XCTAssertLessThan(statistics.frameTime, 0.1, "Frame time should remain reasonable under CPU load")
    }
    
    // MARK: - Helper Methods
    
    private func createFurnitureEntity(id: Int) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: 0.1)
        let material = SimpleMaterial(color: .systemBlue, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "TestEntity_\(id)"
        return entity
    }
    
    private func createLightweightEntity(id: Int) -> ModelEntity {
        // Minimal entity for extreme count tests
        let mesh = MeshResource.generateBox(size: 0.05)
        let material = UnlitMaterial(color: .white)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "Lightweight_\(id)"
        return entity
    }
    
    private func createComplexEntity(id: Int) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: 0.15)
        
        // Complex material with various properties
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = UIColor(
            hue: CGFloat(id % 360) / 360.0,
            saturation: 0.8,
            brightness: 0.9,
            alpha: 1.0
        )
        material.metallic = 0.5
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.3)
        
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "ComplexEntity_\(id)"
        
        // Add shadow component
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
}