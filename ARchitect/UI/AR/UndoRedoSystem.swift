import SwiftUI
import Combine

// MARK: - Undo/Redo Manager

@MainActor
public class UndoRedoManager: ObservableObject {
    
    // MARK: - Properties
    @Published public var canUndo = false
    @Published public var canRedo = false
    @Published public var undoStack: [UndoableAction] = []
    @Published public var redoStack: [UndoableAction] = []
    
    // Visual feedback
    @Published public var isShowingUndoFeedback = false
    @Published public var isShowingRedoFeedback = false
    @Published public var feedbackMessage = ""
    @Published public var feedbackIcon = ""
    
    // Configuration
    public var maxUndoActions = 50
    public var showVisualFeedback = true
    public var feedbackDuration: TimeInterval = 2.0
    
    // State tracking
    private var actionGroups: [ActionGroup] = []
    private var currentGroupId: UUID?
    private var groupTimeout: Timer?
    private let groupTimeoutInterval: TimeInterval = 2.0
    
    private let hapticFeedback = HapticFeedbackManager.shared
    private let accessibilityManager = AccessibilityManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        setupObservers()
        
        logDebug("Undo/Redo manager initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Monitor stack changes
        Publishers.CombineLatest($undoStack, $redoStack)
            .sink { [weak self] undoStack, redoStack in
                self?.updateAvailability(undoStack: undoStack, redoStack: redoStack)
            }
            .store(in: &cancellables)
    }
    
