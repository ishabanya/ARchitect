import Foundation
import SwiftUI
import ARKit

// MARK: - Onboarding Manager

@MainActor
public class OnboardingManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var currentStep: OnboardingStep = .welcome
    @Published public var isOnboardingComplete: Bool = false
    @Published public var showingOnboarding: Bool = false
    @Published public var tutorialProgress: Double = 0.0
    
    // MARK: - Onboarding Steps
    public enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case permissions
        case arIntroduction
        case firstPlacement
        case navigation
        case customization
        case sharing
        case completion
        
        public var title: String {
            switch self {
            case .welcome: return "Welcome to ARchitect"
            case .permissions: return "Camera Access"
            case .arIntroduction: return "AR Basics"
            case .firstPlacement: return "Place Your First Object"
            case .navigation: return "Navigate in AR"
            case .customization: return "Customize Objects"
            case .sharing: return "Share Your Creations"
            case .completion: return "You're All Set!"
            }
        }
        
        public var description: String {
            switch self {
            case .welcome: return "Your journey into augmented reality begins here"
            case .permissions: return "We need camera access to create AR experiences"
            case .arIntroduction: return "Learn how AR works in ARchitect"
            case .firstPlacement: return "Touch the screen to place your first 3D object"
            case .navigation: return "Move around to see your objects from different angles"
            case .customization: return "Make objects your own with colors and materials"
            case .sharing: return "Show off your AR creations to the world"
            case .completion: return "Ready to start creating amazing AR experiences"
            }
        }
        
        public var icon: String {
            switch self {
            case .welcome: return "hand.wave.fill"
            case .permissions: return "camera.fill"
            case .arIntroduction: return "arkit"
            case .firstPlacement: return "hand.tap.fill"
            case .navigation: return "move.3d"
            case .customization: return "paintbrush.fill"
            case .sharing: return "square.and.arrow.up.fill"
            case .completion: return "checkmark.circle.fill"
            }
        }
        
        public var isInteractive: Bool {
            switch self {
            case .welcome, .permissions, .completion: return false
            case .arIntroduction, .firstPlacement, .navigation, .customization, .sharing: return true
            }
        }
        
        public var hasAnimation: Bool {
            switch self {
            case .arIntroduction, .firstPlacement, .navigation, .customization: return true
            default: return false
            }
        }
    }
    
    // MARK: - Tutorial State
    public enum TutorialState {
        case notStarted
        case inProgress
        case completed
        case skipped
    }
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let soundManager = SoundEffectsManager()
    private var tutorialTimer: Timer?
    
    // Step completion tracking
    private var stepCompletionStatus: [OnboardingStep: TutorialState] = [:]
    private var interactionCounts: [String: Int] = [:]
    
    public init() {
        loadOnboardingState()
        checkIfShouldShowOnboarding()
        
        logInfo("Onboarding Manager initialized", category: .onboarding)
    }
    
    // MARK: - Setup
    
    private func loadOnboardingState() {
        isOnboardingComplete = userDefaults.bool(forKey: "onboarding_complete")
        
        if let stepRawValue = userDefaults.object(forKey: "current_onboarding_step") as? Int,
           let step = OnboardingStep(rawValue: stepRawValue) {
            currentStep = step
        }
        
        // Load step completion status
        for step in OnboardingStep.allCases {
            let key = "onboarding_step_\(step.rawValue)"
            let stateRawValue = userDefaults.integer(forKey: key)
            
            switch stateRawValue {
            case 1: stepCompletionStatus[step] = .completed
            case 2: stepCompletionStatus[step] = .skipped
            default: stepCompletionStatus[step] = .notStarted
            }
        }
    }
    
    private func saveOnboardingState() {
        userDefaults.set(isOnboardingComplete, forKey: "onboarding_complete")
        userDefaults.set(currentStep.rawValue, forKey: "current_onboarding_step")
        
        // Save step completion status
        for (step, state) in stepCompletionStatus {
            let key = "onboarding_step_\(step.rawValue)"
            let stateValue: Int = switch state {
            case .notStarted: 0
            case .inProgress: 0
            case .completed: 1
            case .skipped: 2
            }
            userDefaults.set(stateValue, forKey: key)
        }
    }
    
    private func checkIfShouldShowOnboarding() {
        if !isOnboardingComplete {
            // Delay showing onboarding to allow app to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showingOnboarding = true
            }
        }
    }
    
    // MARK: - Navigation
    
    public func startOnboarding() {
        currentStep = .welcome
        isOnboardingComplete = false
        showingOnboarding = true
        tutorialProgress = 0.0
        
        stepCompletionStatus[.welcome] = .inProgress
        
        soundManager.playSound(.chime, withHaptic: true)
        
        logInfo("Onboarding started", category: .onboarding)
    }
    
    public func nextStep() {
        guard let nextStepRawValue = currentStep.rawValue + 1,
              nextStepRawValue < OnboardingStep.allCases.count,
              let nextStep = OnboardingStep(rawValue: nextStepRawValue) else {
            completeOnboarding()
            return
        }
        
        // Mark current step as completed
        stepCompletionStatus[currentStep] = .completed
        
        // Move to next step
        currentStep = nextStep
        stepCompletionStatus[nextStep] = .inProgress
        
        // Update progress
        tutorialProgress = Double(nextStep.rawValue) / Double(OnboardingStep.allCases.count - 1)
        
        saveOnboardingState()
        soundManager.playSound(.tick, withHaptic: true)
        
        logInfo("Advanced to onboarding step", category: .onboarding, context: LogContext(customData: [
            "step": nextStep.title,
            "progress": tutorialProgress
        ]))
    }
    
    public func previousStep() {
        guard currentStep.rawValue > 0,
              let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        
        stepCompletionStatus[currentStep] = .notStarted
        currentStep = prevStep
        stepCompletionStatus[prevStep] = .inProgress
        
        tutorialProgress = Double(prevStep.rawValue) / Double(OnboardingStep.allCases.count - 1)
        
        saveOnboardingState()
        soundManager.playSound(.tick)
    }
    
    public func skipStep() {
        stepCompletionStatus[currentStep] = .skipped
        nextStep()
        
        logInfo("Skipped onboarding step", category: .onboarding, context: LogContext(customData: [
            "step": currentStep.title
        ]))
    }
    
    public func skipOnboarding() {
        for step in OnboardingStep.allCases {
            if stepCompletionStatus[step] != .completed {
                stepCompletionStatus[step] = .skipped
            }
        }
        
        completeOnboarding()
        
        logInfo("Onboarding skipped", category: .onboarding)
    }
    
    public func restartOnboarding() {
        stepCompletionStatus.removeAll()
        currentStep = .welcome
        isOnboardingComplete = false
        tutorialProgress = 0.0
        
        for step in OnboardingStep.allCases {
            stepCompletionStatus[step] = .notStarted
        }
        
        stepCompletionStatus[.welcome] = .inProgress
        
        saveOnboardingState()
        showingOnboarding = true
        
        logInfo("Onboarding restarted", category: .onboarding)
    }
    
    private func completeOnboarding() {
        stepCompletionStatus[currentStep] = .completed
        isOnboardingComplete = true
        showingOnboarding = false
        tutorialProgress = 1.0
        
        saveOnboardingState()
        soundManager.playSound(.achievement, withHaptic: true)
        
        // Track completion analytics
        let completedSteps = stepCompletionStatus.values.filter { $0 == .completed }.count
        let skippedSteps = stepCompletionStatus.values.filter { $0 == .skipped }.count
        
        logInfo("Onboarding completed", category: .onboarding, context: LogContext(customData: [
            "completed_steps": completedSteps,
            "skipped_steps": skippedSteps,
            "completion_rate": Double(completedSteps) / Double(OnboardingStep.allCases.count)
        ]))
        
        // Post completion notification
        NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
    }
    
    // MARK: - Step Interaction Tracking
    
    public func trackInteraction(_ interactionType: String) {
        let currentCount = interactionCounts[interactionType] ?? 0
        interactionCounts[interactionType] = currentCount + 1
        
        // Check if step requirements are met
        checkStepCompletion(for: currentStep, interaction: interactionType)
        
        logDebug("Interaction tracked", category: .onboarding, context: LogContext(customData: [
            "interaction": interactionType,
            "count": currentCount + 1,
            "step": currentStep.title
        ]))
    }
    
    private func checkStepCompletion(for step: OnboardingStep, interaction: String) {
        let isCompleted = switch step {
        case .arIntroduction:
            interaction == "ar_session_started"
        case .firstPlacement:
            interaction == "object_placed" && (interactionCounts["object_placed"] ?? 0) >= 1
        case .navigation:
            interaction == "camera_moved" && (interactionCounts["camera_moved"] ?? 0) >= 3
        case .customization:
            interaction == "object_customized" && (interactionCounts["object_customized"] ?? 0) >= 1
        case .sharing:
            interaction == "share_initiated"
        default:
            false
        }
        
        if isCompleted && stepCompletionStatus[step] == .inProgress {
            // Auto-advance after a brief delay to show completion
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.nextStep()
            }
        }
    }
    
    // MARK: - Tutorial Hints
    
    public func showHint(for step: OnboardingStep) -> String? {
        switch step {
        case .firstPlacement:
            return "Tap anywhere on the screen to place an object"
        case .navigation:
            return "Walk around or move your device to see the object from different angles"
        case .customization:
            return "Tap on the object and try changing its color or material"
        case .sharing:
            return "Use the share button to save or share your creation"
        default:
            return nil
        }
    }
    
    public func getStepInstructions(for step: OnboardingStep) -> [String] {
        switch step {
        case .welcome:
            return [
                "Welcome to ARchitect!",
                "We'll guide you through creating your first AR experience",
                "Let's get started!"
            ]
        case .permissions:
            return [
                "ARchitect needs camera access to work",
                "This allows us to see the real world and place virtual objects",
                "Tap 'Allow' when prompted"
            ]
        case .arIntroduction:
            return [
                "Point your camera at a flat surface",
                "ARchitect will scan the area and detect surfaces",
                "You'll see dots appear when a surface is found"
            ]
        case .firstPlacement:
            return [
                "Great! Now you can place objects",
                "Tap anywhere on the detected surface",
                "Watch as your first 3D object appears!"
            ]
        case .navigation:
            return [
                "Now try moving around your object",
                "Walk around it or tilt your device",
                "See how it stays in place in the real world"
            ]
        case .customization:
            return [
                "Let's customize your object",
                "Tap on it to select it",
                "Then use the tools to change colors and materials"
            ]
        case .sharing:
            return [
                "Ready to share your creation?",
                "Take a screenshot or record a video",
                "Share it with friends and family!"
            ]
        case .completion:
            return [
                "Congratulations! 🎉",
                "You've completed the ARchitect tutorial",
                "You're ready to create amazing AR experiences!"
            ]
        }
    }
    
    // MARK: - Analytics
    
    public func getOnboardingAnalytics() -> OnboardingAnalytics {
        let completedSteps = stepCompletionStatus.values.filter { $0 == .completed }.count
        let skippedSteps = stepCompletionStatus.values.filter { $0 == .skipped }.count
        let totalSteps = OnboardingStep.allCases.count
        
        return OnboardingAnalytics(
            isComplete: isOnboardingComplete,
            currentStep: currentStep,
            completedSteps: completedSteps,
            skippedSteps: skippedSteps,
            totalSteps: totalSteps,
            completionRate: Double(completedSteps) / Double(totalSteps),
            interactions: interactionCounts
        )
    }
    
    // MARK: - Public Interface
    
    public func shouldShowOnboarding() -> Bool {
        return !isOnboardingComplete
    }
    
    public func hasUserCompletedStep(_ step: OnboardingStep) -> Bool {
        return stepCompletionStatus[step] == .completed
    }
    
    public func resetOnboarding() {
        stepCompletionStatus.removeAll()
        interactionCounts.removeAll()
        currentStep = .welcome
        isOnboardingComplete = false
        tutorialProgress = 0.0
        
        userDefaults.removeObject(forKey: "onboarding_complete")
        userDefaults.removeObject(forKey: "current_onboarding_step")
        
        for step in OnboardingStep.allCases {
            userDefaults.removeObject(forKey: "onboarding_step_\(step.rawValue)")
        }
        
        logInfo("Onboarding reset", category: .onboarding)
    }
}

// MARK: - Supporting Data Structures

public struct OnboardingAnalytics {
    public let isComplete: Bool
    public let currentStep: OnboardingManager.OnboardingStep
    public let completedSteps: Int
    public let skippedSteps: Int
    public let totalSteps: Int
    public let completionRate: Double
    public let interactions: [String: Int]
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
    static let onboardingStepChanged = Notification.Name("onboardingStepChanged")
}