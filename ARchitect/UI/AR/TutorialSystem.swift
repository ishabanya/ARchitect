import SwiftUI
import Combine

// MARK: - Tutorial Manager

@MainActor
public class TutorialManager: ObservableObject {
    
    // MARK: - Properties
    @Published public var isShowingTutorial = false
    @Published public var currentStep: TutorialStep?
    @Published public var currentTutorial: Tutorial?
    @Published public var progress: Double = 0.0
    @Published public var canProceed = true
    @Published public var canGoBack = false
    
    // Tutorial state
    @Published public var isFirstLaunch = true
    @Published public var hasCompletedARTutorial = false
    @Published public var hasCompletedPlacementTutorial = false
    @Published public var tutorialMode: TutorialMode = .guided
    
    // Animation state
    @Published public var highlightFrame: CGRect = .zero
    @Published public var isHighlighting = false
    @Published public var overlayOpacity: Double = 0.7
    
    // User preferences
    @Published public var enableTutorials = true
    @Published public var showHints = true
    @Published public var autoAdvance = false
    
    // Internal state
    private var currentStepIndex = 0
    private var completedTutorials: Set<String> = []
    private var autoAdvanceTimer: Timer?
    
    private let hapticFeedback = HapticFeedbackManager.shared
    private let accessibilityManager = AccessibilityManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    public var shouldShowTutorial: Bool {
        return enableTutorials && isFirstLaunch && !hasCompletedARTutorial
    }
    