    private func updateAvailability(undoStack: [UndoableAction], redoStack: [UndoableAction]) {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
    
    // MARK: - Action Management
    
    public func addAction(_ action: UndoableAction) {
        // Clear redo stack when new action is added
        redoStack.removeAll()
        
        // Add to undo stack
        undoStack.append(action)
        
        // Manage group if needed
        if let groupId = currentGroupId {
            addToActionGroup(action, groupId: groupId)
        }
        
        // Limit stack size
        if undoStack.count > maxUndoActions {
            undoStack.removeFirst()
        }
        
        logDebug("Action added to undo stack", category: .general, context: LogContext(customData: [
            "action_type": action.type.rawValue,
            "stack_size": undoStack.count
        ]))
    }
    
    public func beginActionGroup() -> UUID {
        let groupId = UUID()
        currentGroupId = groupId
        
        // Reset group timeout
        resetGroupTimeout()
        
        logDebug("Action group started", category: .general, context: LogContext(customData: [
            "group_id": groupId.uuidString
        ]))
        
        return groupId
    }
    
    public func endActionGroup() {
        currentGroupId = nil
        groupTimeout?.invalidate()
        
        logDebug("Action group ended", category: .general)
    }
    
    private func addToActionGroup(_ action: UndoableAction, groupId: UUID) {
        if let existingGroup = actionGroups.first(where: { $0.id == groupId }) {
            existingGroup.actions.append(action)
        } else {
            let newGroup = ActionGroup(id: groupId, actions: [action])
            actionGroups.append(newGroup)
        }
        
        resetGroupTimeout()
    }
    
    private func resetGroupTimeout() {
        groupTimeout?.invalidate()
        
        groupTimeout = Timer.scheduledTimer(withTimeInterval: groupTimeoutInterval, repeats: false) { [weak self] _ in
            self?.endActionGroup()
        }
    }
    
    // MARK: - Undo/Redo Operations
    
    public func undo() {
        guard canUndo, let lastAction = undoStack.last else { return }
        
        // Remove from undo stack
        undoStack.removeLast()
        
        // Execute undo
        executeUndo(lastAction)
        
        // Add to redo stack
        redoStack.append(lastAction)
        
        // Show visual feedback
        showUndoFeedback(for: lastAction)
        
        // Haptic feedback
        hapticFeedback.impact(.medium)
        
        // Accessibility announcement
        accessibilityManager.announce("Undid \(lastAction.description)", priority: .normal)
        
        logDebug("Action undone", category: .general, context: LogContext(customData: [
            "action_type": lastAction.type.rawValue,
            "action_id": lastAction.id.uuidString
        ]))
    }
    
    public func redo() {
        guard canRedo, let nextAction = redoStack.last else { return }
        
        // Remove from redo stack
        redoStack.removeLast()
        
        // Execute redo
        executeRedo(nextAction)
        
        // Add back to undo stack
        undoStack.append(nextAction)
        
        // Show visual feedback
        showRedoFeedback(for: nextAction)
        
        // Haptic feedback
        hapticFeedback.impact(.medium)
        
        // Accessibility announcement
        accessibilityManager.announce("Redid \(nextAction.description)", priority: .normal)
        
        logDebug("Action redone", category: .general, context: LogContext(customData: [
            "action_type": nextAction.type.rawValue,
            "action_id": nextAction.id.uuidString
        ]))
    }
    
    // MARK: - Action Execution
    
    private func executeUndo(_ action: UndoableAction) {
        switch action.type {
        case .create:
            // Remove the created object
            removeObject(action.targetObject)
            
        case .delete:
            // Restore the deleted object
            restoreObject(action.targetObject, at: action.previousState)
            
        case .move:
            // Restore previous position
            if let previousTransform = action.previousState {
                moveObject(action.targetObject, to: previousTransform.position)
            }
            
        case .rotate:
            // Restore previous rotation
            if let previousTransform = action.previousState {
                rotateObject(action.targetObject, to: previousTransform.rotation)
            }
            
        case .scale:
            // Restore previous scale
            if let previousTransform = action.previousState {
                scaleObject(action.targetObject, to: previousTransform.scale)
            }
            
        case .duplicate:
            // Remove the duplicated object
            if let duplicatedObject = action.resultObject {
                removeObject(duplicatedObject)
            }
            
        case .material:
            // Restore previous material
            if let previousMaterial = action.previousMaterial {
                changeMaterial(action.targetObject, to: previousMaterial)
            }
            
        case .group:
            // Ungroup objects
            ungroupObjects(action.affectedObjects)
            
        case .ungroup:
            // Regroup objects
            groupObjects(action.affectedObjects)
        }
    }
    
    private func executeRedo(_ action: UndoableAction) {
        switch action.type {
        case .create:
            // Recreate the object
            createObject(action.targetObject, at: action.currentState)
            
        case .delete:
            // Delete the object again
            removeObject(action.targetObject)
            
        case .move:
            // Apply the movement again
            if let currentTransform = action.currentState {
                moveObject(action.targetObject, to: currentTransform.position)
            }
            
        case .rotate:
            // Apply the rotation again
            if let currentTransform = action.currentState {
                rotateObject(action.targetObject, to: currentTransform.rotation)
            }
            
        case .scale:
            // Apply the scale again
            if let currentTransform = action.currentState {
                scaleObject(action.targetObject, to: currentTransform.scale)
            }
            
        case .duplicate:
            // Duplicate the object again
            if let duplicatedObject = action.resultObject {
                createObject(duplicatedObject, at: action.currentState)
            }
            
        case .material:
            // Apply the material change again
            if let newMaterial = action.currentMaterial {
                changeMaterial(action.targetObject, to: newMaterial)
            }
            
        case .group:
            // Group objects again
            groupObjects(action.affectedObjects)
            
        case .ungroup:
            // Ungroup objects again
            ungroupObjects(action.affectedObjects)
        }
    }
    
    // MARK: - Object Operations (would interface with AR system)
    
    private func removeObject(_ object: ARObject) {
        // Remove from AR scene
        logDebug("Object removed for undo/redo", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString
        ]))
    }
    
    private func restoreObject(_ object: ARObject, at transform: ObjectTransform?) {
        // Restore to AR scene
        logDebug("Object restored for undo/redo", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString
        ]))
    }
    
    private func createObject(_ object: ARObject, at transform: ObjectTransform?) {
        // Create in AR scene
        logDebug("Object created for undo/redo", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString
        ]))
    }
    
    private func moveObject(_ object: ARObject, to position: SIMD3<Float>) {
        // Move object in AR scene
        logDebug("Object moved for undo/redo", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString,
            "position": [position.x, position.y, position.z]
        ]))
    }
    
    private func rotateObject(_ object: ARObject, to rotation: SIMD3<Float>) {
        // Rotate object in AR scene
        logDebug("Object rotated for undo/redo", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString,
            "rotation": [rotation.x, rotation.y, rotation.z]
        ]))
    }
    
    private func scaleObject(_ object: ARObject, to scale: SIMD3<Float>) {
        // Scale object in AR scene
        logDebug("Object scaled for undo/redo", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString,
            "scale": [scale.x, scale.y, scale.z]
        ]))
    }
    
    private func changeMaterial(_ object: ARObject, to material: String) {
        // Change object material
        logDebug("Object material changed for undo/redo", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString,
            "material": material
        ]))
    }
    
    private func groupObjects(_ objects: [ARObject]) {
        // Group objects
        logDebug("Objects grouped for undo/redo", category: .general, context: LogContext(customData: [
            "object_count": objects.count
        ]))
    }
    
    private func ungroupObjects(_ objects: [ARObject]) {
        // Ungroup objects
        logDebug("Objects ungrouped for undo/redo", category: .general, context: LogContext(customData: [
            "object_count": objects.count
        ]))
    }
    
    // MARK: - Visual Feedback
    
    private func showUndoFeedback(for action: UndoableAction) {
        guard showVisualFeedback else { return }
        
        feedbackMessage = "Undid \(action.description)"
        feedbackIcon = action.type.undoIcon
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingUndoFeedback = true
        }
        
        // Auto-hide feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + feedbackDuration) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isShowingUndoFeedback = false
            }
        }
    }
    
    private func showRedoFeedback(for action: UndoableAction) {
        guard showVisualFeedback else { return }
        
        feedbackMessage = "Redid \(action.description)"
        feedbackIcon = action.type.redoIcon
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingRedoFeedback = true
        }
        
        // Auto-hide feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + feedbackDuration) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isShowingRedoFeedback = false
            }
        }
    }
    
    // MARK: - Stack Management
    
    public func clearAllActions() {
        undoStack.removeAll()
        redoStack.removeAll()
        actionGroups.removeAll()
        currentGroupId = nil
        
        accessibilityManager.announce("Undo history cleared", priority: .normal)
        
        logInfo("Undo/redo stacks cleared", category: .general)
    }
    
    public func getUndoDescription() -> String? {
        return undoStack.last?.description
    }
    
    public func getRedoDescription() -> String? {
        return redoStack.last?.description
    }
    
    // MARK: - Batch Operations
    
    public func undoMultiple(_ count: Int) {
        let actualCount = min(count, undoStack.count)
        
        for _ in 0..<actualCount {
            undo()
        }
        
        accessibilityManager.announce("Undid \(actualCount) actions", priority: .normal)
    }
    
    public func redoMultiple(_ count: Int) {
        let actualCount = min(count, redoStack.count)
        
        for _ in 0..<actualCount {
            redo()
        }
        
        accessibilityManager.announce("Redid \(actualCount) actions", priority: .normal)
    }
}

