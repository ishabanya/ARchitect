import Foundation
import simd

// MARK: - Spatial Grid

public class SpatialGrid {
    
    // MARK: - Properties
    private let cellSize: Float
    private var cells: [GridCell: SpatialCell] = [:]
    private var entityToCells: [UUID: Set<GridCell>] = [:]
    private var staticColliderToCells: [UUID: Set<GridCell>] = [:]
    
    // Performance tracking
    private var totalCells: Int = 0
    private var activeCells: Int = 0
    private var lastOptimizationTime: TimeInterval = 0
    
    public init(cellSize: Float) {
        self.cellSize = cellSize
        
        logDebug("Spatial grid initialized", category: .general, context: LogContext(customData: [
            "cell_size": cellSize
        ]))
    }
    
    // MARK: - Entity Management
    
    public func addEntity(_ entity: PhysicsEntity) {
        updateEntity(entity)
    }
    
    public func updateEntity(_ entity: PhysicsEntity) {
        // Remove from old cells
        if let oldCells = entityToCells[entity.id] {
            for gridCell in oldCells {
                cells[gridCell]?.entities.remove(entity.id)
                if cells[gridCell]?.isEmpty == true {
                    cells.removeValue(forKey: gridCell)
                }
            }
        }
        
        // Add to new cells
        let newCells = getCellsForEntity(entity)
        entityToCells[entity.id] = newCells
        
        for gridCell in newCells {
            if cells[gridCell] == nil {
                cells[gridCell] = SpatialCell()
                totalCells += 1
            }
            cells[gridCell]?.entities.insert(entity.id)
        }
        
        updateActiveCellCount()
    }
    
