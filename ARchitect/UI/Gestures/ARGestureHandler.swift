import SwiftUI
import RealityKit
import ARKit
import simd

// MARK: - AR Gesture Handler

@MainActor
public class ARGestureHandler: ObservableObject {
    
    // MARK: - Properties
    @Published public var currentGesture: GestureType?
    @Published public var selectedEntity: Entity?
    @Published public var manipulationMode: ManipulationMode = .none
    
    // Gesture state
    private var initialTransform: Transform?
    private var initialDistance: Float = 0
    private var initialRotation: Float = 0
    private var gestureStartTime: Date?
    
    // Configuration
    private let minimumMovementThreshold: Float = 0.001 // 1mm
    private let rotationSensitivity: Float = 2.0
    private let scaleSensitivity: Float = 1.5
    private let snapAngle: Float = 15.0 // degrees
    
    // Dependencies
    private let hapticFeedback = HapticFeedbackManager.shared
    private let physicsIntegration: PhysicsIntegration?
    
    // Accessibility
    @Published public var gestureDescription = ""
    
    public init(physicsIntegration: PhysicsIntegration? = nil) {
        self.physicsIntegration = physicsIntegration
        
        logDebug("AR gesture handler initialized", category: .general)
    }
    
    // MARK: - Gesture Recognition
    
    public func handleTapGesture(at location: CGPoint, in arView: ARView) {
        let hitResults = arView.hitTest(location)
        
        if let hitResult = hitResults.first {
            selectEntity(hitResult.entity)
            hapticFeedback.impact(.light)
            
            announceSelection(hitResult.entity)
            
            logDebug("Entity tapped", category: .general, context: LogContext(customData: [
                "entity_name": hitResult.entity.name
            ]))
        } else {
            // Tap on empty space - deselect
            deselectEntity()
        }
    }
    
    public func handlePanGesture(_ gesture: DragGesture.Value, in arView: ARView) {
        guard let entity = selectedEntity,
              manipulationMode == .move else { return }
        
        // Convert screen coordinates to world space
        let screenPoint = gesture.location
        let worldPosition = screenToWorldPosition(screenPoint, in: arView, relativeTo: entity)
        
        if gestureStartTime == nil {
            startGesture(.pan)
            initialTransform = entity.transform
        }
        
        moveEntity(entity, to: worldPosition)
        
        // Update gesture description for accessibility
        gestureDescription = "Moving object to new position"
    }
    
    public func handlePanGestureEnded(_ gesture: DragGesture.Value) {
        guard currentGesture == .pan else { return }
        
        endGesture()
        
        // Snap to surfaces if physics integration is available
        if let entity = selectedEntity,
           let physics = physicsIntegration {
            Task {
                await attemptSurfaceSnapping(entity: entity, physics: physics)
            }
        }
        
        hapticFeedback.impact(.medium)
        gestureDescription = "Object moved"
        announceAction("Object moved to new position")
    }
    
    public func handleRotationGesture(_ gesture: RotationGesture.Value, in arView: ARView) {
        guard let entity = selectedEntity,
              manipulationMode == .rotate else { return }
        
        if gestureStartTime == nil {
            startGesture(.rotation)
            initialTransform = entity.transform
            initialRotation = 0
        }
        
        let rotationDelta = Float(gesture.rotation - Double(initialRotation)) * rotationSensitivity
        rotateEntity(entity, by: rotationDelta)
        
        initialRotation = Float(gesture.rotation)
        gestureDescription = "Rotating object \(Int(rotationDelta * 180 / .pi)) degrees"
    }
    
    public func handleRotationGestureEnded(_ gesture: RotationGesture.Value) {
        guard currentGesture == .rotation else { return }
        
        endGesture()
        
        // Snap to angle increments
        if let entity = selectedEntity {
            snapToAngle(entity)
        }
        
        hapticFeedback.impact(.medium)
        gestureDescription = "Object rotated"
        announceAction("Object rotated")
    }
    