    public init() {
        loadUserPreferences()
        setupObservers()
        
        logDebug("Tutorial manager initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func loadUserPreferences() {
        // Load from UserDefaults
        isFirstLaunch = UserDefaults.standard.object(forKey: "tutorial_first_launch") == nil
        hasCompletedARTutorial = UserDefaults.standard.bool(forKey: "tutorial_ar_completed")
        hasCompletedPlacementTutorial = UserDefaults.standard.bool(forKey: "tutorial_placement_completed")
        enableTutorials = UserDefaults.standard.object(forKey: "tutorial_enabled") == nil ? true : UserDefaults.standard.bool(forKey: "tutorial_enabled")
        
        let completedList = UserDefaults.standard.stringArray(forKey: "tutorial_completed") ?? []
        completedTutorials = Set(completedList)
    }
    
    private func saveUserPreferences() {
        UserDefaults.standard.set(false, forKey: "tutorial_first_launch")
        UserDefaults.standard.set(hasCompletedARTutorial, forKey: "tutorial_ar_completed")
        UserDefaults.standard.set(hasCompletedPlacementTutorial, forKey: "tutorial_placement_completed")
        UserDefaults.standard.set(enableTutorials, forKey: "tutorial_enabled")
        UserDefaults.standard.set(Array(completedTutorials), forKey: "tutorial_completed")
    }
    
    private func setupObservers() {
        // Monitor tutorial progress
        $currentStep
            .sink { [weak self] step in
                self?.handleStepChange(step)
            }
            .store(in: &cancellables)
        
        // Auto-advance timer
        $autoAdvance
            .sink { [weak self] enabled in
                if enabled {
                    self?.startAutoAdvanceTimer()
                } else {
                    self?.stopAutoAdvanceTimer()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Tutorial Control
    
    public func startTutorial(_ tutorial: Tutorial = .arBasics) {
        guard enableTutorials else { return }
        
        currentTutorial = tutorial
        currentStepIndex = 0
        currentStep = tutorial.steps.first
        isShowingTutorial = true
        progress = 0.0
        canGoBack = false
        canProceed = true
        
        updateProgress()
        setupStepAnimation()
        
        hapticFeedback.impact(.medium)
        accessibilityManager.announce("Tutorial started: \(tutorial.title)", priority: .high)
        
        logInfo("Tutorial started", category: .general, context: LogContext(customData: [
            "tutorial_id": tutorial.id,
            "tutorial_title": tutorial.title
        ]))
    }
    
    public func nextStep() {
        guard let tutorial = currentTutorial,
              currentStepIndex < tutorial.steps.count - 1 else {
            completeTutorial()
            return
        }
        
        currentStepIndex += 1
        currentStep = tutorial.steps[currentStepIndex]
        
        updateProgress()
        setupStepAnimation()
        
        hapticFeedback.impact(.light)
        
        if let step = currentStep {
            accessibilityManager.announce(step.title, priority: .normal)
        }
        
        logDebug("Tutorial step advanced", category: .general, context: LogContext(customData: [
            "step_index": currentStepIndex,
            "step_title": currentStep?.title ?? "unknown"
        ]))
    }
    
    public func previousStep() {
        guard currentStepIndex > 0 else { return }
        
        currentStepIndex -= 1
        currentStep = currentTutorial?.steps[currentStepIndex]
        
        updateProgress()
        setupStepAnimation()
        
        hapticFeedback.impact(.light)
        
        if let step = currentStep {
            accessibilityManager.announce("Previous step: \(step.title)", priority: .normal)
        }
        
        logDebug("Tutorial step went back", category: .general, context: LogContext(customData: [
            "step_index": currentStepIndex
        ]))
    }
    
    public func skipTutorial() {
        guard isShowingTutorial else { return }
        
        endTutorial(completed: false)
        
        hapticFeedback.impact(.medium)
        accessibilityManager.announce("Tutorial skipped", priority: .normal)
        
        logDebug("Tutorial skipped", category: .general, context: LogContext(customData: [
            "tutorial_id": currentTutorial?.id ?? "unknown",
            "step_index": currentStepIndex
        ]))
    }
    
    public func completeTutorial() {
        guard let tutorial = currentTutorial else { return }
        
        // Mark tutorial as completed
        completedTutorials.insert(tutorial.id)
        
        // Update specific completion flags
        switch tutorial.id {
        case "ar_basics":
            hasCompletedARTutorial = true
        case "furniture_placement":
            hasCompletedPlacementTutorial = true
        default:
            break
        }
        
        endTutorial(completed: true)
        
        hapticFeedback.operationSuccess()
        accessibilityManager.announceSuccess("Tutorial completed")
        
        logInfo("Tutorial completed", category: .general, context: LogContext(customData: [
            "tutorial_id": tutorial.id,
            "tutorial_title": tutorial.title
        ]))
    }
    
    private func endTutorial(completed: Bool) {
        withAnimation(.easeInOut(duration: 0.5)) {
            isShowingTutorial = false
            isHighlighting = false
        }
        
        currentTutorial = nil
        currentStep = nil
        currentStepIndex = 0
        progress = 0.0
        highlightFrame = .zero
        
        stopAutoAdvanceTimer()
        saveUserPreferences()
        
        if completed {
            // Show completion feedback
            showCompletionFeedback()
        }
    }
    
    // MARK: - Step Management
    
    private func handleStepChange(_ step: TutorialStep?) {
        guard let step = step else { return }
        
        // Update navigation state
        canGoBack = currentStepIndex > 0
        canProceed = step.canProceed
        
        // Handle step-specific logic
        switch step.type {
        case .introduction:
            overlayOpacity = 0.7
            
        case .interaction:
            overlayOpacity = 0.5
            
        case .highlight:
            overlayOpacity = 0.8
            startHighlighting(step.targetFrame)
            
        case .gesture:
            overlayOpacity = 0.6
            
        case .completion:
            overlayOpacity = 0.4
        }
        
        // Start auto-advance if enabled
        if autoAdvance && step.canAutoAdvance {
            startAutoAdvanceTimer()
        }
    }
    
    private func updateProgress() {
        guard let tutorial = currentTutorial else { return }
        
        progress = Double(currentStepIndex + 1) / Double(tutorial.steps.count)
    }
    
    private func setupStepAnimation() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            // Animate step transition
        }
    }
    
    // MARK: - Highlighting
    
    private func startHighlighting(_ frame: CGRect) {
        highlightFrame = frame
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isHighlighting = true
        }
        
        // Pulse animation
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            // Pulsing effect would be handled in the view
        }
    }
    
