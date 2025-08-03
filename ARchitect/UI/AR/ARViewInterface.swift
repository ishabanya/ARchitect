import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - AR View Interface

public struct ARViewInterface: View {
    @StateObject private var arController = ARViewController()
    @StateObject private var toolPalette = ToolPaletteManager()
    @StateObject private var contextControls = ContextControlsManager()
    @StateObject private var undoRedoManager = UndoRedoManager()
    @StateObject private var performanceMonitor = ARPerformanceMonitor()
    @StateObject private var pipManager = PictureInPictureManager()
    @StateObject private var tutorialManager = TutorialManager()
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var isUIVisible = true
    @State private var autoHideTimer: Timer?
    
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // AR View Background
            ARViewContainer(controller: arController)
                .ignoresSafeArea(.all)
                .onTapGesture(coordinateSpace: .global) { location in
                    handleARViewTap(location)
                }
                .onLongPressGesture(coordinateSpace: .global) { location in
                    handleARViewLongPress(location)
                }
            
            // Minimalist UI Overlay
            if isUIVisible {
                MinimalistUIOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.3), value: isUIVisible)
            }
            
            // Tutorial Overlay (highest priority)
            if tutorialManager.isShowingTutorial {
                TutorialOverlay()
                    .transition(.opacity)
                    .zIndex(1000)
            }
        }
        .environmentObject(arController)
        .environmentObject(toolPalette)
        .environmentObject(contextControls)
        .environmentObject(undoRedoManager)
        .environmentObject(performanceMonitor)
        .environmentObject(pipManager)
        .environmentObject(tutorialManager)
        .onAppear {
            setupARInterface()
        }
        .onDisappear {
            cleanupARInterface()
        }
    }
    
    // MARK: - Minimalist UI Overlay
    
    @ViewBuilder
    private func MinimalistUIOverlay() -> some View {
        VStack {
            // Top UI Bar
            TopUIBar()
                .padding(.horizontal, 16)
                .padding(.top, 8)
            
            Spacer()
            
            // Context-sensitive middle controls
            if contextControls.hasActiveSelection {
                ContextSensitiveControls()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            Spacer()
            
            // Bottom UI Bar
            BottomUIBar()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .allowsHitTesting(true)
    }
    
    // MARK: - Top UI Bar
    
    @ViewBuilder
    private func TopUIBar() -> some View {
        HStack {
            // Left side - Session controls
            HStack(spacing: 12) {
                MinimalistButton(
                    systemImage: "xmark.circle.fill",
                    action: { arController.exitARSession() },
                    style: .secondary
                )
                .accessibilityLabel("Exit AR")
                .accessibilityHint("Exits AR mode and returns to main navigation")
                
                if arController.sessionState != .normal {
                    SessionStatusIndicator(state: arController.sessionState)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            
            Spacer()
            
            // Center - Performance indicators (when needed)
            if performanceMonitor.shouldShowIndicators {
                PerformanceIndicators()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
            
            // Right side - Tools and settings
            HStack(spacing: 12) {
                MinimalistButton(
                    systemImage: toolPalette.isExpanded ? "chevron.up.circle.fill" : "plus.circle.fill",
                    action: { toolPalette.toggleExpansion() },
                    style: .accent
                )
                .accessibilityLabel("Tools")
                .accessibilityHint("Opens tool palette")
                
                MinimalistButton(
                    systemImage: "gear.circle.fill",
                    action: { arController.showSettings() },
                    style: .secondary
                )
                .accessibilityLabel("Settings")
                .accessibilityHint("Opens AR settings")
            }
        }
    }
    
    // MARK: - Bottom UI Bar
    
    @ViewBuilder
    private func BottomUIBar() -> some View {
        HStack {
            // Left side - Undo/Redo
            UndoRedoControls()
            
            Spacer()
            
            // Center - Main actions
            MainActionControls()
            
            Spacer()
            
            // Right side - Secondary actions
            SecondaryActionControls()
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleARViewTap(_ location: CGPoint) {
        // Reset auto-hide timer
        resetAutoHideTimer()
        
        // Handle AR interaction
        arController.handleTap(at: location)
        
        // Update context controls
        contextControls.updateSelection(arController.selectedObject)
    }
    
    private func handleARViewLongPress(_ location: CGPoint) {
        resetAutoHideTimer()
        arController.handleLongPress(at: location)
        contextControls.showContextMenu(at: location)
    }
    
    private func setupARInterface() {
        // Initialize AR session
        arController.startSession()
        
        // Setup auto-hide timer
        setupAutoHideTimer()
        
        // Configure performance monitoring
        performanceMonitor.startMonitoring()
        
        // Show tutorial for first-time users
        if tutorialManager.shouldShowTutorial {
            tutorialManager.startTutorial()
        }
        
        logInfo("AR view interface setup completed", category: .general)
    }
    
    private func cleanupARInterface() {
        // Cleanup timers
        autoHideTimer?.invalidate()
        
        // Stop monitoring
        performanceMonitor.stopMonitoring()
        
        // Pause AR session
        arController.pauseSession()
        
        logInfo("AR view interface cleaned up", category: .general)
    }
    
    // MARK: - Auto-hide Logic
    
    private func setupAutoHideTimer() {
        resetAutoHideTimer()
    }
    
    private func resetAutoHideTimer() {
        autoHideTimer?.invalidate()
        
        // Show UI if hidden
        if !isUIVisible {
            withAnimation(.easeInOut(duration: 0.2)) {
                isUIVisible = true
            }
        }
        
        // Set timer to hide UI after inactivity
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            if !contextControls.hasActiveSelection && !toolPalette.isExpanded {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isUIVisible = false
                }
            }
        }
    }
    
    public func showUI() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isUIVisible = true
        }
        resetAutoHideTimer()
    }
}

// MARK: - AR View Container

private struct ARViewContainer: UIViewRepresentable {
    let controller: ARViewController
    
    func makeUIView(context: Context) -> ARView {
        return controller.arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update AR view if needed
    }
}

// MARK: - Minimalist Button

private struct MinimalistButton: View {
    let systemImage: String
    let action: () -> Void
    let style: ButtonStyle
    
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    enum ButtonStyle {
        case primary, secondary, accent, destructive
    }
    
    var body: some View {
        Button(action: {
            HapticFeedbackManager.shared.impact(.light)
            action()
        }) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: 44, height: 44)
                .background(backgroundColor, in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                .scaleEffect(isPressed && !reduceMotion ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
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
        case .primary: return .regularMaterial
        case .secondary: return .ultraThinMaterial
        case .accent: return .regularMaterial
        case .destructive: return .regularMaterial
        }
    }
}

// MARK: - Session Status Indicator

private struct SessionStatusIndicator: View {
    let state: ARSessionState
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(statusColor)
            
            Text(statusText)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel("AR Session Status: \(statusText)")
    }
    
    private var statusIcon: String {
        switch state {
        case .normal: return "checkmark.circle.fill"
        case .notAvailable: return "exclamationmark.triangle.fill"
        case .limitedTracking: return "location.circle.fill"
        case .initializing: return "arrow.clockwise.circle.fill"
        case .relocalizing: return "location.magnifyingglass"
        }
    }
    
    private var statusColor: Color {
        switch state {
        case .normal: return .green
        case .notAvailable: return .red
        case .limitedTracking: return .orange
        case .initializing: return .blue
        case .relocalizing: return .yellow
        }
    }
    
    private var statusText: String {
        switch state {
        case .normal: return "Ready"
        case .notAvailable: return "Unavailable"
        case .limitedTracking: return "Limited"
        case .initializing: return "Starting"
        case .relocalizing: return "Relocating"
        }
    }
}

// MARK: - Performance Indicators

private struct PerformanceIndicators: View {
    @EnvironmentObject private var performanceMonitor: ARPerformanceMonitor
    
    var body: some View {
        HStack(spacing: 8) {
            // FPS Indicator
            PerformanceMetric(
                value: String(format: "%.0f", performanceMonitor.currentFPS),
                unit: "FPS",
                color: performanceMonitor.fpsColor,
                isGood: performanceMonitor.currentFPS >= 55
            )
            
            // Tracking Quality
            PerformanceMetric(
                value: performanceMonitor.trackingQuality.shortName,
                unit: "Track",
                color: performanceMonitor.trackingColor,
                isGood: performanceMonitor.trackingQuality == .normal
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel("Performance: \(Int(performanceMonitor.currentFPS)) FPS, \(performanceMonitor.trackingQuality.rawValue) tracking")
    }
}

private struct PerformanceMetric: View {
    let value: String
    let unit: String
    let color: Color
    let isGood: Bool
    
    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(value)
                .font(.caption2)
                .fontWeight(.semibold)
                .monospacedDigit()
            
            Text(unit)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(.primary)
    }
}

// MARK: - Undo/Redo Controls

private struct UndoRedoControls: View {
    @EnvironmentObject private var undoRedoManager: UndoRedoManager
    
    var body: some View {
        HStack(spacing: 8) {
            MinimalistButton(
                systemImage: "arrow.uturn.backward.circle.fill",
                action: { undoRedoManager.undo() },
                style: undoRedoManager.canUndo ? .accent : .secondary
            )
            .disabled(!undoRedoManager.canUndo)
            .accessibilityLabel("Undo")
            .accessibilityHint(undoRedoManager.canUndo ? "Undoes last action" : "No actions to undo")
            
            MinimalistButton(
                systemImage: "arrow.uturn.forward.circle.fill",
                action: { undoRedoManager.redo() },
                style: undoRedoManager.canRedo ? .accent : .secondary
            )
            .disabled(!undoRedoManager.canRedo)
            .accessibilityLabel("Redo")
            .accessibilityHint(undoRedoManager.canRedo ? "Redoes last undone action" : "No actions to redo")
        }
    }
}

// MARK: - Main Action Controls

private struct MainActionControls: View {
    @EnvironmentObject private var arController: ARViewController
    @EnvironmentObject private var pipManager: PictureInPictureManager
    
    var body: some View {
        HStack(spacing: 16) {
            // Add Furniture (with PiP support)
            MinimalistButton(
                systemImage: "plus.circle.fill",
                action: { 
                    if pipManager.isSupported {
                        pipManager.showCatalogPiP()
                    } else {
                        arController.showFurnitureCatalog()
                    }
                },
                style: .primary
            )
            .accessibilityLabel("Add Furniture")
            .accessibilityHint("Opens furniture catalog")
            
            // Scan Room
            MinimalistButton(
                systemImage: "viewfinder.circle.fill",
                action: { arController.startRoomScanning() },
                style: .accent
            )
            .accessibilityLabel("Scan Room")
            .accessibilityHint("Starts room scanning mode")
            
            // Save/Share
            MinimalistButton(
                systemImage: "square.and.arrow.up.circle.fill",
                action: { arController.shareCurrentDesign() },
                style: .primary
            )
            .accessibilityLabel("Share Design")
            .accessibilityHint("Shares current room design")
        }
    }
}

// MARK: - Secondary Action Controls

private struct SecondaryActionControls: View {
    @EnvironmentObject private var arController: ARViewController
    
    var body: some View {
        HStack(spacing: 8) {
            MinimalistButton(
                systemImage: "camera.circle.fill",
                action: { arController.takeScreenshot() },
                style: .secondary
            )
            .accessibilityLabel("Screenshot")
            .accessibilityHint("Takes a screenshot of current view")
            
            MinimalistButton(
                systemImage: "record.circle.fill",
                action: { arController.toggleRecording() },
                style: arController.isRecording ? .destructive : .secondary
            )
            .accessibilityLabel(arController.isRecording ? "Stop Recording" : "Start Recording")
            .accessibilityHint(arController.isRecording ? "Stops video recording" : "Starts video recording")
        }
    }
}

// MARK: - Context-Sensitive Controls

private struct ContextSensitiveControls: View {
    @EnvironmentObject private var contextControls: ContextControlsManager
    @EnvironmentObject private var undoRedoManager: UndoRedoManager
    
    var body: some View {
        VStack {
            if let selectedObject = contextControls.selectedObject {
                HStack(spacing: 12) {
                    // Object name and type
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedObject.name)
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        Text(selectedObject.type)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Context actions
                    HStack(spacing: 8) {
                        MinimalistButton(
                            systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                            action: { contextControls.enterMoveMode() },
                            style: contextControls.manipulationMode == .move ? .accent : .secondary
                        )
                        .accessibilityLabel("Move")
                        
                        MinimalistButton(
                            systemImage: "rotate.right.fill",
                            action: { contextControls.enterRotateMode() },
                            style: contextControls.manipulationMode == .rotate ? .accent : .secondary
                        )
                        .accessibilityLabel("Rotate")
                        
                        MinimalistButton(
                            systemImage: "plus.magnifyingglass",
                            action: { contextControls.enterScaleMode() },
                            style: contextControls.manipulationMode == .scale ? .accent : .secondary
                        )
                        .accessibilityLabel("Scale")
                        
                        MinimalistButton(
                            systemImage: "doc.on.doc.fill",
                            action: { 
                                contextControls.duplicateObject()
                                undoRedoManager.addAction(UndoableAction(type: .duplicate, object: selectedObject))
                            },
                            style: .primary
                        )
                        .accessibilityLabel("Duplicate")
                        
                        MinimalistButton(
                            systemImage: "trash.fill",
                            action: { 
                                contextControls.deleteObject()
                                undoRedoManager.addAction(UndoableAction(type: .delete, object: selectedObject))
                            },
                            style: .destructive
                        )
                        .accessibilityLabel("Delete")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Supporting Types

public enum ARSessionState {
    case normal
    case notAvailable
    case limitedTracking
    case initializing
    case relocalizing
}

public struct ARObject {
    let id: UUID
    let name: String
    let type: String
    let position: SIMD3<Float>
    
    public init(id: UUID = UUID(), name: String, type: String, position: SIMD3<Float> = SIMD3<Float>(0, 0, 0)) {
        self.id = id
        self.name = name
        self.type = type
        self.position = position
    }
}

// MARK: - AR View Controller (Placeholder)

@MainActor
private class ARViewController: ObservableObject {
    @Published var sessionState: ARSessionState = .initializing
    @Published var selectedObject: ARObject?
    @Published var isRecording = false
    
    let arView = ARView(frame: .zero)
    
    func startSession() {
        // Start AR session
        sessionState = .normal
    }
    
    func pauseSession() {
        // Pause AR session
    }
    
    func exitARSession() {
        // Exit AR session
        NavigationManager.shared.exitARMode()
    }
    
    func handleTap(at location: CGPoint) {
        // Handle tap gesture
    }
    
    func handleLongPress(at location: CGPoint) {
        // Handle long press gesture
    }
    
    func showSettings() {
        // Show AR settings
    }
    
    func showFurnitureCatalog() {
        // Show furniture catalog
    }
    
    func startRoomScanning() {
        // Start room scanning
    }
    
    func shareCurrentDesign() {
        // Share current design
    }
    
    func takeScreenshot() {
        // Take screenshot
    }
    
    func toggleRecording() {
        isRecording.toggle()
    }
}