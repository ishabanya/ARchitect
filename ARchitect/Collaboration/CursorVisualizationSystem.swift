import Foundation
import RealityKit
import ARKit
import simd
import Combine

// MARK: - Collaborative Cursor and Selection Visualization

@MainActor
public class CursorVisualizationSystem: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var activeCursors: [UserCursor] = []
    @Published public var activeSelections: [UserSelection] = []
    @Published public var isVisualizationEnabled: Bool = true
    @Published public var cursorOpacity: Float = 0.8
    
    // MARK: - Private Properties
    private let arView: ARView
    private let entityManager: CursorEntityManager
    private let animationController: CursorAnimationController
    private let selectionHighlighter: SelectionHighlighter
    
    private var cursorEntities: [UUID: Entity] = [:]
    private var selectionEntities: [UUID: Entity] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    private let maxCursorAge: TimeInterval = 30.0
    private let cursorUpdateInterval: TimeInterval = 0.1
    private let selectionPulseSpeed: Float = 2.0
    
    public init(arView: ARView) {
        self.arView = arView
        self.entityManager = CursorEntityManager()
        self.animationController = CursorAnimationController()
        self.selectionHighlighter = SelectionHighlighter()
        
        setupObservers()
        setupCleanupTimer()
        
        logDebug("Cursor visualization system initialized", category: .collaboration)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        $isVisualizationEnabled
            .sink { [weak self] enabled in
                self?.toggleVisualization(enabled)
            }
            .store(in: &cancellables)
        
        $cursorOpacity
            .sink { [weak self] opacity in
                self?.updateCursorOpacity(opacity)
            }
            .store(in: &cancellables)
    }
    
    private func setupCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupOldCursors()
            }
        }
    }
    
    // MARK: - Cursor Management
    
    public func updateUserCursor(
        userId: UUID,
        position: SIMD3<Float>,
        targetObject: UUID?,
        userName: String,
        userColor: Color
    ) {
        
        // Update or create cursor data
        if let existingIndex = activeCursors.firstIndex(where: { $0.userId == userId }) {
            var cursor = activeCursors[existingIndex]
            cursor.position = position
            cursor.targetObject = targetObject
            cursor.lastUpdate = Date()
            activeCursors[existingIndex] = cursor
        } else {
            let newCursor = UserCursor(
                id: UUID(),
                userId: userId,
                userName: userName,
                userColor: userColor,
                position: position,
                targetObject: targetObject,
                lastUpdate: Date(),
                isActive: true
            )
            activeCursors.append(newCursor)
        }
        
        // Update visual representation
        updateCursorVisualization(userId: userId)
    }
    
    public func removeUserCursor(userId: UUID) {
        activeCursors.removeAll { $0.userId == userId }
        removeCursorVisualization(userId: userId)
    }
    
    public func updateUserSelection(
        userId: UUID,
        selectedObjects: [UUID],
        selectionType: SelectionType,
        userName: String,
        userColor: Color
    ) {
        
        // Remove existing selection
        activeSelections.removeAll { $0.userId == userId }
        
        // Add new selection if objects are selected
        if !selectedObjects.isEmpty {
            let selection = UserSelection(
                id: UUID(),
                userId: userId,
                userName: userName,
                userColor: userColor,
                selectedObjects: selectedObjects,
                selectionType: selectionType,
                timestamp: Date()
            )
            activeSelections.append(selection)
        }
        
        // Update visual representation
        updateSelectionVisualization(userId: userId)
    }
    
    // MARK: - Visualization Updates
    
    private func updateCursorVisualization(userId: UUID) {
        guard isVisualizationEnabled,
              let cursor = activeCursors.first(where: { $0.userId == userId }) else {
            removeCursorVisualization(userId: userId)
            return
        }
        
        // Create or update cursor entity
        if let existingEntity = cursorEntities[userId] {
            updateCursorEntity(existingEntity, with: cursor)
        } else {
            let cursorEntity = createCursorEntity(for: cursor)
            cursorEntities[userId] = cursorEntity
            arView.scene.addAnchor(AnchorEntity(world: cursor.position))
            if let anchor = arView.scene.anchors.last {
                anchor.addChild(cursorEntity)
            }
        }
    }
    
    private func updateSelectionVisualization(userId: UUID) {
        guard isVisualizationEnabled else {
            removeSelectionVisualization(userId: userId)
            return
        }
        
        // Remove existing selection visualization
        removeSelectionVisualization(userId: userId)
        
        // Create new selection visualization if user has selections
        if let selection = activeSelections.first(where: { $0.userId == userId }) {
            for objectId in selection.selectedObjects {
                if let objectEntity = findObjectEntity(objectId) {
                    let highlightEntity = createSelectionHighlight(
                        for: objectEntity,
                        selection: selection
                    )
                    
                    if selectionEntities[userId] == nil {
                        selectionEntities[userId] = Entity()
                        arView.scene.addAnchor(AnchorEntity())
                        if let anchor = arView.scene.anchors.last {
                            anchor.addChild(selectionEntities[userId]!)
                        }
                    }
                    
                    selectionEntities[userId]?.addChild(highlightEntity)
                }
            }
        }
    }
    
    // MARK: - Entity Creation
    
    private func createCursorEntity(for cursor: UserCursor) -> Entity {
        let cursorEntity = entityManager.createCursor(
            userId: cursor.userId,
            userName: cursor.userName,
            userColor: cursor.userColor,
            cursorType: determineCursorType(for: cursor)
        )
        
        // Set initial position and properties
        cursorEntity.position = cursor.position
        cursorEntity.transform.scale = SIMD3<Float>(0.02, 0.02, 0.02)
        
        // Add floating animation
        animationController.addFloatingAnimation(to: cursorEntity)
        
        // Add name label
        if let labelEntity = createNameLabel(for: cursor) {
            cursorEntity.addChild(labelEntity)
        }
        
        return cursorEntity
    }
    
    private func createSelectionHighlight(
        for objectEntity: Entity,
        selection: UserSelection
    ) -> Entity {
        
        let highlightEntity = selectionHighlighter.createHighlight(
            for: objectEntity,
            userColor: selection.userColor,
            selectionType: selection.selectionType
        )
        
        // Add pulsing animation
        animationController.addPulsingAnimation(
            to: highlightEntity,
            color: selection.userColor,
            speed: selectionPulseSpeed
        )
        
        return highlightEntity
    }
    
    private func createNameLabel(for cursor: UserCursor) -> Entity? {
        let labelEntity = Entity()
        
        // Create text mesh
        let textMesh = MeshResource.generateText(
            cursor.userName,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.05)
        )
        
        // Create material with user color
        var material = SimpleMaterial()
        material.color.tint = UIColor(cursor.userColor)
        material.isMetallic = false
        material.roughness = 0.5
        
        let textComponent = ModelComponent(mesh: textMesh, materials: [material])
        labelEntity.components.set(textComponent)
        
        // Position label above cursor
        labelEntity.position = SIMD3<Float>(0, 0.1, 0)
        
        // Make label always face camera
        let billboardComponent = BillboardComponent()
        labelEntity.components.set(billboardComponent)
        
        return labelEntity
    }
    
    // MARK: - Entity Updates
    
    private func updateCursorEntity(_ entity: Entity, with cursor: UserCursor) {
        // Smooth position transition
        let currentPosition = entity.position
        let targetPosition = cursor.position
        let distance = simd_distance(currentPosition, targetPosition)
        
        if distance > 0.01 { // Only animate if significant movement
            animationController.animatePosition(
                entity: entity,
                to: targetPosition,
                duration: cursorUpdateInterval
            )
        }
        
        // Update cursor type if targeting changed
        let newCursorType = determineCursorType(for: cursor)
        entityManager.updateCursorType(entity, type: newCursorType)
    }
    
    private func updateCursorOpacity(_ opacity: Float) {
        for entity in cursorEntities.values {
            entityManager.updateOpacity(entity, opacity: opacity)
        }
    }
    
    // MARK: - Helper Methods
    
    private func determineCursorType(for cursor: UserCursor) -> CursorType {
        if cursor.targetObject != nil {
            return .targeting
        } else {
            return .pointer
        }
    }
    
    private func findObjectEntity(_ objectId: UUID) -> Entity? {
        // Search through AR scene for entity with matching ID
        return findEntityRecursively(in: arView.scene, withId: objectId)
    }
    
    private func findEntityRecursively(in entity: Entity, withId id: UUID) -> Entity? {
        // Check if this entity has the matching ID
        if let hasId = entity.components[IdentityComponent.self], hasId.id == id {
            return entity
        }
        
        // Search children
        for child in entity.children {
            if let found = findEntityRecursively(in: child, withId: id) {
                return found
            }
        }
        
        return nil
    }
    
    private func removeCursorVisualization(userId: UUID) {
        if let entity = cursorEntities[userId] {
            entity.removeFromParent()
            cursorEntities.removeValue(forKey: userId)
        }
    }
    
    private func removeSelectionVisualization(userId: UUID) {
        if let entity = selectionEntities[userId] {
            entity.removeFromParent()
            selectionEntities.removeValue(forKey: userId)
        }
    }
    
    private func toggleVisualization(_ enabled: Bool) {
        for entity in cursorEntities.values {
            entity.isEnabled = enabled
        }
        for entity in selectionEntities.values {
            entity.isEnabled = enabled
        }
    }
    
    private func cleanupOldCursors() {
        let cutoffTime = Date().addingTimeInterval(-maxCursorAge)
        
        // Remove old cursors
        let oldCursorUserIds = activeCursors.compactMap { cursor in
            cursor.lastUpdate < cutoffTime ? cursor.userId : nil
        }
        
        for userId in oldCursorUserIds {
            removeUserCursor(userId: userId)
        }
        
        // Clean up orphaned entities
        for (userId, _) in cursorEntities {
            if !activeCursors.contains(where: { $0.userId == userId }) {
                removeCursorVisualization(userId: userId)
            }
        }
    }
    
    // MARK: - Public Interface
    
    public func setCursorVisibility(_ visible: Bool, for userId: UUID) {
        if let entity = cursorEntities[userId] {
            entity.isEnabled = visible
        }
    }
    
    public func setSelectionVisibility(_ visible: Bool, for userId: UUID) {
        if let entity = selectionEntities[userId] {
            entity.isEnabled = visible
        }
    }
    
    public func updateVisualizationSettings(_ settings: VisualizationSettings) {
        cursorOpacity = settings.cursorOpacity
        isVisualizationEnabled = settings.isEnabled
        
        // Apply other settings
        for entity in cursorEntities.values {
            entityManager.updateSettings(entity, settings: settings)
        }
    }
    
    public func getActiveCursorsCount() -> Int {
        return activeCursors.count
    }
    
    public func getActiveSelectionsCount() -> Int {
        return activeSelections.count
    }
    
    public func clearAllVisualizations() {
        for userId in cursorEntities.keys {
            removeCursorVisualization(userId: userId)
        }
        for userId in selectionEntities.keys {
            removeSelectionVisualization(userId: userId)
        }
        activeCursors.removeAll()
        activeSelections.removeAll()
    }
}

