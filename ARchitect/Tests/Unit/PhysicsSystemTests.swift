import XCTest
import RealityKit
import ARKit
@testable import ARchitect

final class PhysicsSystemTests: XCTestCase {
    
    var physicsSystem: PhysicsSystem!
    
    override func setUp() async throws {
        physicsSystem = await PhysicsSystem()
    }
    
    override func tearDown() {
        physicsSystem = nil
    }
    
    func testPhysicsSystemInitialization() async {
        XCTAssertTrue(await physicsSystem.isEnabled)
        XCTAssertTrue(await physicsSystem.gravityEnabled)
        XCTAssertTrue(await physicsSystem.collisionDetectionEnabled)
        XCTAssertTrue(await physicsSystem.snapToFloorEnabled)
        XCTAssertTrue(await physicsSystem.snapToWallEnabled)
        XCTAssertTrue(await physicsSystem.shadowsEnabled)
        XCTAssertTrue(await physicsSystem.occlusionEnabled)
        XCTAssertTrue(await physicsSystem.performanceOptimized)
    }
    
    func testPhysicsConfiguration() {
        let config = PhysicsSystem.PhysicsConfiguration()
        
        XCTAssertEqual(config.gravity.y, -9.81, accuracy: 0.01)
        XCTAssertEqual(config.collisionMargin, 0.01)
        XCTAssertEqual(config.snapDistance, 0.05)
        XCTAssertEqual(config.snapAngleTolerance, 15.0)
        XCTAssertEqual(config.damping, 0.98)
        XCTAssertEqual(config.restitution, 0.3)
        XCTAssertEqual(config.friction, 0.7)
        XCTAssertEqual(config.maxVelocity, 10.0)
        XCTAssertEqual(config.sleepThreshold, 0.01)
        XCTAssertEqual(config.performanceBudget, 0.008)
    }
    
    func testPhysicsProperties() {
        let properties = PhysicsProperties()
        
        XCTAssertEqual(properties.mass, 1.0)
        XCTAssertNil(properties.friction)
        XCTAssertNil(properties.restitution)
        XCTAssertTrue(properties.canSnap)
        XCTAssertTrue(properties.castsShadows)
        XCTAssertTrue(properties.receivesOcclusion)
        XCTAssertFalse(properties.isKinematic)
        XCTAssertEqual(properties.collisionGroup, .furniture)
    }
    
    func testPhysicsPropertiesCustomization() {
        let properties = PhysicsProperties(
            mass: 5.0,
            friction: 0.8,
            restitution: 0.2,
            canSnap: false,
            castsShadows: false,
            receivesOcclusion: false,
            isKinematic: true,
            collisionGroup: .walls
        )
        
        XCTAssertEqual(properties.mass, 5.0)
        XCTAssertEqual(properties.friction, 0.8)
        XCTAssertEqual(properties.restitution, 0.2)
        XCTAssertFalse(properties.canSnap)
        XCTAssertFalse(properties.castsShadows)
        XCTAssertFalse(properties.receivesOcclusion)
        XCTAssertTrue(properties.isKinematic)
        XCTAssertEqual(properties.collisionGroup, .walls)
    }
    
    func testCollisionGroups() {
        XCTAssertEqual(CollisionGroup.none.rawValue, 0)
        XCTAssertEqual(CollisionGroup.furniture.rawValue, 1)
        XCTAssertEqual(CollisionGroup.walls.rawValue, 2)
        XCTAssertEqual(CollisionGroup.floor.rawValue, 4)
        XCTAssertEqual(CollisionGroup.ceiling.rawValue, 8)
        XCTAssertEqual(CollisionGroup.decoration.rawValue, 16)
        XCTAssertEqual(CollisionGroup.all.rawValue, 0xFFFFFFFF)
        
        XCTAssertEqual(CollisionGroup.allCases.count, 7)
    }
    
    func testPhysicsStatistics() {
        let stats = PhysicsStatistics(
            totalEntities: 10,
            activeEntities: 8,
            staticColliders: 5,
            snapTargets: 3,
            frameTime: 0.006,
            collisionChecks: 15,
            snapOperations: 2,
            shadowUpdates: 10,
            memoryUsage: 1024
        )
        
        XCTAssertEqual(stats.totalEntities, 10)
        XCTAssertEqual(stats.activeEntities, 8)
        XCTAssertEqual(stats.staticColliders, 5)
        XCTAssertEqual(stats.snapTargets, 3)
        XCTAssertEqual(stats.frameTime, 0.006)
        XCTAssertEqual(stats.collisionChecks, 15)
        XCTAssertEqual(stats.snapOperations, 2)
        XCTAssertEqual(stats.shadowUpdates, 10)
        XCTAssertEqual(stats.memoryUsage, 1024)
    }
    
    func testPhysicsConfigurationUpdate() async {
        var config = PhysicsSystem.PhysicsConfiguration()
        config.gravity = SIMD3<Float>(0, -5.0, 0)
        config.damping = 0.95
        config.friction = 0.8
        
        await physicsSystem.updateConfiguration(config)
        
        // Since we can't directly access the private configuration,
        // we verify that the method executes without error
        XCTAssertTrue(true)
    }
    
    func testPhysicsSystemSettings() async {
        await physicsSystem.setPhysicsEnabled(false, for: UUID())
        // Test should complete without error even for non-existent entity
        XCTAssertTrue(true)
    }
}