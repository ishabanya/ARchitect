import SwiftUI
import RealityKit
import ARKit

// MARK: - Navigation Integration Demo

public struct NavigationIntegrationDemo: View {
    @StateObject private var navigationController = MainNavigationController()
    @StateObject private var orientationManager = OrientationManager.shared
    @StateObject private var accessibilityManager = AccessibilityManager.shared
    @StateObject private var hapticFeedback = HapticFeedbackManager.shared
    @StateObject private var transitionManager = TransitionManager.shared
    
    public init() {}
    
    public var body: some View {
        NavigationSystemContainer()
            .environmentObject(navigationController)
            .environmentObject(orientationManager)
            .environmentObject(accessibilityManager)
            .environmentObject(hapticFeedback)
            .environmentObject(transitionManager)
            .onAppear {
                setupIntegration()
            }
    }
}

// MARK: - Navigation System Container

private struct NavigationSystemContainer: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    @EnvironmentObject private var orientationManager: OrientationManager
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main tab navigation
                MainTabView()
                    .transition(.opacity.combined(with: .scale))
                
                // Orientation-aware overlays
                if navigationController.selectedTab == .ar {
                    ARViewWithContextualControls()
                        .orientationSpecific(
                            portrait: AnyView(ARPortraitOverlay()),
                            landscape: AnyView(ARLandscapeOverlay())
                        )
                }
                
                // Demo controls overlay
                if navigationController.debugMode {
                    DemoControlsOverlay()
                        .safeAreaPadding()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onOrientationChange { isLandscape in
                handleOrientationChange(isLandscape: isLandscape, size: geometry.size)
            }
        }
        .ignoresSafeArea(.all, edges: orientationManager.isLandscape ? [.horizontal] : [])
    }
    
    private func handleOrientationChange(isLandscape: Bool, size: CGSize) {
        // Announce orientation change for accessibility
        AccessibilityManager.shared.announceOrientationChange()
        
        // Provide haptic feedback
        HapticFeedbackManager.shared.impact(.light)
        
        // Log orientation change
        logDebug("Orientation changed in navigation system", category: .general, context: LogContext(customData: [
            "is_landscape": isLandscape,
            "size_width": size.width,
            "size_height": size.height
        ]))
    }
}

// MARK: - AR View with Contextual Controls

private struct ARViewWithContextualControls: View {
    @StateObject private var gestureHandler = ARGestureHandler()
    @State private var arView = ARView(frame: .zero)
    
    var body: some View {
        ZStack {
            // AR View
            ARViewRepresentable(arView: $arView)
                .arGestures(arView: arView, gestureHandler: gestureHandler)
                .accessibilityLabel("AR Camera View")
                .accessibilityHint("Touch and drag to manipulate furniture. Double tap to select objects.")
            
            // Contextual controls overlay
            ARContextualControls()
                .environmentObject(gestureHandler)
        }
    }
}

private struct ARViewRepresentable: UIViewRepresentable {
    @Binding var arView: ARView
    
    func makeUIView(context: Context) -> ARView {
        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        arView.session.run(configuration)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update AR view if needed
    }
}

// MARK: - Orientation-Specific AR Overlays

private struct ARPortraitOverlay: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    
    var body: some View {
        VStack {
            // Top controls
            HStack {
                Button("Exit AR") {
                    navigationController.exitARMode()
                }
                .accessibilityEnhanced(
                    label: "Exit AR mode",
                    hint: "Returns to main navigation"
                )
                
                Spacer()
                
                Button("Settings") {
                    navigationController.presentSheet(.settings)
                }
                .accessibilityEnhanced(
                    label: "AR Settings",
                    hint: "Opens AR configuration options"
                )
            }
            .padding()
            
            Spacer()
            
            // Bottom controls
            HStack(spacing: 20) {
                Button("Add") {
                    navigationController.presentSheet(.furnitureCatalog)
                    HapticFeedbackManager.shared.buttonPress()
                }
                .accessibilityEnhanced(
                    label: "Add Furniture",
                    hint: "Opens furniture catalog to place new items"
                )
                
                Button("Scan") {
                    // Start room scanning
                    HapticFeedbackManager.shared.roomScanProgress()
                }
                .accessibilityEnhanced(
                    label: "Scan Room",
                    hint: "Starts scanning the room for surfaces"
                )
                
                Button("Save") {
                    // Save room design
                    HapticFeedbackManager.shared.operationSuccess()
                }
                .accessibilityEnhanced(
                    label: "Save Room",
                    hint: "Saves the current room design"
                )
            }
            .padding()
        }
        .transition(.slideTransition(from: .bottom, isPresented: true))
    }
}