// MARK: - Supporting Data Structures

public struct UserCursor: Identifiable {
    public let id: UUID
    public let userId: UUID
    public let userName: String
    public let userColor: Color
    public var position: SIMD3<Float>
    public var targetObject: UUID?
    public var lastUpdate: Date
    public var isActive: Bool
}

public struct UserSelection: Identifiable {
    public let id: UUID
    public let userId: UUID
    public let userName: String
    public let userColor: Color
    public let selectedObjects: [UUID]
    public let selectionType: SelectionType
    public let timestamp: Date
}

public enum SelectionType {
    case single
    case multiple
    case group
    case area
}

public enum CursorType {
    case pointer
    case targeting
    case grabbing
    case resizing
    case custom(String)
    
    var meshName: String {
        switch self {
        case .pointer: return "cursor_pointer"
        case .targeting: return "cursor_target"
        case .grabbing: return "cursor_grab"
        case .resizing: return "cursor_resize"
        case .custom(let name): return name
        }
    }
}

public struct VisualizationSettings {
    public let isEnabled: Bool
    public let cursorOpacity: Float
    public let selectionOpacity: Float
    public let showNames: Bool
    public let animationSpeed: Float
    public let cursorSize: Float
    
    public static let `default` = VisualizationSettings(
        isEnabled: true,
        cursorOpacity: 0.8,
        selectionOpacity: 0.6,
        showNames: true,
        animationSpeed: 1.0,
        cursorSize: 1.0
    )
}

