import XCTest
@testable import ARchitect

final class FurnitureItemTests: XCTestCase {
    
    func testFurnitureItemInitialization() {
        let dimensions = FurnitureDimensions(width: 1.0, height: 0.8, depth: 0.6)
        let item = FurnitureItem(
            name: "Test Chair",
            category: .chair,
            dimensions: dimensions,
            modelResource: "chair_model.usd"
        )
        
        XCTAssertFalse(item.id.uuidString.isEmpty)
        XCTAssertEqual(item.name, "Test Chair")
        XCTAssertEqual(item.category, .chair)
        XCTAssertEqual(item.dimensions.width, 1.0)
        XCTAssertEqual(item.dimensions.height, 0.8)
        XCTAssertEqual(item.dimensions.depth, 0.6)
        XCTAssertEqual(item.modelResource, "chair_model.usd")
        XCTAssertEqual(item.position, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(item.rotation, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(item.scale, SIMD3<Float>(1, 1, 1))
        XCTAssertFalse(item.isPlaced)
        XCTAssertNotNil(item.createdAt)
    }
    
    func testFurnitureItemWithCustomPosition() {
        let dimensions = FurnitureDimensions(width: 1.0, height: 0.8, depth: 0.6)
        let customPosition = SIMD3<Float>(1.0, 0.5, -2.0)
        let item = FurnitureItem(
            name: "Test Table",
            category: .table,
            dimensions: dimensions,
            modelResource: "table_model.usd",
            position: customPosition
        )
        
        XCTAssertEqual(item.position, customPosition)
    }
    
    func testFurnitureCategoryAllCases() {
        let expectedCategories: [FurnitureCategory] = [
            .chair, .table, .sofa, .bed, .desk, .bookshelf, .lamp, .plant, .artwork, .storage
        ]
        
        XCTAssertEqual(FurnitureCategory.allCases.count, expectedCategories.count)
        for category in expectedCategories {
            XCTAssertTrue(FurnitureCategory.allCases.contains(category))
        }
    }
    
    func testFurnitureDimensionsCalculations() {
        let dimensions = FurnitureDimensions(width: 2.0, height: 1.5, depth: 1.0)
        
        XCTAssertEqual(dimensions.width, 2.0)
        XCTAssertEqual(dimensions.height, 1.5)
        XCTAssertEqual(dimensions.depth, 1.0)
    }
}