    private func stopHighlighting() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isHighlighting = false
        }
        
        highlightFrame = .zero
    }
    
    // MARK: - Auto-advance
    
    private func startAutoAdvanceTimer() {
        stopAutoAdvanceTimer()
        
        guard let step = currentStep,
              step.canAutoAdvance else { return }
        
        autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: step.autoAdvanceDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.nextStep()
            }
        }
    }
    
    private func stopAutoAdvanceTimer() {
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
    }
    
    // MARK: - Feedback
    
    private func showCompletionFeedback() {
        // Show celebration animation or feedback
        logDebug("Showing tutorial completion feedback", category: .general)
    }
    
    // MARK: - Tutorial Recommendations
    
    public func recommendNextTutorial() -> Tutorial? {
        if !hasCompletedARTutorial {
            return .arBasics
        } else if !hasCompletedPlacementTutorial {
            return .furniturePlacement
        } else {
            return .advancedFeatures
        }
    }
    
    public func shouldShowHint(for feature: String) -> Bool {
        return showHints && enableTutorials && !completedTutorials.contains("\(feature)_hint")
    }
    
    public func markHintShown(for feature: String) {
        completedTutorials.insert("\(feature)_hint")
        saveUserPreferences()
    }
    
    // MARK: - Accessibility
    
    public func getStepAccessibilityDescription() -> String {
        guard let step = currentStep else { return "" }
        
        var description = step.title
        if !step.description.isEmpty {
            description += ". \(step.description)"
        }
        
        description += ". Step \(currentStepIndex + 1) of \(currentTutorial?.steps.count ?? 1)."
        
        if canProceed {
            description += " Tap to continue."
        }
        
        return description
    }
}

// MARK: - Tutorial Overlay View

public struct TutorialOverlay: View {
    @EnvironmentObject private var tutorialManager: TutorialManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Overlay background
            Rectangle()
                .fill(.black.opacity(tutorialManager.overlayOpacity))
                .ignoresSafeArea()
                .allowsHitTesting(true)
            
            // Highlight cutout
            if tutorialManager.isHighlighting {
                HighlightCutout(frame: tutorialManager.highlightFrame)
            }
            
            // Tutorial content
            if let step = tutorialManager.currentStep {
                TutorialStepView(step: step)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tutorialManager.isShowingTutorial)
    }
}

// MARK: - Highlight Cutout

private struct HighlightCutout: View {
    let frame: CGRect
    @EnvironmentObject private var tutorialManager: TutorialManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Rectangle()
            .fill(.black.opacity(tutorialManager.overlayOpacity))
            .mask(
                Rectangle()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .frame(width: frame.width + 16, height: frame.height + 16)
                            .position(x: frame.midX, y: frame.midY)
                            .blendMode(.destinationOut)
                    )
            )
            .overlay(
                // Highlight border
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white, lineWidth: 3)
                    .frame(width: frame.width + 16, height: frame.height + 16)
                    .position(x: frame.midX, y: frame.midY)
                    .scaleEffect(tutorialManager.isHighlighting && !reduceMotion ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: tutorialManager.isHighlighting)
            )
            .ignoresSafeArea()
    }
}

// MARK: - Tutorial Step View

private struct TutorialStepView: View {
    let step: TutorialStep
    @EnvironmentObject private var tutorialManager: TutorialManager
    
    var body: some View {
        VStack {
            Spacer()
            
            // Step content
            VStack(spacing: 20) {
                // Progress indicator
                if let tutorial = tutorialManager.currentTutorial {
                    TutorialProgressView(
                        current: tutorialManager.currentStepIndex + 1,
                        total: tutorial.steps.count,
                        progress: tutorialManager.progress
                    )
                }
                
                // Step content card
                StepContentCard(step: step)
                
                // Navigation controls
                TutorialNavigationControls()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tutorialManager.getStepAccessibilityDescription())
    }
}

// MARK: - Tutorial Progress View

private struct TutorialProgressView: View {
    let current: Int
    let total: Int
    let progress: Double
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .frame(height: 4)
            
