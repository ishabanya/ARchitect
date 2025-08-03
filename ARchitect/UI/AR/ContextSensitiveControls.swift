import SwiftUI
import RealityKit
import Combine

// MARK: - Context Controls Manager

@MainActor
public class ContextControlsManager: ObservableObject {
    
    // MARK: - Properties
    @Published public var selectedObject: ARObject?
    @Published public var hasActiveSelection = false
    @Published public var manipulationMode: ManipulationMode = .none
    @Published public var isShowingContextMenu = false
    @Published public var contextMenuLocation: CGPoint = .zero
    
    // Object state
    @Published public var objectTransform: ObjectTransform?
    @Published public var objectProperties: ObjectProperties?
    @Published public var objectConstraints: ObjectConstraints?
    
    // Animation state
    @Published public var selectionAnimationProgress: Double = 0.0
    @Published public var transformFeedbackVisible = false
    
    // Configuration
    public var enableSmartSnapping = true
    public var enableCollisionDetection = true
    public var showTransformFeedback = true
    
    private let hapticFeedback = HapticFeedbackManager.shared
    private let accessibilityManager = AccessibilityManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var transformUpdateTimer: Timer?
    
    public init() {
        setupObservers()
        
        logDebug("Context controls manager initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Monitor selection changes
        $selectedObject
            .sink { [weak self] object in
                self?.handleSelectionChange(object)
            }
            .store(in: &cancellables)
        
        // Monitor manipulation mode changes
        $manipulationMode
            .sink { [weak self] mode in
                self?.handleManipulationModeChange(mode)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Selection Management
    
    public func updateSelection(_ object: ARObject?) {
        guard selectedObject?.id != object?.id else { return }
        
        selectedObject = object
        hasActiveSelection = object != nil
        
        if let object = object {
            loadObjectProperties(object)
            startSelectionAnimation()
        } else {
            clearSelection()
        }
    }
    
    private func handleSelectionChange(_ object: ARObject?) {
        if let object = object {
            // Object selected
            hapticFeedback.objectSelected()
            accessibilityManager.announceObjectSelection(object.name)
            
            // Reset manipulation mode
            manipulationMode = .none
            
            logDebug("Object selected", category: .general, context: LogContext(customData: [
                "object_id": object.id.uuidString,
                "object_name": object.name,
                "object_type": object.type
            ]))
        } else {
            // Object deselected
            manipulationMode = .none
            accessibilityManager.announce("Object deselected", priority: .normal)
            
            logDebug("Object deselected", category: .general)
        }
    }
    
    private func clearSelection() {
        objectTransform = nil
        objectProperties = nil
        objectConstraints = nil
        stopTransformUpdateTimer()
        hideTransformFeedback()
    }
    
    private func loadObjectProperties(_ object: ARObject) {
        // Load object properties from the AR system
        objectProperties = ObjectProperties(
            name: object.name,
            type: object.type,
            material: "Wood", // This would come from the actual object
            dimensions: SIMD3<Float>(1.0, 1.0, 1.0),
            mass: 10.0,
            isLocked: false,
            isVisible: true
        )
        
        objectTransform = ObjectTransform(
            position: object.position,
            rotation: SIMD3<Float>(0, 0, 0),
            scale: SIMD3<Float>(1, 1, 1)
        )
        
        objectConstraints = ObjectConstraints(
            canMove: true,
            canRotate: true,
            canScale: true,
            snapToSurfaces: enableSmartSnapping,
            respectCollisions: enableCollisionDetection
        )
    }
    
    // MARK: - Manipulation Modes
    
    public func enterMoveMode() {
        guard hasActiveSelection else { return }
        
        manipulationMode = .move
        hapticFeedback.impact(.light)
        accessibilityManager.announce("Move mode activated", priority: .normal)
        
        startTransformUpdateTimer()
        showTransformFeedback()
    }
    
    public func enterRotateMode() {
        guard hasActiveSelection else { return }
        
        manipulationMode = .rotate
        hapticFeedback.impact(.light)
        accessibilityManager.announce("Rotate mode activated", priority: .normal)
        
        startTransformUpdateTimer()
        showTransformFeedback()
    }
    
    public func enterScaleMode() {
        guard hasActiveSelection else { return }
        
        manipulationMode = .scale
        hapticFeedback.impact(.light)
        accessibilityManager.announce("Scale mode activated", priority: .normal)
        
        startTransformUpdateTimer()
        showTransformFeedback()
    }
    
    public func exitManipulationMode() {
        manipulationMode = .none
        stopTransformUpdateTimer()
        hideTransformFeedback()
        
        accessibilityManager.announce("Manipulation mode exited", priority: .normal)
    }
    
    private func handleManipulationModeChange(_ mode: ManipulationMode) {
        if mode == .none {
            stopTransformUpdateTimer()
            hideTransformFeedback()
        }
        
        logDebug("Manipulation mode changed", category: .general, context: LogContext(customData: [
            "mode": mode.rawValue
        ]))
    }
    
    // MARK: - Object Actions
    
    public func duplicateObject() {
        guard let object = selectedObject else { return }
        
        hapticFeedback.objectPlaced()
        accessibilityManager.announce("Object duplicated", priority: .normal)
        
        // Create duplicate action
        let duplicateAction = ContextAction(
            type: .duplicate,
            object: object,
            timestamp: Date()
        )
        
        executeAction(duplicateAction)
        
        logDebug("Object duplicated", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString
        ]))
    }
    
    public func deleteObject() {
        guard let object = selectedObject else { return }
        
        hapticFeedback.impact(.heavy)
        accessibilityManager.announce("Object deleted", priority: .normal)
        
        // Create delete action
        let deleteAction = ContextAction(
            type: .delete,
            object: object,
            timestamp: Date()
        )
        
        executeAction(deleteAction)
        
        // Clear selection
        updateSelection(nil)
        
        logDebug("Object deleted", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString
        ]))
    }
    
    public func lockObject() {
        guard let object = selectedObject else { return }
        
        objectProperties?.isLocked.toggle()
        
        let isLocked = objectProperties?.isLocked ?? false
        hapticFeedback.impact(.medium)
        accessibilityManager.announce(isLocked ? "Object locked" : "Object unlocked", priority: .normal)
        
        logDebug("Object lock toggled", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString,
            "is_locked": isLocked
        ]))
    }
    
    public func toggleObjectVisibility() {
        guard let object = selectedObject else { return }
        
        objectProperties?.isVisible.toggle()
        
        let isVisible = objectProperties?.isVisible ?? true
        hapticFeedback.impact(.light)
        accessibilityManager.announce(isVisible ? "Object shown" : "Object hidden", priority: .normal)
        
        logDebug("Object visibility toggled", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString,
            "is_visible": isVisible
        ]))
    }
    
    // MARK: - Context Menu
    
    public func showContextMenu(at location: CGPoint) {
        guard hasActiveSelection else { return }
        
        contextMenuLocation = location
        isShowingContextMenu = true
        
        hapticFeedback.impact(.medium)
        accessibilityManager.announce("Context menu opened", priority: .normal)
        
        // Auto-hide after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.isShowingContextMenu {
                self.hideContextMenu()
            }
        }
        
        logDebug("Context menu shown", category: .general, context: LogContext(customData: [
            "location_x": location.x,
            "location_y": location.y
        ]))
    }
    
    public func hideContextMenu() {
        isShowingContextMenu = false
        accessibilityManager.announce("Context menu closed", priority: .normal)
    }
    
    // MARK: - Transform Feedback
    
    private func showTransformFeedback() {
        guard showTransformFeedback else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            transformFeedbackVisible = true
        }
    }
    
    private func hideTransformFeedback() {
        withAnimation(.easeInOut(duration: 0.2)) {
            transformFeedbackVisible = false
        }
    }
    
    private func startTransformUpdateTimer() {
        stopTransformUpdateTimer()
        
        transformUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.updateTransformFeedback()
        }
    }
    
    private func stopTransformUpdateTimer() {
        transformUpdateTimer?.invalidate()
        transformUpdateTimer = nil
    }
    
    private func updateTransformFeedback() {
        // Update transform values from AR system
        // This would get real values from the selected object
        if let selectedObject = selectedObject {
            objectTransform = ObjectTransform(
                position: selectedObject.position, // Would get current position
                rotation: SIMD3<Float>(0, 0, 0), // Would get current rotation
                scale: SIMD3<Float>(1, 1, 1) // Would get current scale
            )
        }
    }
    
    // MARK: - Animation
    
    private func startSelectionAnimation() {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectionAnimationProgress = 1.0
        }
        
        // Reset after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.selectionAnimationProgress = 0.0
            }
        }
    }
    
    // MARK: - Action Execution
    
    private func executeAction(_ action: ContextAction) {
        // Execute the action in the AR system
        // This would interface with RealityKit/ARKit
        
        logDebug("Context action executed", category: .general, context: LogContext(customData: [
            "action_type": action.type.rawValue,
            "object_id": action.object.id.uuidString
        ]))
    }
    
    // MARK: - Smart Features
    
    public func suggestActions(for object: ARObject) -> [SuggestedAction] {
        var suggestions: [SuggestedAction] = []
        
        // Add type-specific suggestions
        switch object.type.lowercased() {
        case "chair", "sofa":
            suggestions.append(SuggestedAction(
                title: "Rotate to face table",
                icon: "rotate.right",
                action: { self.autoOrientToNearbyFurniture() }
            ))
            
        case "table":
            suggestions.append(SuggestedAction(
                title: "Center in room",
                icon: "target",
                action: { self.centerInRoom() }
            ))
            
        case "lamp", "light":
            suggestions.append(SuggestedAction(
                title: "Optimize lighting",
                icon: "lightbulb",
                action: { self.optimizeLighting() }
            ))
            
        default:
            break
        }
        
        // Add universal suggestions
        suggestions.append(SuggestedAction(
            title: "Snap to surface",
            icon: "arrow.down.to.line",
            action: { self.snapToNearestSurface() }
        ))
        
        return suggestions
    }
    
    private func autoOrientToNearbyFurniture() {
        // Auto-orient object to face nearby furniture
        hapticFeedback.surfaceSnapped()
        accessibilityManager.announce("Object oriented to nearby furniture", priority: .normal)
    }
    
    private func centerInRoom() {
        // Center object in the room
        hapticFeedback.surfaceSnapped()
        accessibilityManager.announce("Object centered in room", priority: .normal)
    }
    
    private func optimizeLighting() {
        // Optimize lighting placement
        hapticFeedback.surfaceSnapped()
        accessibilityManager.announce("Lighting optimized", priority: .normal)
    }
    
    private func snapToNearestSurface() {
        // Snap to nearest surface
        hapticFeedback.surfaceSnapped()
        accessibilityManager.announce("Object snapped to surface", priority: .normal)
    }
}

