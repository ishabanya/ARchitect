import SwiftUI
import RealityKit
import ARKit

// MARK: - AR Contextual Controls

public struct ARContextualControls: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    @StateObject private var arSessionManager = ARSessionManager()
    @StateObject private var selectionManager = ARSelectionManager()
    @StateObject private var hapticFeedback = HapticFeedbackManager.shared
    
    // Control states
    @State private var showingActionMenu = false
    @State private var isRecording = false
    @State private var selectedObject: ARObject?
    @State private var controlsVisible = true
    @State private var autoHideTimer: Timer?
    
    // Layout properties
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var isCompact: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    private var isLandscape: Bool {
        navigationController.isLandscape
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Main control layout
            if controlsVisible {
                if isLandscape {
                    landscapeControlsLayout
                } else {
                    portraitControlsLayout
                }
            }
            
            // Floating action menu
            if showingActionMenu {
                FloatingActionMenu(
                    selectedObject: selectedObject,
                    onAction: handleFloatingAction,
                    onDismiss: { showingActionMenu = false }
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: controlsVisible)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showingActionMenu)
        .onReceive(selectionManager.$selectedObject) { object in
            selectedObject = object
            if object != nil {
                showFloatingMenu()
            }
        }
        .onAppear {
            setupAutoHide()
        }
    }
    
    // MARK: - Layout Variants
    
    private var portraitControlsLayout: some View {
        VStack {
            // Top controls
            HStack {
                TopControlsRow()
                Spacer()
                RecordingControls()
            }
            .padding(.horizontal)
            .padding(.top, 10)
            
            Spacer()
            
            // Bottom controls
            VStack(spacing: 16) {
                // Object manipulation controls (if object selected)
                if selectedObject != nil {
                    ObjectManipulationControls(object: selectedObject!)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Main action buttons
                MainActionButtons()
            }
            .padding(.horizontal)
            .padding(.bottom, 34) // Account for home indicator
        }
    }
    
    private var landscapeControlsLayout: some View {
        HStack {
            // Left side controls
            if !isCompact {
                VStack {
                    TopControlsRow()
                    Spacer()
                    RecordingControls()
                }
                .padding(.leading)
                .padding(.vertical, 20)
            }
            
            Spacer()
            
            // Right side controls
            VStack {
                if isCompact {
                    HStack {
                        TopControlsRow()
                        Spacer()
                        RecordingControls()
                    }
                }
                
                Spacer()
                
                // Main action buttons (vertical in landscape)
                VStack(spacing: 12) {
                    if selectedObject != nil {
                        ObjectManipulationControls(object: selectedObject!)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    
                    MainActionButtons()
                }
            }
            .padding(.trailing)
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - Control Components
    
    private func TopControlsRow() -> some View {
        HStack(spacing: 12) {
            // Close/Back button
            ContextualButton(
                systemImage: "xmark",
                action: { navigationController.exitARMode() },
                style: .secondary
            )
            .accessibilityLabel("Exit AR mode")
            
            // Settings button
            ContextualButton(
                systemImage: "gear",
                action: { navigationController.presentSheet(.settings) },
                style: .secondary
            )
            .accessibilityLabel("AR settings")
            
            // Help button
            ContextualButton(
                systemImage: "questionmark.circle",
                action: { showHelpOverlay() },
                style: .secondary
            )
            .accessibilityLabel("Help")
        }
    }
    
    private func RecordingControls() -> some View {
        HStack(spacing: 12) {
            // Screenshot button
            ContextualButton(
                systemImage: "camera",
                action: { takeScreenshot() },
                style: .secondary
            )
            .accessibilityLabel("Take screenshot")
            
            // Record button
            ContextualButton(
                systemImage: isRecording ? "stop.circle.fill" : "record.circle",
                action: { toggleRecording() },
                style: isRecording ? .destructive : .secondary
            )
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        }
    }
    
    private func MainActionButtons() -> some View {
        HStack(spacing: isLandscape ? 12 : 20) {
            // Add furniture button
            ContextualButton(
                systemImage: "plus.circle.fill",
                action: { navigationController.presentSheet(.furnitureCatalog) },
                style: .primary,
                size: .large
            )
            .accessibilityLabel("Add furniture")
            .accessibilityHint("Opens furniture catalog")
            
            // Scan room button
            ContextualButton(
                systemImage: "viewfinder.circle.fill",
                action: { startRoomScanning() },
                style: .accent,
                size: .large
            )
            .accessibilityLabel("Scan room")
            .accessibilityHint("Starts room scanning mode")
            
            // Save room button
            ContextualButton(
                systemImage: "square.and.arrow.down.fill",
                action: { saveCurrentRoom() },
                style: .secondary,
                size: .large
            )
            .accessibilityLabel("Save room")
            .accessibilityHint("Saves current room design")
        }
    }
    
    private func ObjectManipulationControls(object: ARObject) -> some View {
        HStack(spacing: 16) {
            // Delete object
            ContextualButton(
                systemImage: "trash",
                action: { deleteObject(object) },
                style: .destructive
            )
            .accessibilityLabel("Delete object")
            
            // Duplicate object
            ContextualButton(
                systemImage: "doc.on.doc",
                action: { duplicateObject(object) },
                style: .secondary
            )
            .accessibilityLabel("Duplicate object")
            
            // Rotate object
            ContextualButton(
                systemImage: "rotate.right",
                action: { rotateObject(object) },
                style: .secondary
            )
            .accessibilityLabel("Rotate object")
            
            // Object properties
            ContextualButton(
                systemImage: "slider.horizontal.3",
                action: { showObjectProperties(object) },
                style: .secondary
            )
            .accessibilityLabel("Object properties")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }
    
    // MARK: - Action Handlers
    
    private func handleFloatingAction(_ action: FloatingAction) {
        hapticFeedback.impact(.medium)
        
        switch action {
        case .move:
            startMoveMode()
        case .rotate:
            startRotateMode()
        case .scale:
            startScaleMode()
        case .duplicate:
            if let object = selectedObject {
                duplicateObject(object)
            }
        case .delete:
            if let object = selectedObject {
                deleteObject(object)
            }
        case .properties:
            if let object = selectedObject {
                showObjectProperties(object)
            }
        }
        
        showingActionMenu = false
    }
    
    private func showFloatingMenu() {
        guard !showingActionMenu else { return }
        
        hapticFeedback.impact(.light)
        showingActionMenu = true
        
        // Auto-hide after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if showingActionMenu {
                showingActionMenu = false
            }
        }
    }
    
    private func takeScreenshot() {
        hapticFeedback.impact(.medium)
        
        // Take screenshot logic
        arSessionManager.takeScreenshot { result in
            switch result {
            case .success:
                hapticFeedback.notification(.success)
                navigationController.announceImportantAction("Screenshot saved")
            case .failure:
                hapticFeedback.notification(.error)
                navigationController.announceImportantAction("Screenshot failed")
            }
        }
        
        logDebug("Screenshot taken", category: .general)
    }
    
    private func toggleRecording() {
        isRecording.toggle()
        hapticFeedback.impact(.heavy)
        
        if isRecording {
            arSessionManager.startRecording()
            navigationController.announceImportantAction("Recording started")
        } else {
            arSessionManager.stopRecording()
            navigationController.announceImportantAction("Recording stopped")
        }
        
        logDebug("Recording toggled", category: .general, context: LogContext(customData: [
            "is_recording": isRecording
        ]))
    }
    
    private func startRoomScanning() {
        hapticFeedback.impact(.medium)
        arSessionManager.startRoomScanning()
        navigationController.announceImportantAction("Room scanning started")
        
        logInfo("Room scanning started", category: .general)
    }
    
    private func saveCurrentRoom() {
        hapticFeedback.impact(.medium)
        
        // Save room logic
        Task {
            do {
                try await arSessionManager.saveCurrentRoom()
                hapticFeedback.notification(.success)
                navigationController.announceImportantAction("Room saved successfully")
            } catch {
                hapticFeedback.notification(.error)
                navigationController.announceImportantAction("Failed to save room")
                logError("Failed to save room", category: .general, error: error)
            }
        }
    }
    
    private func deleteObject(_ object: ARObject) {
        hapticFeedback.impact(.heavy)
        
        selectionManager.deleteObject(object)
        navigationController.announceImportantAction("Object deleted")
        
        logDebug("Object deleted", category: .general, context: LogContext(customData: [
            "object_id": object.id.uuidString
        ]))
    }
    
    private func duplicateObject(_ object: ARObject) {
        hapticFeedback.impact(.medium)
        
        selectionManager.duplicateObject(object)
        navigationController.announceImportantAction("Object duplicated")
        
        logDebug("Object duplicated", category: .general)
    }
    
    private func rotateObject(_ object: ARObject) {
        hapticFeedback.impact(.light)
        
        selectionManager.rotateObject(object, by: 45) // 45 degree rotation
        navigationController.announceImportantAction("Object rotated")
    }
    
    private func showObjectProperties(_ object: ARObject) {
        // Show object properties sheet
        navigationController.presentSheet(.roomSettings) // Placeholder
    }
    
    private func startMoveMode() {
        selectionManager.setManipulationMode(.move)
        navigationController.announceImportantAction("Move mode activated")
    }
    
    private func startRotateMode() {
        selectionManager.setManipulationMode(.rotate)
        navigationController.announceImportantAction("Rotate mode activated")
    }
    
    private func startScaleMode() {
        selectionManager.setManipulationMode(.scale)
        navigationController.announceImportantAction("Scale mode activated")
    }
    
    private func showHelpOverlay() {
        // Show help overlay
        navigationController.announceImportantAction("Help overlay shown")
    }
    
    // MARK: - Auto-hide Controls
    
    private func setupAutoHide() {
        resetAutoHideTimer()
    }
    
    private func resetAutoHideTimer() {
        autoHideTimer?.invalidate()
        
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            if selectedObject == nil && !showingActionMenu {
                withAnimation(.easeInOut(duration: 0.3)) {
                    controlsVisible = false
                }
            }
        }
    }
    
    public func showControls() {
        withAnimation(.easeInOut(duration: 0.3)) {
            controlsVisible = true
        }
        resetAutoHideTimer()
    }
}

// MARK: - Contextual Button

private struct ContextualButton: View {
    let systemImage: String
    let action: () -> Void
    let style: ButtonStyle
    let size: ButtonSize
    
    @StateObject private var hapticFeedback = HapticFeedbackManager.shared
    
    enum ButtonStyle {
        case primary, secondary, accent, destructive
    }
    
    enum ButtonSize {
        case small, medium, large
    }
    
    init(systemImage: String, action: @escaping () -> Void, style: ButtonStyle = .secondary, size: ButtonSize = .medium) {
        self.systemImage = systemImage
        self.action = action
        self.style = style
        self.size = size
    }
    
    var body: some View {
        Button(action: {
            hapticFeedback.impact(.light)
            action()
        }) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: buttonSize, height: buttonSize)
                .background(backgroundColor, in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var iconSize: CGFloat {
        switch size {
        case .small: return 16
        case .medium: return 20
        case .large: return 24
        }
    }
    
    private var buttonSize: CGFloat {
        switch size {
        case .small: return 36
        case .medium: return 44
        case .large: return 56
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return .primary
        case .accent: return .white
        case .destructive: return .white
        }
    }
    
    private var backgroundColor: Material {
        switch style {
        case .primary: return .ultraThinMaterial
        case .secondary: return .ultraThinMaterial
        case .accent: return .ultraThinMaterial
        case .destructive: return .ultraThinMaterial
        }
    }
}

// MARK: - Floating Action Menu

private struct FloatingActionMenu: View {
    let selectedObject: ARObject?
    let onAction: (FloatingAction) -> Void
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ForEach(FloatingAction.allCases, id: \.self) { action in
                    FloatingActionButton(action: action, onTap: onAction)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                scale = 1.0
                opacity = 1.0
            }
        }
        .onTapGesture {
            onDismiss()
        }
    }
}