            // Step counter
            Text("\(current) of \(total)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - Step Content Card

private struct StepContentCard: View {
    let step: TutorialStep
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Icon and title
            HStack(spacing: 12) {
                if !step.icon.isEmpty {
                    Image(systemName: step.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                        .background(.blue.opacity(0.2), in: Circle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if !step.subtitle.isEmpty {
                        Text(step.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Description
            if !step.description.isEmpty {
                Text(step.description)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Interactive elements
            if case .gesture(let gestureType) = step.interactionType {
                GestureInstructionView(gestureType: gestureType)
            }
            
            // Tips
            if !step.tips.isEmpty {
                TipsView(tips: step.tips)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Gesture Instruction View

private struct GestureInstructionView: View {
    let gestureType: GestureType
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: gestureType.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.orange)
            
            Text(gestureType.instruction)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Tips View

private struct TipsView: View {
    let tips: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.yellow)
                
                Text("Tips")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            ForEach(tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(.yellow)
                        .frame(width: 4, height: 4)
                        .padding(.top, 6)
                    
                    Text(tip)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Tutorial Navigation Controls

private struct TutorialNavigationControls: View {
    @EnvironmentObject private var tutorialManager: TutorialManager
    
    var body: some View {
        HStack(spacing: 16) {
            // Skip button
            Button("Skip") {
                tutorialManager.skipTutorial()
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white.opacity(0.7))
            
            Spacer()
            
            // Back button
            if tutorialManager.canGoBack {
                Button("Back") {
                    tutorialManager.previousStep()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.white.opacity(0.2), in: Capsule())
                .foregroundColor(.white)
            }
            
            // Next button
            Button(isLastStep ? "Finish" : "Next") {
                tutorialManager.nextStep()
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.blue, in: Capsule())
            .foregroundColor(.white)
            .disabled(!tutorialManager.canProceed)
            .opacity(tutorialManager.canProceed ? 1.0 : 0.6)
        }
    }
    
    private var isLastStep: Bool {
        guard let tutorial = tutorialManager.currentTutorial else { return false }
        return tutorialManager.currentStepIndex == tutorial.steps.count - 1
    }
}

// MARK: - Supporting Types

public struct Tutorial {
    public let id: String
    public let title: String
    public let description: String
    public let steps: [TutorialStep]
    
    public init(id: String, title: String, description: String, steps: [TutorialStep]) {
        self.id = id
        self.title = title
        self.description = description
        self.steps = steps
    }
    
    // Predefined tutorials
    public static let arBasics = Tutorial(
        id: "ar_basics",
        title: "AR Basics",
        description: "Learn the fundamentals of using AR to design your space",
        steps: [
            TutorialStep(
                type: .introduction,
                title: "Welcome to ARchitect",
                subtitle: "Design your space with augmented reality",
                description: "ARchitect lets you visualize furniture in your real space before you buy. Let's start with the basics!",
                icon: "hand.wave.fill",
                canProceed: true
            ),
            TutorialStep(
                type: .highlight,
                title: "Camera View",
                subtitle: "This is your AR camera",
                description: "Point your device at the room where you want to place furniture. Make sure you have good lighting and move slowly to help the app understand your space.",
                icon: "camera.fill",
                targetFrame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height * 0.7),
                canProceed: true
            ),
            TutorialStep(
                type: .interaction,
                title: "Room Scanning",
                subtitle: "Let's scan your room",
                description: "Slowly move your device around to scan the room. The app will detect floors, walls, and other surfaces where you can place furniture.",
                icon: "viewfinder.circle.fill",
                interactionType: .gesture(.pan),
                canProceed: true,
                tips: ["Move slowly and steadily", "Ensure good lighting", "Point at different surfaces"]
            ),
            TutorialStep(
                type: .completion,
                title: "Great Job!",
                subtitle: "You've learned the AR basics",
                description: "Now you're ready to start placing furniture in your space. Tap 'Finish' to continue exploring ARchitect.",
                icon: "checkmark.circle.fill",
                canProceed: true
            )
        ]
    )
    
    public static let furniturePlacement = Tutorial(
        id: "furniture_placement",
        title: "Furniture Placement",
        description: "Learn how to add and arrange furniture in your AR space",
        steps: [
            TutorialStep(
                type: .introduction,
                title: "Adding Furniture",
                subtitle: "Let's place your first piece",
                description: "You can add furniture by tapping the + button or using the picture-in-picture catalog.",
                icon: "plus.circle.fill",
                canProceed: true
            ),
            TutorialStep(
                type: .highlight,
                title: "Add Button",
                subtitle: "Tap here to add furniture",
                description: "This button opens the furniture catalog where you can browse and select items to place in your room.",
                icon: "plus.circle.fill",
                targetFrame: CGRect(x: UIScreen.main.bounds.width/2 - 40, y: UIScreen.main.bounds.height - 120, width: 80, height: 80),
                canProceed: true
            )
        ]
    )
    
    public static let advancedFeatures = Tutorial(
        id: "advanced_features",
        title: "Advanced Features",
        description: "Discover advanced tools and features",
        steps: [
            TutorialStep(
                type: .introduction,
                title: "Advanced Tools",
                subtitle: "Master the advanced features",
                description: "Learn about the tool palette, performance monitoring, and other advanced features.",
                icon: "wrench.and.screwdriver.fill",
                canProceed: true
            )
        ]
    )
}

public struct TutorialStep {
    public let type: TutorialStepType
    public let title: String
    public let subtitle: String
    public let description: String
    public let icon: String
    public let targetFrame: CGRect
    public let interactionType: InteractionType
    public let canProceed: Bool
    public let canAutoAdvance: Bool
    public let autoAdvanceDelay: TimeInterval
    public let tips: [String]
    
    public init(
        type: TutorialStepType,
        title: String,
        subtitle: String = "",
        description: String,
        icon: String = "",
        targetFrame: CGRect = .zero,
        interactionType: InteractionType = .none,
        canProceed: Bool = true,
        canAutoAdvance: Bool = false,
        autoAdvanceDelay: TimeInterval = 3.0,
        tips: [String] = []
    ) {
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.icon = icon
        self.targetFrame = targetFrame
        self.interactionType = interactionType
        self.canProceed = canProceed
        self.canAutoAdvance = canAutoAdvance
        self.autoAdvanceDelay = autoAdvanceDelay
        self.tips = tips
    }
}

public enum TutorialStepType {
    case introduction
    case highlight
    case interaction
    case gesture
    case completion
}

public enum InteractionType {
    case none
    case tap(CGPoint)
    case gesture(GestureType)
    case selection(String)
}

public enum GestureType {
    case tap
    case pan
    case pinch
    case rotate
    case longPress
    
    public var icon: String {
        switch self {
        case .tap: return "hand.tap.fill"
        case .pan: return "hand.drag.fill"
        case .pinch: return "hand.pinch.fill"
        case .rotate: return "rotate.3d"
        case .longPress: return "hand.point.up.left.fill"
        }
    }
    
    public var instruction: String {
        switch self {
        case .tap: return "Tap to select"
        case .pan: return "Drag to move"
        case .pinch: return "Pinch to scale"
        case .rotate: return "Rotate with two fingers"
        case .longPress: return "Hold to access options"
        }
    }
}

public enum TutorialMode {
    case guided    // Step-by-step with blocking overlays
    case hints     // Non-blocking hints and tips
    case disabled  // No tutorials
}

// MARK: - Tutorial Hint View

public struct TutorialHint: View {
    let message: String
    let icon: String
    let position: HintPosition
    @State private var isVisible = true
    
    public enum HintPosition {
        case top, bottom, leading, trailing
    }
    
    public init(message: String, icon: String = "lightbulb.fill", position: HintPosition = .top) {
        self.message = message
        self.icon = icon
        self.position = position
    }
    
    public var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.yellow)
                
                Text(message)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Button(action: { isVisible = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .transition(.scale.combined(with: .opacity))
        }
    }
}