private struct ARLandscapeOverlay: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    
    var body: some View {
        HStack {
            // Left side controls
            VStack {
                Button("Exit AR") {
                    navigationController.exitARMode()
                }
                .accessibilityEnhanced(
                    label: "Exit AR mode",
                    hint: "Returns to main navigation"
                )
                
                Spacer()
                
                Button("Settings") {
                    navigationController.presentSheet(.settings)
                }
                .accessibilityEnhanced(
                    label: "AR Settings",
                    hint: "Opens AR configuration options"
                )
            }
            .padding()
            
            Spacer()
            
            // Right side controls
            VStack(spacing: 15) {
                Button("Add") {
                    navigationController.presentSheet(.furnitureCatalog)
                    HapticFeedbackManager.shared.buttonPress()
                }
                .accessibilityEnhanced(
                    label: "Add Furniture",
                    hint: "Opens furniture catalog to place new items"
                )
                
                Button("Scan") {
                    HapticFeedbackManager.shared.roomScanProgress()
                }
                .accessibilityEnhanced(
                    label: "Scan Room",
                    hint: "Starts scanning the room for surfaces"
                )
                
                Button("Save") {
                    HapticFeedbackManager.shared.operationSuccess()
                }
                .accessibilityEnhanced(
                    label: "Save Room",
                    hint: "Saves the current room design"
                )
            }
            .padding()
        }
        .transition(.slideTransition(from: .trailing, isPresented: true))
    }
}

// MARK: - Demo Controls Overlay

private struct DemoControlsOverlay: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    @EnvironmentObject private var orientationManager: OrientationManager
    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @EnvironmentObject private var hapticFeedback: HapticFeedbackManager
    
    @State private var showingDebugInfo = false
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                VStack(spacing: 12) {
                    // Debug toggle
                    Button("Debug") {
                        showingDebugInfo.toggle()
                        hapticFeedback.selectionChanged()
                    }
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    
                    // Orientation controls
                    VStack(spacing: 4) {
                        Button("Portrait") {
                            orientationManager.forcePortrait()
                            hapticFeedback.impact(.light)
                        }
                        .font(.caption2)
                        .padding(6)
                        .background(orientationManager.isPortrait ? .blue : .clear, in: RoundedRectangle(cornerRadius: 6))
                        
                        Button("Landscape") {
                            orientationManager.forceLandscape()
                            hapticFeedback.impact(.light)
                        }
                        .font(.caption2)
                        .padding(6)
                        .background(orientationManager.isLandscape ? .blue : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    
                    // Haptic test
                    Button("Haptic") {
                        hapticFeedback.playPattern(.objectSelection)
                    }
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    
                    // Accessibility test
                    Button("Voice") {
                        accessibilityManager.announce("Testing accessibility announcement", priority: .normal)
                    }
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingDebugInfo) {
            DebugInfoSheet()
        }
    }
}

// MARK: - Debug Info Sheet

