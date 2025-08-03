import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - Complete AR View Interface

public struct CompleteARViewInterface: View {
    @StateObject private var arController = ARViewController()
    @StateObject private var toolPalette = ToolPaletteManager()
    @StateObject private var contextControls = ContextControlsManager()
    @StateObject private var undoRedoManager = UndoRedoManager()
    @StateObject private var performanceMonitor = ARPerformanceMonitor()
    @StateObject private var pipManager = PictureInPictureManager()
    @StateObject private var tutorialManager = TutorialManager()
    @StateObject private var gestureHandler = ARGestureHandler()
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isUIVisible = true
    @State private var autoHideTimer: Timer?
    @State private var arView = ARView(frame: .zero)
    
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // AR View Background
            ARViewContainer(arView: $arView, controller: arController)
                .ignoresSafeArea(.all)
                .arGestures(arView: arView, gestureHandler: gestureHandler)
                .onTapGesture(coordinateSpace: .global) { location in
                    handleARViewTap(location)
                }
                .accessibilityLabel("AR Camera View")
                .accessibilityHint("View your room through the camera. Touch and drag to manipulate furniture.")
            
            // Main UI Layer
            if isUIVisible && !tutorialManager.isShowingTutorial {
                MainUILayer()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.3), value: isUIVisible)
            }
            
            // Tool Palette Overlay
            if toolPalette.isExpanded {
                VStack {
                    Spacer()
                    ToolPalette()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(900)
            }
            
            // Picture-in-Picture Layer
            PictureInPictureView()
                .zIndex(950)
            
            // Context-Sensitive Controls
            if contextControls.hasActiveSelection && isUIVisible {
                VStack {
                    Spacer()
                    ContextSensitiveControls()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 160)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(800)
            }
            
            // Undo/Redo Visual Feedback
            VStack {
                UndoRedoFeedback()
                    .padding(.top, 100)
                Spacer()
            }
            .zIndex(850)
            
            // Performance Indicators
            if performanceMonitor.shouldShowIndicators {
                VStack {
                    HStack {
                        Spacer()
                        PerformanceIndicators()
                            .padding(.trailing, 20)
                            .padding(.top, 60)
                    }
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(700)
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
        .environmentObject(gestureHandler)
        .onAppear {
            setupCompleteARInterface()
        }
        .onDisappear {
            cleanupCompleteARInterface()
        }
        .onChange(of: gestureHandler.selectedEntity) { _, entity in
            contextControls.updateSelection(entity != nil ? ARObject(name: entity?.name ?? "Unknown", type: "Furniture") : nil)
        }
    }
    
    // MARK: - Main UI Layer
    
    @ViewBuilder
    private func MainUILayer() -> some View {
        VStack {
            // Top UI Bar
            TopUIBar()
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Spacer()
            
            // Bottom UI Bar
            BottomUIBar()
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
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
                    action: { 
                        exitARWithConfirmation()
                    },
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
            if performanceMonitor.shouldShowIndicators && !isCompact {
                PerformanceIndicators()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
            
            // Right side - Tools and settings
            HStack(spacing: 12) {
                MinimalistButton(
                    systemImage: toolPalette.isExpanded ? "chevron.down.circle.fill" : "plus.circle.fill",
                    action: { 
                        toolPalette.toggleExpansion()
                        resetAutoHideTimer()
                    },
                    style: .accent
                )
                .accessibilityLabel(toolPalette.isExpanded ? "Hide tools" : "Show tools")
                .accessibilityHint("Opens tool palette with furniture and editing options")
                
                MinimalistButton(
                    systemImage: "gear.circle.fill",
                    action: { 
                        showARSettings()
                    },
                    style: .secondary
                )
                .accessibilityLabel("AR Settings")
                .accessibilityHint("Opens AR configuration and preferences")
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
    
    // MARK: - Main Action Controls
    
    @ViewBuilder
    private func MainActionControls() -> some View {
        HStack(spacing: isCompact ? 12 : 16) {
            // Add Furniture (with PiP support)
            MinimalistButton(
                systemImage: "plus.circle.fill",
                action: { 
                    if pipManager.isSupported {
                        pipManager.showCatalogPiP()
                    } else {
                        showFurnitureCatalog()
                    }
                    resetAutoHideTimer()
                },
                style: .primary,
                size: .large
            )
            .accessibilityLabel("Add Furniture")
            .accessibilityHint("Opens furniture catalog to place new items")
            
            // Scan Room
            MinimalistButton(
                systemImage: "viewfinder.circle.fill",
                action: { 
                    startRoomScanning()
                    resetAutoHideTimer()
                },
                style: .accent,
                size: .large
            )
            .accessibilityLabel("Scan Room")
            .accessibilityHint("Starts room scanning to detect surfaces")
            
            // Save/Share
            MinimalistButton(
                systemImage: "square.and.arrow.up.circle.fill",
                action: { 
                    shareCurrentDesign()
                    resetAutoHideTimer()
                },
                style: .primary,
                size: .large
            )
            .accessibilityLabel("Share Design")
            .accessibilityHint("Saves and shares current room design")
        }
    }
    
    // MARK: - Secondary Action Controls
    
    @ViewBuilder
    private func SecondaryActionControls() -> some View {
        HStack(spacing: 8) {
            MinimalistButton(
                systemImage: "camera.circle.fill",
                action: { 
                    takeScreenshot()
                    resetAutoHideTimer()
                },
                style: .secondary
            )
            .accessibilityLabel("Screenshot")
            .accessibilityHint("Takes a screenshot of current AR view")
            
            MinimalistButton(
                systemImage: arController.isRecording ? "stop.circle.fill" : "record.circle.fill",
                action: { 
                    toggleRecording()
                    resetAutoHideTimer()
                },
                style: arController.isRecording ? .destructive : .secondary
            )
            .accessibilityLabel(arController.isRecording ? "Stop Recording" : "Start Recording")
            .accessibilityHint(arController.isRecording ? "Stops video recording" : "Starts video recording")
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleARViewTap(_ location: CGPoint) {
        // Reset auto-hide timer
        resetAutoHideTimer()
        showUI()
        
        // Handle AR interaction
        arController.handleTap(at: location)
        gestureHandler.handleTapGesture(at: location, in: arView)
        
        // Update context controls
        contextControls.updateSelection(gestureHandler.selectedEntity != nil ? 
                                      ARObject(name: gestureHandler.selectedEntity?.name ?? "Object", type: "Furniture") : nil)
    }
    
    private func exitARWithConfirmation() {
        // Show confirmation if there are unsaved changes
        if undoRedoManager.canUndo {
            // Would show confirmation dialog
            logInfo("Exiting AR with unsaved changes", category: .general)
        }
        
        NavigationController.shared.exitARMode()
    }
    
    private func showARSettings() {
        // Show AR settings sheet
        logDebug("Showing AR settings", category: .general)
    }
    
    private func showFurnitureCatalog() {
        // Show full-screen furniture catalog
        logDebug("Showing furniture catalog", category: .general)
    }
    
    private func startRoomScanning() {
        arController.startRoomScanning()
        HapticFeedbackManager.shared.roomScanProgress()
        AccessibilityManager.shared.announce("Room scanning started", priority: .normal)
        
        // Show scanning tutorial hint if first time
        if tutorialManager.shouldShowHint(for: "room_scanning") {
            // Would show tutorial hint
            tutorialManager.markHintShown(for: "room_scanning")
        }
    }
    
    private func shareCurrentDesign() {
        arController.shareCurrentDesign()
        HapticFeedbackManager.shared.operationSuccess()
    }
    
    private func takeScreenshot() {
        arController.takeScreenshot()
        HapticFeedbackManager.shared.impact(.medium)
        AccessibilityManager.shared.announce("Screenshot saved", priority: .normal)
    }
    
    private func toggleRecording() {
        arController.toggleRecording()
        HapticFeedbackManager.shared.impact(.heavy)
        
        let message = arController.isRecording ? "Recording started" : "Recording stopped"
        AccessibilityManager.shared.announce(message, priority: .normal)
    }
    
    // MARK: - Setup and Cleanup
    
    private func setupCompleteARInterface() {
        // Initialize AR session
        arController.startSession()
        
        // Setup performance monitoring with AR frame updates
        performanceMonitor.startMonitoring()
        arController.onFrameUpdate = { frame in
            self.performanceMonitor.updateFromARFrame(frame)
        }
        
        // Setup gesture handling
        gestureHandler.setPhysicsIntegration(nil) // Would pass actual physics integration
        
        // Setup auto-hide timer
        setupAutoHideTimer()
        
        // Show tutorial for first-time users
        if tutorialManager.shouldShowTutorial {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.tutorialManager.startTutorial(.arBasics)
            }
        }
        
        logInfo("Complete AR view interface setup completed", category: .general)
    }
    
    private func cleanupCompleteARInterface() {
        // Cleanup timers
        autoHideTimer?.invalidate()
        
        // Stop monitoring
        performanceMonitor.stopMonitoring()
        
        // Pause AR session
        arController.pauseSession()
        
        // Hide PiP
        if pipManager.isPiPActive {
            pipManager.hidePiP()
        }
        
        // End tutorial if active
        if tutorialManager.isShowingTutorial {
            tutorialManager.skipTutorial()
        }
        
        logInfo("Complete AR view interface cleaned up", category: .general)
    }
    
    // MARK: - Auto-hide Logic
    
    private func setupAutoHideTimer() {
        resetAutoHideTimer()
    }
    
    private func resetAutoHideTimer() {
        autoHideTimer?.invalidate()
        
        // Don't auto-hide if tutorial is showing or context menu is active
        guard !tutorialManager.isShowingTutorial && !contextControls.hasActiveSelection else { return }
        
        // Show UI if hidden
        if !isUIVisible {
            showUI()
        }
        
        // Set timer to hide UI after inactivity
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            if !self.contextControls.hasActiveSelection && 
               !self.toolPalette.isExpanded && 
               !self.pipManager.isDragging {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.isUIVisible = false
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
    
    // MARK: - Accessibility Helpers
    
    private func announceARStatus() {
        let status = switch arController.sessionState {
        case .normal: "AR tracking is working well"
        case .limitedTracking: "AR tracking is limited, try moving slowly"
        case .notAvailable: "AR is not available"
        case .initializing: "AR is starting up"
        case .relocalizing: "AR is relocating, move the device slowly"
        }
        
        AccessibilityManager.shared.announce(status, priority: .normal)
    }
}

// MARK: - AR View Container

private struct ARViewContainer: UIViewRepresentable {
    @Binding var arView: ARView
    let controller: ARViewController
    
    func makeUIView(context: Context) -> ARView {
        setupARView()
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update AR view configuration if needed
    }
    
    private func setupARView() {
        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        
        // Enable scene reconstruction if supported
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        // Enable occlusion if supported
        if type(of: configuration).supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        
        // Start AR session
        arView.session.run(configuration)
        
        // Configure rendering
        arView.renderOptions = [.disablePersonOcclusion, .disableDepthOfField]
        arView.environment.sceneUnderstanding.options = [.occlusion, .physics]
        
        logDebug("AR view configured and session started", category: .general)
    }
}

// MARK: - Minimalist Button Enhanced

private struct MinimalistButton: View {
    let systemImage: String
    let action: () -> Void
    let style: ButtonStyle
    let size: ButtonSize
    
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    enum ButtonStyle {
        case primary, secondary, accent, destructive
    }
    
    enum ButtonSize {
        case small, medium, large
        
        var dimension: CGFloat {
            switch self {
            case .small: return 36
            case .medium: return 44
            case .large: return 56
            }
        }
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 16
            case .medium: return 20
            case .large: return 24
            }
        }
    }
    
    init(systemImage: String, action: @escaping () -> Void, style: ButtonStyle = .secondary, size: ButtonSize = .medium) {
        self.systemImage = systemImage
        self.action = action
        self.style = style
        self.size = size
    }
    
    var body: some View {
        Button(action: {
            HapticFeedbackManager.shared.impact(.light)
            action()
        }) {
            Image(systemName: systemImage)
                .font(.system(size: size.iconSize, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: size.dimension, height: size.dimension)
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
        return .ultraThinMaterial
    }
}

// MARK: - Session Status Indicator

private struct SessionStatusIndicator: View {
    let state: ARSessionState
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(statusColor)
            
            Text(statusText)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel("AR Status: \(statusText)")
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

// MARK: - Supporting Extensions

private class NavigationController {
    static let shared = NavigationController()
    
    func exitARMode() {
        // Implementation would go here
        logInfo("Exiting AR mode", category: .general)
    }
}

// MARK: - AR View Controller Enhanced

@MainActor
private class ARViewController: ObservableObject {
    @Published var sessionState: ARSessionState = .initializing
    @Published var selectedObject: ARObject?
    @Published var isRecording = false
    
    let arView = ARView(frame: .zero)
    var onFrameUpdate: ((ARFrame) -> Void)?
    
    func startSession() {
        sessionState = .normal
        
        // Setup frame update callback
        arView.session.delegate = ARSessionDelegate(onFrameUpdate: onFrameUpdate)
    }
    
    func pauseSession() {
        arView.session.pause()
    }
    
    func handleTap(at location: CGPoint) {
        // Handle tap gesture
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

// MARK: - AR Session Delegate

private class ARSessionDelegate: NSObject, ARSessionDelegate {
    let onFrameUpdate: ((ARFrame) -> Void)?
    
    init(onFrameUpdate: ((ARFrame) -> Void)?) {
        self.onFrameUpdate = onFrameUpdate
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        onFrameUpdate?(frame)
    }
}