// MARK: - Undo/Redo Visual Feedback View

public struct UndoRedoFeedback: View {
    @EnvironmentObject private var undoRedoManager: UndoRedoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init() {}
    
    public var body: some View {
        ZStack {
            if undoRedoManager.isShowingUndoFeedback {
                FeedbackToast(
                    message: undoRedoManager.feedbackMessage,
                    icon: undoRedoManager.feedbackIcon,
                    color: .blue
                )
                .transition(.feedbackTransition)
            }
            
            if undoRedoManager.isShowingRedoFeedback {
                FeedbackToast(
                    message: undoRedoManager.feedbackMessage,
                    icon: undoRedoManager.feedbackIcon,
                    color: .green
                )
                .transition(.feedbackTransition)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: undoRedoManager.isShowingUndoFeedback)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: undoRedoManager.isShowingRedoFeedback)
    }
}

// MARK: - Feedback Toast

private struct FeedbackToast: View {
    let message: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
            
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

// MARK: - Undo/Redo Controls Enhanced

public struct UndoRedoControls: View {
    @EnvironmentObject private var undoRedoManager: UndoRedoManager
    @State private var showingUndoOptions = false
    @State private var showingRedoOptions = false
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 12) {
            // Undo button with long press menu
            Button(action: { undoRedoManager.undo() }) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(undoRedoManager.canUndo ? .blue : .gray)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            .disabled(!undoRedoManager.canUndo)
            .accessibilityLabel("Undo")
            .accessibilityHint(undoRedoManager.canUndo ? 
                "Undoes \(undoRedoManager.getUndoDescription() ?? "last action")" : 
                "No actions to undo"
            )
            .contextMenu {
                if undoRedoManager.canUndo {
                    UndoContextMenu()
                }
            }
            
            // Redo button with long press menu
            Button(action: { undoRedoManager.redo() }) {
                Image(systemName: "arrow.uturn.forward.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(undoRedoManager.canRedo ? .green : .gray)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            .disabled(!undoRedoManager.canRedo)
            .accessibilityLabel("Redo")
            .accessibilityHint(undoRedoManager.canRedo ? 
                "Redoes \(undoRedoManager.getRedoDescription() ?? "last undone action")" : 
                "No actions to redo"
            )
            .contextMenu {
                if undoRedoManager.canRedo {
                    RedoContextMenu()
                }
            }
        }
    }
}

// MARK: - Undo Context Menu

private struct UndoContextMenu: View {
    @EnvironmentObject private var undoRedoManager: UndoRedoManager
    
