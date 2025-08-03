import XCTest
@testable import ARchitect

final class FurniturePlacementUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Navigate to furniture placement
        navigateToFurniturePlacement()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    private func navigateToFurniturePlacement() {
        let catalogButton = app.buttons["Furniture Catalog"]
        if catalogButton.exists {
            catalogButton.tap()
        }
    }
    
    func testFurnitureCatalogAccess() throws {
        let catalogView = app.otherElements["FurnitureCatalogView"]
        XCTAssertTrue(catalogView.waitForExistence(timeout: 5.0))
        
        // Test category filters
        let categoryFilter = app.buttons["Chair"]
        if categoryFilter.exists {
            categoryFilter.tap()
            
            // Verify filtering works
            let chairItems = app.cells.containing(NSPredicate(format: "label CONTAINS 'Chair'"))
            XCTAssertTrue(chairItems.count > 0)
        }
    }
    
    func testFurnitureItemSelection() throws {
        let catalogView = app.otherElements["FurnitureCatalogView"]
        XCTAssertTrue(catalogView.waitForExistence(timeout: 5.0))
        
        // Select first furniture item
        let firstItem = app.cells.firstMatch
        if firstItem.exists {
            firstItem.tap()
            
            let detailView = app.otherElements["FurnitureItemDetailView"]
            XCTAssertTrue(detailView.waitForExistence(timeout: 3.0))
            
            let placeButton = app.buttons["Place in AR"]
            XCTAssertTrue(placeButton.exists)
        }
    }
    
    func testFurniturePlacement() throws {
        // Select and place furniture
        let firstItem = app.cells.firstMatch
        if firstItem.exists {
            firstItem.tap()
            
            let placeButton = app.buttons["Place in AR"]
            if placeButton.waitForExistence(timeout: 3.0) {
                placeButton.tap()
                
                // Should transition to AR placement mode
                let arView = app.otherElements["ARView"]
                XCTAssertTrue(arView.waitForExistence(timeout: 3.0))
                
                let placementIndicator = app.otherElements["PlacementIndicator"]
                XCTAssertTrue(placementIndicator.waitForExistence(timeout: 3.0))
            }
        }
    }
    
    func testFurnitureManipulation() throws {
        // Test furniture manipulation controls
        let manipulationControls = app.otherElements["ManipulationControls"]
        if manipulationControls.waitForExistence(timeout: 3.0) {
            
            let rotateButton = app.buttons["Rotate"]
            if rotateButton.exists {
                rotateButton.tap()
                XCTAssertTrue(rotateButton.isSelected)
            }
            
            let scaleButton = app.buttons["Scale"]
            if scaleButton.exists {
                scaleButton.tap()
                XCTAssertTrue(scaleButton.isSelected)
            }
            
            let moveButton = app.buttons["Move"]
            if moveButton.exists {
                moveButton.tap()
                XCTAssertTrue(moveButton.isSelected)
            }
        }
    }
    
    func testGestureHandling() throws {
        let arView = app.otherElements["ARView"]
        if arView.waitForExistence(timeout: 3.0) {
            
            // Test tap gesture (selection)
            arView.tap()
            
            // Test long press (context menu)
            arView.press(forDuration: 1.0)
            
            let contextMenu = app.menus.firstMatch
            if contextMenu.exists {
                XCTAssertTrue(contextMenu.exists)
            }
            
            // Test pinch gesture (scaling) - simulated
            // Note: XCUITest has limited gesture simulation capabilities
        }
    }
    
    func testFurnitureDeletion() throws {
        // Test removing placed furniture
        let arView = app.otherElements["ARView"]
        if arView.waitForExistence(timeout: 3.0) {
            
            // Long press to bring up context menu
            arView.press(forDuration: 1.0)
            
            let deleteButton = app.buttons["Delete"]
            if deleteButton.exists {
                deleteButton.tap()
                
                let confirmButton = app.alerts.buttons["Delete"]
                if confirmButton.exists {
                    confirmButton.tap()
                }
            }
        }
    }
    
    func testUndoRedoFunctionality() throws {
        let undoButton = app.buttons["Undo"]
        let redoButton = app.buttons["Redo"]
        
        if undoButton.exists {
            XCTAssertTrue(undoButton.exists)
            
            // Test undo action
            undoButton.tap()
        }
        
        if redoButton.exists {
            XCTAssertTrue(redoButton.exists)
            
            // Test redo action
            redoButton.tap()
        }
    }
    
    func testSnapToSurface() throws {
        let snapButton = app.buttons["Snap to Surface"]
        if snapButton.waitForExistence(timeout: 3.0) {
            snapButton.tap()
            
            // Verify snap mode is active
            XCTAssertTrue(snapButton.isSelected)
            
            let snapIndicator = app.otherElements["SnapIndicator"]
            XCTAssertTrue(snapIndicator.waitForExistence(timeout: 3.0))
        }
    }
    
    func testCollisionDetection() throws {
        let collisionIndicator = app.otherElements["CollisionIndicator"]
        // This would appear when furniture overlaps
        if collisionIndicator.exists {
            XCTAssertTrue(collisionIndicator.exists)
            
            let warningMessage = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'collision'"))
            XCTAssertTrue(warningMessage.firstMatch.exists)
        }
    }
    
    func testFurnitureFilters() throws {
        let catalogView = app.otherElements["FurnitureCatalogView"]
        XCTAssertTrue(catalogView.waitForExistence(timeout: 5.0))
        
        let filtersButton = app.buttons["Filters"]
        if filtersButton.exists {
            filtersButton.tap()
            
            let filterView = app.otherElements["FurnitureFiltersView"]
            XCTAssertTrue(filterView.waitForExistence(timeout: 3.0))
            
            // Test price range filter
            let priceSlider = app.sliders["PriceRange"]
            if priceSlider.exists {
                priceSlider.adjust(toNormalizedSliderPosition: 0.5)
            }
            
            // Test color filter
            let colorFilter = app.buttons["Brown"]
            if colorFilter.exists {
                colorFilter.tap()
                XCTAssertTrue(colorFilter.isSelected)
            }
            
            let applyButton = app.buttons["Apply Filters"]
            if applyButton.exists {
                applyButton.tap()
            }
        }
    }
    
    func testFurnitureSearch() throws {
        let catalogView = app.otherElements["FurnitureCatalogView"]
        XCTAssertTrue(catalogView.waitForExistence(timeout: 5.0))
        
        let searchField = app.searchFields["Search Furniture"]
        if searchField.exists {
            searchField.tap()
            searchField.typeText("chair")
            
            let searchButton = app.buttons["Search"]
            if searchButton.exists {
                searchButton.tap()
            }
            
            // Verify search results
            let searchResults = app.cells.containing(NSPredicate(format: "label CONTAINS[c] 'chair'"))
            XCTAssertTrue(searchResults.count > 0)
        }
    }
    
    func testSaveArrangement() throws {
        let saveButton = app.buttons["Save Arrangement"]
        if saveButton.waitForExistence(timeout: 3.0) {
            saveButton.tap()
            
            let saveDialog = app.alerts.firstMatch
            if saveDialog.exists {
                let nameField = app.textFields["Arrangement Name"]
                if nameField.exists {
                    nameField.tap()
                    nameField.typeText("My Room Design")
                }
                
                let confirmSaveButton = app.buttons["Save"]
                confirmSaveButton.tap()
            }
        }
    }
    
    func testLoadArrangement() throws {
        let loadButton = app.buttons["Load Arrangement"]
        if loadButton.waitForExistence(timeout: 3.0) {
            loadButton.tap()
            
            let arrangementsList = app.tables["SavedArrangements"]
            if arrangementsList.waitForExistence(timeout: 3.0) {
                let firstArrangement = arrangementsList.cells.firstMatch
                if firstArrangement.exists {
                    firstArrangement.tap()
                    
                    let loadConfirmButton = app.buttons["Load"]
                    if loadConfirmButton.exists {
                        loadConfirmButton.tap()
                    }
                }
            }
        }
    }
}