// MARK: - Context Sensitive Controls View

public struct ContextSensitiveControls: View {
    @EnvironmentObject private var contextManager: ContextControlsManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init() {}
    
    public var body: some View {
        Group {
            if contextManager.hasActiveSelection {
                VStack(spacing: 16) {
                    // Object info header
                    ObjectInfoHeader()
                    
                    // Manipulation controls
                    ManipulationControls()
                    
                    // Transform feedback
                    if contextManager.transformFeedbackVisible {
                        TransformFeedback()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Smart suggestions
                    if let object = contextManager.selectedObject {
                        SmartSuggestions(object: object)
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .scaleEffect(contextManager.selectionAnimationProgress > 0 ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: contextManager.selectionAnimationProgress)
            }
        }
    }
}

// MARK: - Object Info Header

private struct ObjectInfoHeader: View {
    @EnvironmentObject private var contextManager: ContextControlsManager
    
    var body: some View {
        if let object = contextManager.selectedObject,
           let properties = contextManager.objectProperties {
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(object.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 8) {
                        Text(object.type)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let material = properties.material {
                            Text("• \(material)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if properties.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Spacer()
                
                // Quick actions
                HStack(spacing: 8) {
                    Button(action: { contextManager.lockObject() }) {
                        Image(systemName: properties.isLocked ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(properties.isLocked ? .orange : .primary)
                    }
                    .accessibilityLabel(properties.isLocked ? "Unlock object" : "Lock object")
                    
                    Button(action: { contextManager.toggleObjectVisibility() }) {
                        Image(systemName: properties.isVisible ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(properties.isVisible ? .primary : .gray)
                    }
                    .accessibilityLabel(properties.isVisible ? "Hide object" : "Show object")
                }
            }
        }
    }
}

// MARK: - Manipulation Controls

private struct ManipulationControls: View {
    @EnvironmentObject private var contextManager: ContextControlsManager
    
    var body: some View {
        HStack(spacing: 12) {
            ManipulationButton(
                mode: .move,
                icon: "move.3d",
                title: "Move",
                isActive: contextManager.manipulationMode == .move
            ) {
                contextManager.enterMoveMode()
            }
            
            ManipulationButton(
                mode: .rotate,
                icon: "rotate.3d",
                title: "Rotate",
                isActive: contextManager.manipulationMode == .rotate
            ) {
                contextManager.enterRotateMode()
            }
            
            ManipulationButton(
                mode: .scale,
                icon: "scale.3d",
                title: "Scale",
                isActive: contextManager.manipulationMode == .scale
            ) {
                contextManager.enterScaleMode()
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 8) {
                ActionButton(
                    icon: "doc.on.doc.fill",
                    color: .blue,
                    action: { contextManager.duplicateObject() }
                )
                .accessibilityLabel("Duplicate object")
                
                ActionButton(
                    icon: "trash.fill",
                    color: .red,
                    action: { contextManager.deleteObject() }
                )
                .accessibilityLabel("Delete object")
            }
        }
    }
}

// MARK: - Manipulation Button

private struct ManipulationButton: View {
    let mode: ManipulationMode
    let icon: String
    let title: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isActive ? .white : .primary)
                
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isActive ? .white : .primary)
            }
            .frame(width: 60, height: 50)
            .background(isActive ? .blue : .clear, in: RoundedRectangle(cornerRadius: 12))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("\(title) mode")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(color, in: Circle())
        }
    }
}

// MARK: - Transform Feedback

private struct TransformFeedback: View {
    @EnvironmentObject private var contextManager: ContextControlsManager
    
    var body: some View {
        if let transform = contextManager.objectTransform {
            VStack(spacing: 8) {
                Text("Transform")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    TransformValue(label: "X", value: transform.position.x, unit: "m")
                    TransformValue(label: "Y", value: transform.position.y, unit: "m")
                    TransformValue(label: "Z", value: transform.position.z, unit: "m")
                }
                .font(.caption)
                .monospacedDigit()
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Transform Value

private struct TransformValue: View {
    let label: String
    let value: Float
    let unit: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(String(format: "%.2f%@", value, unit))
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Smart Suggestions

private struct SmartSuggestions: View {
    let object: ARObject
    @EnvironmentObject private var contextManager: ContextControlsManager
    
    var body: some View {
        let suggestions = contextManager.suggestActions(for: object)
        
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggestions")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(suggestions, id: \.title) { suggestion in
                        SuggestionButton(suggestion: suggestion)
                    }
                }
            }
        }
    }
}

// MARK: - Suggestion Button

private struct SuggestionButton: View {
    let suggestion: SuggestedAction
    
    var body: some View {
        Button(action: suggestion.action) {
            HStack(spacing: 6) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
                
                Text(suggestion.title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(suggestion.title)
    }
}

// MARK: - Supporting Types

public enum ManipulationMode: String {
    case none = "none"
    case move = "move"
    case rotate = "rotate"
    case scale = "scale"
}

public struct ObjectTransform {
    public var position: SIMD3<Float>
    public var rotation: SIMD3<Float>
    public var scale: SIMD3<Float>
    
    public init(position: SIMD3<Float>, rotation: SIMD3<Float>, scale: SIMD3<Float>) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

public struct ObjectProperties {
    public var name: String
    public var type: String
    public var material: String?
    public var dimensions: SIMD3<Float>
    public var mass: Float
    public var isLocked: Bool
    public var isVisible: Bool
    
    public init(name: String, type: String, material: String? = nil, dimensions: SIMD3<Float>, mass: Float, isLocked: Bool, isVisible: Bool) {
        self.name = name
        self.type = type
        self.material = material
        self.dimensions = dimensions
        self.mass = mass
        self.isLocked = isLocked
        self.isVisible = isVisible
    }
}

public struct ObjectConstraints {
    public var canMove: Bool
    public var canRotate: Bool
    public var canScale: Bool
    public var snapToSurfaces: Bool
    public var respectCollisions: Bool
    
    public init(canMove: Bool, canRotate: Bool, canScale: Bool, snapToSurfaces: Bool, respectCollisions: Bool) {
        self.canMove = canMove
        self.canRotate = canRotate
        self.canScale = canScale
        self.snapToSurfaces = snapToSurfaces
        self.respectCollisions = respectCollisions
    }
}

public struct ContextAction {
    public let type: ContextActionType
    public let object: ARObject
    public let timestamp: Date
    
    public init(type: ContextActionType, object: ARObject, timestamp: Date) {
        self.type = type
        self.object = object
        self.timestamp = timestamp
    }
}

public enum ContextActionType: String {
    case duplicate = "duplicate"
    case delete = "delete"
    case move = "move"
    case rotate = "rotate"
    case scale = "scale"
    case lock = "lock"
    case hide = "hide"
}

public struct SuggestedAction {
    public let title: String
    public let icon: String
    public let action: () -> Void
    
    public init(title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }
}