    public func handleMagnificationGesture(_ gesture: MagnificationGesture.Value, in arView: ARView) {
        guard let entity = selectedEntity,
              manipulationMode == .scale else { return }
        
        if gestureStartTime == nil {
            startGesture(.magnification)
            initialTransform = entity.transform
            initialDistance = 1.0
        }
        
        let scaleFactor = Float(gesture.magnitude / Double(initialDistance)) * scaleSensitivity
        scaleEntity(entity, by: scaleFactor)
        
        initialDistance = Float(gesture.magnitude)
        gestureDescription = "Scaling object \(Int(scaleFactor * 100))%"
    }
    
    public func handleMagnificationGestureEnded(_ gesture: MagnificationGesture.Value) {
        guard currentGesture == .magnification else { return }
        
        endGesture()
        hapticFeedback.impact(.medium)
        gestureDescription = "Object scaled"
        announceAction("Object scaled")
    }
    
    // MARK: - Long Press Gestures
    
    public func handleLongPressGesture(at location: CGPoint, in arView: ARView) {
        let hitResults = arView.hitTest(location)
        
        if let hitResult = hitResults.first {
            selectEntity(hitResult.entity)
            showContextMenu(for: hitResult.entity, at: location)
            
            hapticFeedback.impact(.heavy)
            announceAction("Context menu opened for \(hitResult.entity.name)")
            
            logDebug("Long press on entity", category: .general, context: LogContext(customData: [
                "entity_name": hitResult.entity.name
            ]))
        }
    }
    
    // MARK: - Multi-touch Gestures
    
    public func handleTwoFingerPan(_ gesture: DragGesture.Value, in arView: ARView) {
        guard let entity = selectedEntity else { return }
        
        if gestureStartTime == nil {
            startGesture(.twoFingerPan)
            initialTransform = entity.transform
        }
        
        // Two-finger pan for vertical movement
        let verticalMovement = Float(gesture.translation.y) * -0.001 // Invert Y and scale
        moveEntityVertically(entity, by: verticalMovement)
        
        gestureDescription = "Moving object vertically"
    }
    
    public func handleTwoFingerPanEnded(_ gesture: DragGesture.Value) {
        guard currentGesture == .twoFingerPan else { return }
        
        endGesture()
        hapticFeedback.impact(.medium)
        gestureDescription = "Object moved vertically"
        announceAction("Object moved vertically")
    }
    
    // MARK: - Entity Manipulation
    
    private func selectEntity(_ entity: Entity) {
        // Deselect previous entity
        if let previousEntity = selectedEntity {
            removeSelectionHighlight(from: previousEntity)
        }
        
        selectedEntity = entity
        addSelectionHighlight(to: entity)
        
        // Enable manipulation mode
        manipulationMode = .move
        
        logDebug("Entity selected", category: .general, context: LogContext(customData: [
            "entity_id": entity.id.uuidString,
            "entity_name": entity.name
        ]))
    }
    
    private func deselectEntity() {
        if let entity = selectedEntity {
            removeSelectionHighlight(from: entity)
        }
        
        selectedEntity = nil
        manipulationMode = .none
        currentGesture = nil
        
        announceAction("Object deselected")
        
        logDebug("Entity deselected", category: .general)
    }
    
    private func moveEntity(_ entity: Entity, to position: SIMD3<Float>) {
        guard simd_distance(entity.position, position) > minimumMovementThreshold else { return }
        
        entity.position = position
        
        // Update physics if available
        if let physics = physicsIntegration {
            Task {
                // Update physics body position
                // await physics.updateEntityPosition(entity.id, position: position)
            }
        }
    }
    
    private func moveEntityVertically(_ entity: Entity, by delta: Float) {
        guard abs(delta) > minimumMovementThreshold else { return }
        
        entity.position.y += delta
        
        // Constrain to reasonable bounds
        entity.position.y = max(-2.0, min(3.0, entity.position.y))
    }
    
    private func rotateEntity(_ entity: Entity, by angle: Float) {
        let rotation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        entity.orientation = entity.orientation * rotation
    }
    
    private func scaleEntity(_ entity: Entity, by factor: Float) {
        // Constrain scale factor to reasonable bounds
        let constrainedFactor = max(0.1, min(5.0, factor))
        
        if let initialTransform = initialTransform {
            entity.scale = initialTransform.scale * constrainedFactor
        }
    }
    