// MARK: - Supporting Classes

@MainActor
class CursorEntityManager {
    
    func createCursor(
        userId: UUID,
        userName: String,
        userColor: Color,
        cursorType: CursorType
    ) -> Entity {
        
        let cursorEntity = Entity()
        
        // Create cursor mesh
        let mesh = generateCursorMesh(type: cursorType)
        
        // Create material with user color
        var material = SimpleMaterial()
        material.color.tint = UIColor(userColor)
        material.isMetallic = false
        material.roughness = 0.3
        
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])
        cursorEntity.components.set(modelComponent)
        
        // Add identity component for tracking
        let identityComponent = IdentityComponent(id: userId)
        cursorEntity.components.set(identityComponent)
        
        return cursorEntity
    }
    
    func updateCursorType(_ entity: Entity, type: CursorType) {
        if var modelComponent = entity.components[ModelComponent.self] {
            modelComponent.mesh = generateCursorMesh(type: type)
            entity.components.set(modelComponent)
        }
    }
    
    func updateOpacity(_ entity: Entity, opacity: Float) {
        if var modelComponent = entity.components[ModelComponent.self] {
            for i in 0..<modelComponent.materials.count {
                if var material = modelComponent.materials[i] as? SimpleMaterial {
                    material.color.tint = material.color.tint.withAlphaComponent(CGFloat(opacity))
                    modelComponent.materials[i] = material
                }
            }
            entity.components.set(modelComponent)
        }
    }
    
    func updateSettings(_ entity: Entity, settings: VisualizationSettings) {
        entity.transform.scale *= settings.cursorSize
        updateOpacity(entity, opacity: settings.cursorOpacity)
    }
    
    private func generateCursorMesh(type: CursorType) -> MeshResource {
        switch type {
        case .pointer:
            return MeshResource.generateSphere(radius: 0.01)
        case .targeting:
            return MeshResource.generateBox(size: [0.02, 0.002, 0.02])
        case .grabbing:
            return MeshResource.generateSphere(radius: 0.015)
        case .resizing:
            return MeshResource.generateBox(size: [0.015, 0.015, 0.015])
        case .custom:
            return MeshResource.generateSphere(radius: 0.01) // Fallback
        }
    }
}