    public func removeEntity(_ entity: PhysicsEntity) {
        guard let entityCells = entityToCells[entity.id] else { return }
        
        for gridCell in entityCells {
            cells[gridCell]?.entities.remove(entity.id)
            if cells[gridCell]?.isEmpty == true {
                cells.removeValue(forKey: gridCell)
                totalCells -= 1
            }
        }
        
        entityToCells.removeValue(forKey: entity.id)
        updateActiveCellCount()
        
        logDebug("Removed entity from spatial grid", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString,
            "cells_affected": entityCells.count
        ]))
    }
    
    // MARK: - Static Collider Management
    
    public func addStaticCollider(_ collider: StaticCollider) {
        let cells = getCellsForStaticCollider(collider)
        staticColliderToCells[collider.id] = cells
        
        for gridCell in cells {
            if self.cells[gridCell] == nil {
                self.cells[gridCell] = SpatialCell()
                totalCells += 1
            }
            self.cells[gridCell]?.staticColliders.insert(collider.id)
        }
        
        updateActiveCellCount()
    }
    
    public func updateStaticCollider(_ collider: StaticCollider) {
        // Remove from old cells
        if let oldCells = staticColliderToCells[collider.id] {
            for gridCell in oldCells {
                cells[gridCell]?.staticColliders.remove(collider.id)
                if cells[gridCell]?.isEmpty == true {
                    cells.removeValue(forKey: gridCell)
                    totalCells -= 1
                }
            }
        }
        
        // Add to new cells
        addStaticCollider(collider)
    }
    
    public func removeStaticCollider(_ collider: StaticCollider) {
        guard let colliderCells = staticColliderToCells[collider.id] else { return }
        
        for gridCell in colliderCells {
            cells[gridCell]?.staticColliders.remove(collider.id)
            if cells[gridCell]?.isEmpty == true {
                cells.removeValue(forKey: gridCell)
                totalCells -= 1
            }
        }
        
        staticColliderToCells.removeValue(forKey: collider.id)
        updateActiveCellCount()
    }
    
    // MARK: - Collision Queries
    
    public func getPotentialCollisions(for entity: PhysicsEntity) -> [PhysicsEntity] {
        guard let entityCells = entityToCells[entity.id] else { return [] }
        
        var potentialCollisions: Set<UUID> = []
        
        for gridCell in entityCells {
            if let cell = cells[gridCell] {
                for entityID in cell.entities {
                    if entityID != entity.id {
                        potentialCollisions.insert(entityID)
                    }
                }
            }
        }
        
        // Convert UUIDs back to entities
        // Note: In a real implementation, we'd maintain a reference to the physics world
        // For now, this is a placeholder that would need access to entity storage
        return [] // Would return actual entities
    }
    
    public func getStaticCollisions(for entity: PhysicsEntity) -> [StaticCollider] {
        guard let entityCells = entityToCells[entity.id] else { return [] }
        
        var potentialCollisions: Set<UUID> = []
        
        for gridCell in entityCells {
            if let cell = cells[gridCell] {
                for colliderID in cell.staticColliders {
                    potentialCollisions.insert(colliderID)
                }
            }
        }
        
        // Convert UUIDs back to static colliders
        // Note: In a real implementation, we'd maintain a reference to the collision detector
        // For now, this is a placeholder that would need access to static collider storage
        return [] // Would return actual static colliders
    }
    
    public func getEntitiesInRadius(center: SIMD3<Float>, radius: Float) -> Set<UUID> {
        let minCell = worldToGrid(center - SIMD3<Float>(radius, radius, radius))
        let maxCell = worldToGrid(center + SIMD3<Float>(radius, radius, radius))
        
        var entities: Set<UUID> = []
        
        for x in minCell.x...maxCell.x {
            for y in minCell.y...maxCell.y {
                for z in minCell.z...maxCell.z {
                    let gridCell = GridCell(x: x, y: y, z: z)
                    if let cell = cells[gridCell] {
                        entities.formUnion(cell.entities)
                    }
                }
            }
        }
        
        return entities
    }
    
    public func getStaticCollidersInRadius(center: SIMD3<Float>, radius: Float) -> Set<UUID> {
        let minCell = worldToGrid(center - SIMD3<Float>(radius, radius, radius))
        let maxCell = worldToGrid(center + SIMD3<Float>(radius, radius, radius))
        
        var colliders: Set<UUID> = []
        
        for x in minCell.x...maxCell.x {
            for y in minCell.y...maxCell.y {
                for z in minCell.z...maxCell.z {
                    let gridCell = GridCell(x: x, y: y, z: z)
                    if let cell = cells[gridCell] {
                        colliders.formUnion(cell.staticColliders)
                    }
                }
            }
        }
        
        return colliders
    }
    
    // MARK: - Grid Operations
    
    private func getCellsForEntity(_ entity: PhysicsEntity) -> Set<GridCell> {
        let position = entity.physicsBody.position
        let radius = getBoundingRadius(entity)
        
        return getCellsInRadius(center: position, radius: radius)
    }
    
    private func getCellsForStaticCollider(_ collider: StaticCollider) -> Set<GridCell> {
        let position = collider.getWorldPosition()
        let bounds = getBounds(for: collider.geometry)
        
        let minPoint = position - bounds.extents * 0.5
        let maxPoint = position + bounds.extents * 0.5
        
        let minCell = worldToGrid(minPoint)
        let maxCell = worldToGrid(maxPoint)
        
        var cells: Set<GridCell> = []
        
        for x in minCell.x...maxCell.x {
            for y in minCell.y...maxCell.y {
                for z in minCell.z...maxCell.z {
                    cells.insert(GridCell(x: x, y: y, z: z))
                }
            }
        }
        
        return cells
    }
    
    private func getCellsInRadius(center: SIMD3<Float>, radius: Float) -> Set<GridCell> {
        let minPoint = center - SIMD3<Float>(radius, radius, radius)
        let maxPoint = center + SIMD3<Float>(radius, radius, radius)
        
        let minCell = worldToGrid(minPoint)
        let maxCell = worldToGrid(maxPoint)
        
        var cells: Set<GridCell> = []
        
        for x in minCell.x...maxCell.x {
            for y in minCell.y...maxCell.y {
                for z in minCell.z...maxCell.z {
                    cells.insert(GridCell(x: x, y: y, z: z))
                }
            }
        }
        
        return cells
    }
    
    private func worldToGrid(_ position: SIMD3<Float>) -> GridCell {
        return GridCell(
            x: Int(floor(position.x / cellSize)),
            y: Int(floor(position.y / cellSize)),
            z: Int(floor(position.z / cellSize))
        )
    }
    
    private func gridToWorld(_ cell: GridCell) -> SIMD3<Float> {
        return SIMD3<Float>(
            Float(cell.x) * cellSize + cellSize * 0.5,
            Float(cell.y) * cellSize + cellSize * 0.5,
            Float(cell.z) * cellSize + cellSize * 0.5
        )
    }
    
    private func getBoundingRadius(_ entity: PhysicsEntity) -> Float {
        // Simplified bounding radius calculation
        let bounds = entity.entity.visualBounds(relativeTo: nil)
        return simd_length(bounds.extents) * 0.5
    }
    
    private func getBounds(for geometry: ColliderGeometry) -> BoundingBox {
        switch geometry.type {
        case .box:
            if let boxGeometry = geometry as? BoxGeometry {
                return BoundingBox(
                    min: -boxGeometry.size * 0.5,
                    max: boxGeometry.size * 0.5
                )
            }
        case .sphere:
            if let sphereGeometry = geometry as? SphereGeometry {
                let radius = sphereGeometry.radius
                return BoundingBox(
                    min: SIMD3<Float>(-radius, -radius, -radius),
                    max: SIMD3<Float>(radius, radius, radius)
                )
            }
        case .plane:
            if let planeGeometry = geometry as? PlaneGeometry {
                let size = planeGeometry.bounds.extents
                return BoundingBox(
                    min: -size * 0.5,
                    max: size * 0.5
                )
            }
        case .mesh:
            // Use mesh bounding box
            if let meshGeometry = geometry as? MeshGeometry {
                return meshGeometry.bounds
            }
        }
        
        // Default bounding box
        return BoundingBox(
            min: SIMD3<Float>(-0.5, -0.5, -0.5),
            max: SIMD3<Float>(0.5, 0.5, 0.5)
        )
    }
    
    private func updateActiveCellCount() {
        activeCells = cells.count
    }
    
    // MARK: - Optimization
    
    public func optimize() {
        let currentTime = CACurrentMediaTime()
        
        // Only optimize every few seconds
        if currentTime - lastOptimizationTime < 5.0 {
            return
        }
        
        // Remove empty cells
        let emptyKeys = cells.compactMap { key, value in
            value.isEmpty ? key : nil
        }
        
        for key in emptyKeys {
            cells.removeValue(forKey: key)
            totalCells -= 1
        }
        
        updateActiveCellCount()
        lastOptimizationTime = currentTime
        
        logDebug("Spatial grid optimized", category: .general, context: LogContext(customData: [
            "removed_empty_cells": emptyKeys.count,
            "active_cells": activeCells,
            "total_cells": totalCells
        ]))
    }
    
    // MARK: - Statistics
    
    public func getActiveCellCount() -> Int {
        return activeCells
    }
    
    public func getTotalCellCount() -> Int {
        return totalCells
    }
    
    public func getStatistics() -> SpatialGridStatistics {
        var entityCount = 0
        var staticColliderCount = 0
        
        for cell in cells.values {
            entityCount += cell.entities.count
            staticColliderCount += cell.staticColliders.count
        }
        
        return SpatialGridStatistics(
            activeCells: activeCells,
            totalCells: totalCells,
            totalEntities: entityCount,
            totalStaticColliders: staticColliderCount,
            cellSize: cellSize
        )
    }
}

// MARK: - Supporting Types

public struct GridCell: Hashable {
    public let x: Int
    public let y: Int
    public let z: Int
    
    public init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public class SpatialCell {
    public var entities: Set<UUID> = []
    public var staticColliders: Set<UUID> = []
    
    public var isEmpty: Bool {
        return entities.isEmpty && staticColliders.isEmpty
    }
    
    public init() {}
}

public struct SpatialGridStatistics {
    public let activeCells: Int
    public let totalCells: Int
    public let totalEntities: Int
    public let totalStaticColliders: Int
    public let cellSize: Float
    
    public init(activeCells: Int, totalCells: Int, totalEntities: Int, totalStaticColliders: Int, cellSize: Float) {
        self.activeCells = activeCells
        self.totalCells = totalCells
        self.totalEntities = totalEntities
        self.totalStaticColliders = totalStaticColliders
        self.cellSize = cellSize
    }
}