    private func snapToAngle(_ entity: Entity) {
        // Get current Y rotation
        let currentRotation = entity.orientation
        let euler = currentRotation.eulerAngles
        
        // Snap to nearest increment
        let snapRadians = snapAngle * .pi / 180
        let snappedY = round(euler.y / snapRadians) * snapRadians
        
        // Apply snapped rotation
        entity.orientation = simd_quatf(angle: snappedY, axis: SIMD3<Float>(0, 1, 0))
        
        hapticFeedback.impact(.light)
    }
    
    // MARK: - Visual Feedback
    
    private func addSelectionHighlight(to entity: Entity) {
        // Create selection highlight
        let highlightEntity = Entity()
        highlightEntity.name = "selection_highlight"
        
        // Add wireframe or outline effect
        let bounds = entity.visualBounds(relativeTo: nil)
        let size = bounds.extents + SIMD3<Float>(0.02, 0.02, 0.02) // Slightly larger
        
        let mesh = MeshResource.generateBox(size: size)
        var material = SimpleMaterial()
        material.color = .init(tint: .blue.withAlphaComponent(0.3))
        material.isMetallic = false
        material.roughness = 1.0
        
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])
        highlightEntity.components.set(modelComponent)
        
        entity.addChild(highlightEntity)
        
        // Add pulsing animation
        addPulsingAnimation(to: highlightEntity)
    }
    
    private func removeSelectionHighlight(from entity: Entity) {
        if let highlight = entity.children.first(where: { $0.name == "selection_highlight" }) {
            highlight.removeFromParent()
        }
    }
    
    private func addPulsingAnimation(to entity: Entity) {
        let animation = FromToByAnimation<Transform>(
            name: "pulse",
            from: .init(scale: SIMD3<Float>(1.0, 1.0, 1.0), rotation: entity.orientation, translation: entity.position),
            to: .init(scale: SIMD3<Float>(1.05, 1.05, 1.05), rotation: entity.orientation, translation: entity.position),
            duration: 1.0,
            timing: .easeInOut,
            isAdditive: false
        )
        
        let animationResource = try? AnimationResource.generate(with: animation)
        if let resource = animationResource {
            entity.playAnimation(resource.repeat())
        }
    }
    
    // MARK: - Context Menu
    
    private func showContextMenu(for entity: Entity, at location: CGPoint) {
        // This would trigger a context menu in the UI
        // The actual menu would be handled by the AR view controller
        
        logDebug("Context menu requested", category: .general, context: LogContext(customData: [
            "entity_name": entity.name,
            "location_x": location.x,
            "location_y": location.y
        ]))
    }
    
    // MARK: - Gesture State Management
    
    private func startGesture(_ type: GestureType) {
        currentGesture = type
        gestureStartTime = Date()
        
        hapticFeedback.impact(.light)
        
        logDebug("Gesture started", category: .general, context: LogContext(customData: [
            "gesture_type": type.rawValue
        ]))
    }
    
    private func endGesture() {
        let duration = Date().timeIntervalSince(gestureStartTime ?? Date())
        
        logDebug("Gesture ended", category: .general, context: LogContext(customData: [
            "gesture_type": currentGesture?.rawValue ?? "unknown",
            "duration": duration
        ]))
        
        currentGesture = nil
        gestureStartTime = nil
        initialTransform = nil
    }
    
    // MARK: - Coordinate Conversion
    
    private func screenToWorldPosition(_ screenPoint: CGPoint, in arView: ARView, relativeTo entity: Entity) -> SIMD3<Float> {
        // Perform ray casting from screen point
        let raycastQuery = arView.makeRaycastQuery(from: screenPoint, allowing: .existingPlaneGeometry, alignment: .any)
        
        if let raycastResult = arView.session.raycast(raycastQuery).first {
            return SIMD3<Float>(raycastResult.worldTransform.columns.3.x,
                               raycastResult.worldTransform.columns.3.y,
                               raycastResult.worldTransform.columns.3.z)
        }
        
        // Fallback: project to same depth as entity
        let entityDistance = simd_length(entity.position)
        let camera = arView.cameraTransform
        let forward = -normalize(SIMD3<Float>(camera.matrix.columns.2.x, camera.matrix.columns.2.y, camera.matrix.columns.2.z))
        
        return camera.translation + forward * entityDistance
    }
    
    // MARK: - Surface Snapping
    
    private func attemptSurfaceSnapping(entity: Entity, physics: PhysicsIntegration) async {
        // Attempt to snap to floor first
        let floorSnapped = await physics.snapFurnitureToFloor(entity.id)
        
        if floorSnapped {
            hapticFeedback.notification(.success)
            announceAction("Object snapped to floor")
            return
        }
        
        // Try wall snapping
        let wallSnapped = await physics.snapFurnitureToWall(entity.id)
        
        if wallSnapped {
            hapticFeedback.notification(.success)
            announceAction("Object snapped to wall")
        }
    }
    
    // MARK: - Accessibility
    
    private func announceSelection(_ entity: Entity) {
        announceAction("Selected \(entity.name)")
    }
    
    private func announceAction(_ message: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
    
    // MARK: - Public API
    
    public func setManipulationMode(_ mode: ManipulationMode) {
        manipulationMode = mode
        
        let modeDescription = switch mode {
        case .none: "Manipulation disabled"
        case .move: "Move mode activated"
        case .rotate: "Rotate mode activated"
        case .scale: "Scale mode activated"
        }
        
        announceAction(modeDescription)
        
        logDebug("Manipulation mode changed", category: .general, context: LogContext(customData: [
            "mode": mode.rawValue
        ]))
    }
    
    public func cancelCurrentGesture() {
        if let entity = selectedEntity,
           let initialTransform = initialTransform {
            // Restore original transform
            entity.transform = initialTransform
        }
        
        endGesture()
        announceAction("Gesture cancelled")
    }
}