@MainActor
class CursorAnimationController {
    
    func animatePosition(entity: Entity, to position: SIMD3<Float>, duration: TimeInterval) {
        let animation = FromToByAnimation(
            from: .init(entity.position),
            to: .init(position),
            duration: duration,
            timing: .easeInOut,
            bindTarget: .transform
        )
        
        if let animationResource = try? AnimationResource.generate(with: animation) {
            entity.playAnimation(animationResource)
        }
    }
    
    func addFloatingAnimation(to entity: Entity) {
        let floatHeight: Float = 0.005
        let duration: TimeInterval = 2.0
        
        let upAnimation = FromToByAnimation(
            by: .init([0, floatHeight, 0]),
            duration: duration / 2,
            timing: .easeInOut,
            bindTarget: .transform
        )
        
        let downAnimation = FromToByAnimation(
            by: .init([0, -floatHeight, 0]),
            duration: duration / 2,
            timing: .easeInOut,
            bindTarget: .transform
        )
        
        let sequence = AnimationGroup([upAnimation, downAnimation], timing: .easeInOut)
        
        if let animationResource = try? AnimationResource.generate(with: sequence) {
            entity.playAnimation(animationResource.repeat())
        }
    }
    
    func addPulsingAnimation(to entity: Entity, color: Color, speed: Float) {
        let pulseScale: Float = 1.2
        let duration: TimeInterval = TimeInterval(1.0 / speed)
        
        let scaleUpAnimation = FromToByAnimation(
            to: .init(scale: [pulseScale, pulseScale, pulseScale]),
            duration: duration / 2,
            timing: .easeInOut,
            bindTarget: .transform
        )
        
        let scaleDownAnimation = FromToByAnimation(
            to: .init(scale: [1.0, 1.0, 1.0]),
            duration: duration / 2,
            timing: .easeInOut,
            bindTarget: .transform
        )
        
        let sequence = AnimationGroup([scaleUpAnimation, scaleDownAnimation], timing: .easeInOut)
        
        if let animationResource = try? AnimationResource.generate(with: sequence) {
            entity.playAnimation(animationResource.repeat())
        }
    }
}

@MainActor
class SelectionHighlighter {
    
    func createHighlight(
        for objectEntity: Entity,
        userColor: Color,
        selectionType: SelectionType
    ) -> Entity {
        
        let highlightEntity = Entity()
        
        // Get object bounds
        let bounds = objectEntity.visualBounds(relativeTo: nil)
        let size = bounds.max - bounds.min
        let center = (bounds.max + bounds.min) / 2
        
        // Create highlight based on selection type
        let mesh = createHighlightMesh(for: selectionType, size: size)
        
        // Create highlight material
        var material = SimpleMaterial()
        material.color.tint = UIColor(userColor).withAlphaComponent(0.3)
        material.isMetallic = false
        material.roughness = 0.8
        
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])
        highlightEntity.components.set(modelComponent)
        
        // Position highlight
        highlightEntity.position = center
        
        return highlightEntity
    }
    
    private func createHighlightMesh(for selectionType: SelectionType, size: SIMD3<Float>) -> MeshResource {
        let expandedSize = size * 1.1 // Slightly larger than object
        
        switch selectionType {
        case .single, .multiple:
            return MeshResource.generateBox(size: expandedSize, cornerRadius: 0.01)
        case .group:
            return MeshResource.generateSphere(radius: max(expandedSize.x, expandedSize.y, expandedSize.z) / 2)
        case .area:
            return MeshResource.generateBox(size: [expandedSize.x, 0.005, expandedSize.z])
        }
    }
}

// Identity component for tracking entities
struct IdentityComponent: Component {
    let id: UUID
}

extension Color {
    static let userColors: [Color] = [
        .blue, .green, .orange, .purple, .red, .yellow, .pink, .cyan
    ]
    
    static func forUser(at index: Int) -> Color {
        return userColors[index % userColors.count]
    }
}