private struct FloatingActionButton: View {
    let action: FloatingAction
    let onTap: (FloatingAction) -> Void
    
    var body: some View {
        Button {
            onTap(action)
        } label: {
            Image(systemName: action.systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel(action.accessibilityLabel)
    }
}

// MARK: - Supporting Types

private enum FloatingAction: CaseIterable {
    case move, rotate, scale, duplicate, delete, properties
    
    var systemImage: String {
        switch self {
        case .move: return "move.3d"
        case .rotate: return "rotate.3d"
        case .scale: return "scale.3d"
        case .duplicate: return "doc.on.doc"
        case .delete: return "trash"
        case .properties: return "slider.horizontal.3"
        }
    }
    
    var accessibilityLabel: String {
        switch self {
        case .move: return "Move object"
        case .rotate: return "Rotate object"
        case .scale: return "Scale object"
        case .duplicate: return "Duplicate object"
        case .delete: return "Delete object"
        case .properties: return "Object properties"
        }
    }
}

// MARK: - Supporting Classes (Placeholders)

@MainActor
private class ARSessionManager: ObservableObject {
    func takeScreenshot(completion: @escaping (Result<Void, Error>) -> Void) {
        // Screenshot implementation
        completion(.success(()))
    }
    
    func startRecording() {
        // Recording implementation
    }
    
    func stopRecording() {
        // Stop recording implementation
    }
    
    func startRoomScanning() {
        // Room scanning implementation
    }
    
    func saveCurrentRoom() async throws {
        // Save room implementation
    }
}

@MainActor
private class ARSelectionManager: ObservableObject {
    @Published var selectedObject: ARObject?
    
    enum ManipulationMode {
        case move, rotate, scale
    }
    
    func deleteObject(_ object: ARObject) {
        // Delete implementation
    }
    
    func duplicateObject(_ object: ARObject) {
        // Duplicate implementation
    }
    
    func rotateObject(_ object: ARObject, by degrees: Float) {
        // Rotate implementation
    }
    
    func setManipulationMode(_ mode: ManipulationMode) {
        // Set manipulation mode
    }
}

public struct ARObject: Identifiable {
    public let id = UUID()
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
}