// MARK: - Supporting Types

public enum GestureType: String {
    case tap = "tap"
    case pan = "pan"
    case rotation = "rotation"
    case magnification = "magnification"
    case longPress = "long_press"
    case twoFingerPan = "two_finger_pan"
}

public enum ManipulationMode: String {
    case none = "none"
    case move = "move"
    case rotate = "rotate"
    case scale = "scale"
    
    public var description: String {
        switch self {
        case .none: return "None"
        case .move: return "Move"
        case .rotate: return "Rotate"
        case .scale: return "Scale"
        }
    }
}

// MARK: - Gesture Modifier

public struct ARGestureModifier: ViewModifier {
    let arView: ARView
    let gestureHandler: ARGestureHandler
    
    public func body(content: Content) -> some View {
        content
            .onTapGesture { location in
                gestureHandler.handleTapGesture(at: location, in: arView)
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        gestureHandler.handlePanGesture(value, in: arView)
                    }
                    .onEnded { value in
                        gestureHandler.handlePanGestureEnded(value)
                    }
            )
            .gesture(
                RotationGesture()
                    .onChanged { value in
                        gestureHandler.handleRotationGesture(value, in: arView)
                    }
                    .onEnded { value in
                        gestureHandler.handleRotationGestureEnded(value)
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        gestureHandler.handleMagnificationGesture(value, in: arView)
                    }
                    .onEnded { value in
                        gestureHandler.handleMagnificationGestureEnded(value)
                    }
            )
            .onLongPressGesture(perform: { location in
                gestureHandler.handleLongPressGesture(at: location, in: arView)
            })
    }
}

// MARK: - Extensions

extension View {
    public func arGestures(arView: ARView, gestureHandler: ARGestureHandler) -> some View {
        self.modifier(ARGestureModifier(arView: arView, gestureHandler: gestureHandler))
    }
}

extension simd_quatf {
    var eulerAngles: SIMD3<Float> {
        let w = self.vector.w
        let x = self.vector.x
        let y = self.vector.y
        let z = self.vector.z
        
        let yaw = atan2(2 * (w * y + x * z), 1 - 2 * (y * y + x * x))
        let pitch = asin(2 * (w * x - y * z))
        let roll = atan2(2 * (w * z + x * y), 1 - 2 * (x * x + z * z))
        
        return SIMD3<Float>(pitch, yaw, roll)
    }
}