private struct DebugInfoSheet: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    @EnvironmentObject private var orientationManager: OrientationManager
    @EnvironmentObject private var accessibilityManager: AccessibilityManager
    @EnvironmentObject private var hapticFeedback: HapticFeedbackManager
    @EnvironmentObject private var transitionManager: TransitionManager
    
    var body: some View {
        NavigationView {
            List {
                Section("Navigation") {
                    LabeledContent("Selected Tab", value: navigationController.selectedTab.title)
                    LabeledContent("AR Active", value: navigationController.isARViewActive ? "Yes" : "No")
                    LabeledContent("Can Go Back", value: navigationController.canGoBack ? "Yes" : "No")
                }
                
                Section("Orientation") {
                    let debugInfo = orientationManager.getDebugInfo()
                    LabeledContent("Device", value: debugInfo.deviceOrientation.description)
                    LabeledContent("Interface", value: debugInfo.interfaceOrientation.description)
                    LabeledContent("Screen Size", value: "\(Int(debugInfo.screenSize.width))×\(Int(debugInfo.screenSize.height))")
                    LabeledContent("Available Size", value: "\(Int(debugInfo.availableSize.width))×\(Int(debugInfo.availableSize.height))")
                    LabeledContent("Horizontal Class", value: debugInfo.horizontalSizeClass.description)
                    LabeledContent("Vertical Class", value: debugInfo.verticalSizeClass.description)
                }
                
                Section("Accessibility") {
                    LabeledContent("VoiceOver", value: accessibilityManager.isVoiceOverEnabled ? "On" : "Off")
                    LabeledContent("Dynamic Type", value: accessibilityManager.isDynamicTypeEnabled ? "On" : "Off")
                    LabeledContent("Reduce Motion", value: accessibilityManager.isReduceMotionEnabled ? "On" : "Off")
                    LabeledContent("Content Size", value: accessibilityManager.preferredContentSizeCategory.description)
                }
                
                Section("Haptics") {
                    LabeledContent("Enabled", value: hapticFeedback.isHapticsEnabled ? "Yes" : "No")
                    LabeledContent("Engine Ready", value: hapticFeedback.isEngineReady ? "Yes" : "No")
                    LabeledContent("Intensity", value: String(format: "%.1f", hapticFeedback.hapticIntensity))
                }
                
                Section("Transitions") {
                    LabeledContent("Current", value: transitionManager.currentTransition?.rawValue ?? "None")
                    LabeledContent("In Progress", value: transitionManager.isTransitioning ? "Yes" : "No")
                    LabeledContent("Progress", value: String(format: "%.1f%%", transitionManager.transitionProgress * 100))
                    LabeledContent("Duration", value: String(format: "%.2fs", transitionManager.animationDuration))
                }
            }
            .navigationTitle("Debug Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        navigationController.dismissSheet()
                    }
                }
            }
        }
    }
}

// MARK: - Integration Setup

private extension NavigationIntegrationDemo {
    func setupIntegration() {
        // Configure orientation for AR
        orientationManager.configureForAR()
        
        // Configure accessibility for AR experience
        accessibilityManager.configureForARExperience()
        
        // Setup haptic feedback
        hapticFeedback.setEnabled(true)
        hapticFeedback.setIntensity(0.8)
        
        // Configure transitions
        transitionManager.createCustomTransition(
            type: .enterAR,
            animation: .spring(response: 0.6, dampingFraction: 0.7),
            hapticFeedback: .impact(.heavy),
            allowsInterruption: false
        )
        
        logInfo("Navigation integration demo setup completed", category: .general)
    }
}

// MARK: - Extensions for Demo

extension MainNavigationController {
    var debugMode: Bool {
        // This would be a debug flag in production
        return true
    }
}

extension UIDeviceOrientation {
    var description: String {
        switch self {
        case .portrait: return "Portrait"
        case .portraitUpsideDown: return "Portrait Upside Down"
        case .landscapeLeft: return "Landscape Left"
        case .landscapeRight: return "Landscape Right"
        case .faceUp: return "Face Up"
        case .faceDown: return "Face Down"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }
}

extension UIInterfaceOrientation {
    var description: String {
        switch self {
        case .portrait: return "Portrait"
        case .portraitUpsideDown: return "Portrait Upside Down"
        case .landscapeLeft: return "Landscape Left"
        case .landscapeRight: return "Landscape Right"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }
}

extension UserInterfaceSizeClass {
    var description: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        @unknown default: return "Unknown"
        }
    }
}

extension ContentSizeCategory {
    var description: String {
        switch self {
        case .extraSmall: return "Extra Small"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        case .extraExtraLarge: return "Extra Extra Large"
        case .extraExtraExtraLarge: return "Extra Extra Extra Large"
        case .accessibilityMedium: return "Accessibility Medium"
        case .accessibilityLarge: return "Accessibility Large"
        case .accessibilityExtraLarge: return "Accessibility Extra Large"
        case .accessibilityExtraExtraLarge: return "Accessibility Extra Extra Large"
        case .accessibilityExtraExtraExtraLarge: return "Accessibility Extra Extra Extra Large"
        @unknown default: return "Unknown"
        }
    }
}