    var body: some View {
        VStack {
            if let description = undoRedoManager.getUndoDescription() {
                Button("Undo \(description)") {
                    undoRedoManager.undo()
                }
            }
            
            if undoRedoManager.undoStack.count > 1 {
                Button("Undo Multiple...") {
                    // Show multiple undo options
                }
                
                Button("Undo All (\(undoRedoManager.undoStack.count))") {
                    undoRedoManager.undoMultiple(undoRedoManager.undoStack.count)
                }
            }
        }
    }
}

// MARK: - Redo Context Menu

private struct RedoContextMenu: View {
    @EnvironmentObject private var undoRedoManager: UndoRedoManager
    
    var body: some View {
        VStack {
            if let description = undoRedoManager.getRedoDescription() {
                Button("Redo \(description)") {
                    undoRedoManager.redo()
                }
            }
            
            if undoRedoManager.redoStack.count > 1 {
                Button("Redo Multiple...") {
                    // Show multiple redo options
                }
                
                Button("Redo All (\(undoRedoManager.redoStack.count))") {
                    undoRedoManager.redoMultiple(undoRedoManager.redoStack.count)
                }
            }
        }
    }
}

// MARK: - Supporting Types

public struct UndoableAction {
    public let id: UUID
    public let type: ActionType
    public let targetObject: ARObject
    public let timestamp: Date
    public let previousState: ObjectTransform?
    public let currentState: ObjectTransform?
    public let previousMaterial: String?
    public let currentMaterial: String?
    public let resultObject: ARObject?
    public let affectedObjects: [ARObject]
    
    public var description: String {
        switch type {
        case .create: return "Create \(targetObject.name)"
        case .delete: return "Delete \(targetObject.name)"
        case .move: return "Move \(targetObject.name)"
        case .rotate: return "Rotate \(targetObject.name)"
        case .scale: return "Scale \(targetObject.name)"
        case .duplicate: return "Duplicate \(targetObject.name)"
        case .material: return "Change Material"
        case .group: return "Group Objects"
        case .ungroup: return "Ungroup Objects"
        }
    }
    
    public init(
        type: ActionType,
        object: ARObject,
        previousState: ObjectTransform? = nil,
        currentState: ObjectTransform? = nil,
        previousMaterial: String? = nil,
        currentMaterial: String? = nil,
        resultObject: ARObject? = nil,
        affectedObjects: [ARObject] = []
    ) {
        self.id = UUID()
        self.type = type
        self.targetObject = object
        self.timestamp = Date()
        self.previousState = previousState
        self.currentState = currentState
        self.previousMaterial = previousMaterial
        self.currentMaterial = currentMaterial
        self.resultObject = resultObject
        self.affectedObjects = affectedObjects
    }
}

public enum ActionType: String, CaseIterable {
    case create = "create"
    case delete = "delete"
    case move = "move"
    case rotate = "rotate"
    case scale = "scale"
    case duplicate = "duplicate"
    case material = "material"
    case group = "group"
    case ungroup = "ungroup"
    
    public var undoIcon: String {
        switch self {
        case .create: return "minus.circle.fill"
        case .delete: return "plus.circle.fill"
        case .move: return "arrow.uturn.backward.circle.fill"
        case .rotate: return "rotate.left.fill"
        case .scale: return "arrow.down.right.and.arrow.up.left.circle.fill"
        case .duplicate: return "doc.on.doc.fill"
        case .material: return "paintbrush.fill"
        case .group: return "rectangle.3.group.fill"
        case .ungroup: return "square.3.layers.3d"
        }
    }
    
    public var redoIcon: String {
        switch self {
        case .create: return "plus.circle.fill"
        case .delete: return "minus.circle.fill"
        case .move: return "arrow.uturn.forward.circle.fill"
        case .rotate: return "rotate.right.fill"
        case .scale: return "arrow.up.left.and.arrow.down.right.circle.fill"
        case .duplicate: return "doc.on.doc.fill"
        case .material: return "paintbrush.fill"
        case .group: return "rectangle.3.group.fill"
        case .ungroup: return "square.3.layers.3d"
        }
    }
}

private class ActionGroup {
    let id: UUID
    var actions: [UndoableAction]
    
    init(id: UUID, actions: [UndoableAction] = []) {
        self.id = id
        self.actions = actions
    }
}

// MARK: - Transition Extensions

extension AnyTransition {
    static var feedbackTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
            removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 1.05))
        )
    }
}