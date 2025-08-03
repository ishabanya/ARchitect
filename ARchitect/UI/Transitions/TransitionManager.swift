import SwiftUI
import Combine

// MARK: - Transition Manager

@MainActor
public class TransitionManager: ObservableObject {
    
    // MARK: - Properties
    @Published public var currentTransition: TransitionType?
    @Published public var transitionProgress: Double = 0.0
    @Published public var isTransitioning = false
    
    // Animation settings
    @Published public var animationDuration: Double = 0.35
    @Published public var useReducedMotion = false
    
    // Transition configuration
    private var transitionConfigurations: [TransitionType: TransitionConfiguration] = [:]
    
    // State tracking
    private var transitionStartTime: Date?
    private var pendingTransitions: [PendingTransition] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    public static let shared = TransitionManager()
    
    private init() {
        setupDefaultConfigurations()
        setupReduceMotionObserver()
        
        logDebug("Transition manager initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func setupDefaultConfigurations() {
        // Tab transitions
        transitionConfigurations[.tabSwitch] = TransitionConfiguration(
            animation: .easeInOut(duration: 0.3),
            hapticFeedback: .selectionChanged,
            soundEffect: nil,
            allowsInterruption: true
        )
        
        // Navigation transitions
        transitionConfigurations[.push] = TransitionConfiguration(
            animation: .easeInOut(duration: 0.35),
            hapticFeedback: .impact(.light),
            soundEffect: nil,
            allowsInterruption: false
        )
        
        transitionConfigurations[.pop] = TransitionConfiguration(
            animation: .easeInOut(duration: 0.3),
            hapticFeedback: .impact(.light),
            soundEffect: nil,
            allowsInterruption: false
        )
        
        // Modal transitions
        transitionConfigurations[.presentModal] = TransitionConfiguration(
            animation: .spring(response: 0.5, dampingFraction: 0.8),
            hapticFeedback: .impact(.medium),
            soundEffect: nil,
            allowsInterruption: false
        )
        
        transitionConfigurations[.dismissModal] = TransitionConfiguration(
            animation: .easeInOut(duration: 0.25),
            hapticFeedback: .impact(.light),
            soundEffect: nil,
            allowsInterruption: false
        )
        
        // AR transitions
        transitionConfigurations[.enterAR] = TransitionConfiguration(
            animation: .spring(response: 0.6, dampingFraction: 0.7),
            hapticFeedback: .impact(.heavy),
            soundEffect: .arEnter,
            allowsInterruption: false
        )
        
        transitionConfigurations[.exitAR] = TransitionConfiguration(
            animation: .easeInOut(duration: 0.4),
            hapticFeedback: .impact(.medium),
            soundEffect: .arExit,
            allowsInterruption: false
        )
        
        // Content transitions
        transitionConfigurations[.fadeIn] = TransitionConfiguration(
            animation: .easeIn(duration: 0.25),
            hapticFeedback: nil,
            soundEffect: nil,
            allowsInterruption: true
        )
        
        transitionConfigurations[.fadeOut] = TransitionConfiguration(
            animation: .easeOut(duration: 0.2),
            hapticFeedback: nil,
            soundEffect: nil,
            allowsInterruption: true
        )
        
        transitionConfigurations[.slideIn] = TransitionConfiguration(
            animation: .spring(response: 0.4, dampingFraction: 0.8),
            hapticFeedback: nil,
            soundEffect: nil,
            allowsInterruption: true
        )
        
        transitionConfigurations[.slideOut] = TransitionConfiguration(
            animation: .easeInOut(duration: 0.3),
            hapticFeedback: nil,
            soundEffect: nil,
            allowsInterruption: true
        )
        
        // Scale transitions
        transitionConfigurations[.scaleIn] = TransitionConfiguration(
            animation: .spring(response: 0.3, dampingFraction: 0.6),
            hapticFeedback: .impact(.light),
            soundEffect: nil,
            allowsInterruption: true
        )
        
        transitionConfigurations[.scaleOut] = TransitionConfiguration(
            animation: .easeInOut(duration: 0.2),
            hapticFeedback: nil,
            soundEffect: nil,
            allowsInterruption: true
        )
    }
    
    private func setupReduceMotionObserver() {
        NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateReduceMotionStatus()
            }
            .store(in: &cancellables)
        
        updateReduceMotionStatus()
    }
    
    private func updateReduceMotionStatus() {
        useReducedMotion = UIAccessibility.isReduceMotionEnabled
        
        if useReducedMotion {
            // Reduce animation durations and use simpler animations
            for (type, config) in transitionConfigurations {
                let reducedConfig = TransitionConfiguration(
                    animation: .linear(duration: config.animation.duration * 0.5),
                    hapticFeedback: config.hapticFeedback,
                    soundEffect: config.soundEffect,
                    allowsInterruption: config.allowsInterruption
                )
                transitionConfigurations[type] = reducedConfig
            }
        }
        
        logDebug("Reduce motion status updated", category: .general, context: LogContext(customData: [
            "reduce_motion": useReducedMotion
        ]))
    }
    
    // MARK: - Transition Execution
    
    public func performTransition(
        _ type: TransitionType,
        from fromView: AnyView? = nil,
        to toView: AnyView? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard !isTransitioning || canInterruptCurrentTransition() else {
            // Queue the transition
            let pending = PendingTransition(type: type, fromView: fromView, toView: toView, completion: completion)
            pendingTransitions.append(pending)
            return
        }
        
        executeTransition(type, from: fromView, to: toView, completion: completion)
    }
    
    private func executeTransition(
        _ type: TransitionType,
        from fromView: AnyView?,
        to toView: AnyView?,
        completion: (() -> Void)?
    ) {
        guard let config = transitionConfigurations[type] else {
            logWarning("No configuration found for transition type", category: .general, context: LogContext(customData: [
                "transition_type": type.rawValue
            ]))
            completion?()
            return
        }
        
        // Start transition
        startTransition(type)
        
        // Play haptic feedback
        if let haptic = config.hapticFeedback {
            playHapticFeedback(haptic)
        }
        
        // Play sound effect
        if let sound = config.soundEffect {
            playSoundEffect(sound)
        }
        
        // Execute animation
        withAnimation(config.animation) {
            transitionProgress = 1.0
        }
        
        // Complete transition after animation duration
        DispatchQueue.main.asyncAfter(deadline: .now() + config.animation.duration) {
            self.completeTransition(completion)
        }
        
        logDebug("Transition executed", category: .general, context: LogContext(customData: [
            "type": type.rawValue,
            "duration": config.animation.duration
        ]))
    }
    
    private func startTransition(_ type: TransitionType) {
        currentTransition = type
        isTransitioning = true
        transitionProgress = 0.0
        transitionStartTime = Date()
    }
    
    private func completeTransition(_ completion: (() -> Void)?) {
        let duration = Date().timeIntervalSince(transitionStartTime ?? Date())
        
        currentTransition = nil
        isTransitioning = false
        transitionProgress = 0.0
        transitionStartTime = nil
        
        completion?()
        
        // Process pending transitions
        processPendingTransitions()
        
        logDebug("Transition completed", category: .general, context: LogContext(customData: [
            "actual_duration": duration
        ]))
    }
    
    private func canInterruptCurrentTransition() -> Bool {
        guard let currentType = currentTransition,
              let config = transitionConfigurations[currentType] else {
            return true
        }
        
        return config.allowsInterruption
    }
    
    private func processPendingTransitions() {
        guard !pendingTransitions.isEmpty else { return }
        
        let nextTransition = pendingTransitions.removeFirst()
        executeTransition(
            nextTransition.type,
            from: nextTransition.fromView,
            to: nextTransition.toView,
            completion: nextTransition.completion
        )
    }
    
    // MARK: - Feedback
    
    private func playHapticFeedback(_ feedback: HapticFeedbackType) {
        let hapticManager = HapticFeedbackManager.shared
        
        switch feedback {
        case .impact(let style):
            hapticManager.impact(style)
        case .selectionChanged:
            hapticManager.selectionChanged()
        case .notification(let type):
            hapticManager.notification(type)
        case .pattern(let pattern):
            hapticManager.playPattern(pattern)
        }
    }
    
    private func playSoundEffect(_ sound: SoundEffect) {
        // Sound effect implementation would go here
        // For now, just log
        logDebug("Sound effect played", category: .general, context: LogContext(customData: [
            "sound": sound.rawValue
        ]))
    }
    
    // MARK: - Custom Transitions
    
    public func createCustomTransition(
        type: TransitionType,
        animation: Animation,
        hapticFeedback: HapticFeedbackType? = nil,
        soundEffect: SoundEffect? = nil,
        allowsInterruption: Bool = true
    ) {
        let config = TransitionConfiguration(
            animation: animation,
            hapticFeedback: hapticFeedback,
            soundEffect: soundEffect,
            allowsInterruption: allowsInterruption
        )
        
        transitionConfigurations[type] = config
        
        logDebug("Custom transition created", category: .general, context: LogContext(customData: [
            "type": type.rawValue
        ]))
    }
    
    // MARK: - Animation Helpers
    
    public func getAnimation(for type: TransitionType) -> Animation {
        return transitionConfigurations[type]?.animation ?? .default
    }
    
    public func getDuration(for type: TransitionType) -> Double {
        return transitionConfigurations[type]?.animation.duration ?? 0.35
    }
    
    // MARK: - State Management
    
    public func cancelCurrentTransition() {
        guard isTransitioning else { return }
        
        // Reset state
        currentTransition = nil
        isTransitioning = false
        transitionProgress = 0.0
        transitionStartTime = nil
        
        // Clear pending transitions
        pendingTransitions.removeAll()
        
        logDebug("Transition cancelled", category: .general)
    }
    
    public func pauseTransitions() {
        // Implementation for pausing transitions
        // This would be used in scenarios like app backgrounding
    }
    
    public func resumeTransitions() {
        // Implementation for resuming transitions
    }
}

// MARK: - Supporting Types

public enum TransitionType: String, CaseIterable {
    // Navigation
    case tabSwitch = "tab_switch"
    case push = "push"
    case pop = "pop"
    
    // Modal
    case presentModal = "present_modal"
    case dismissModal = "dismiss_modal"
    
    // AR specific
    case enterAR = "enter_ar"
    case exitAR = "exit_ar"
    
    // Content transitions
    case fadeIn = "fade_in"
    case fadeOut = "fade_out"
    case slideIn = "slide_in"
    case slideOut = "slide_out"
    case scaleIn = "scale_in"
    case scaleOut = "scale_out"
    
    // Custom
    case custom = "custom"
}

public struct TransitionConfiguration {
    let animation: Animation
    let hapticFeedback: HapticFeedbackType?
    let soundEffect: SoundEffect?
    let allowsInterruption: Bool
    
    public init(
        animation: Animation,
        hapticFeedback: HapticFeedbackType? = nil,
        soundEffect: SoundEffect? = nil,
        allowsInterruption: Bool = true
    ) {
        self.animation = animation
        self.hapticFeedback = hapticFeedback
        self.soundEffect = soundEffect
        self.allowsInterruption = allowsInterruption
    }
}

public enum HapticFeedbackType {
    case impact(ImpactStyle)
    case selectionChanged
    case notification(NotificationType)
    case pattern(HapticPattern)
}

public enum SoundEffect: String {
    case arEnter = "ar_enter"
    case arExit = "ar_exit"
    case buttonTap = "button_tap"
    case objectPlace = "object_place"
    case notification = "notification"
    case error = "error"
    case success = "success"
}

private struct PendingTransition {
    let type: TransitionType
    let fromView: AnyView?
    let toView: AnyView?
    let completion: (() -> Void)?
}

// MARK: - Animation Extensions

extension Animation {
    var duration: Double {
        // Extract duration from animation
        // This is a simplified implementation
        switch self {
        case .easeIn(let duration), .easeOut(let duration), .easeInOut(let duration), .linear(let duration):
            return duration
        case .spring(let response, _, _):
            return response * 2 // Approximate
        default:
            return 0.35 // Default
        }
    }
}

// MARK: - Transition Modifiers

public struct TransitionModifier: ViewModifier {
    let transitionType: TransitionType
    let isPresented: Bool
    
    @StateObject private var transitionManager = TransitionManager.shared
    
    public func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .scaleEffect(isPresented ? 1 : 0.95)
            .animation(
                transitionManager.getAnimation(for: transitionType),
                value: isPresented
            )
    }
}

public struct SlideTransitionModifier: ViewModifier {
    let edge: Edge
    let isPresented: Bool
    
    @StateObject private var transitionManager = TransitionManager.shared
    
    public func body(content: Content) -> some View {
        content
            .offset(
                x: isPresented ? 0 : offsetX,
                y: isPresented ? 0 : offsetY
            )
            .animation(
                transitionManager.getAnimation(for: .slideIn),
                value: isPresented
            )
    }
    
    private var offsetX: CGFloat {
        switch edge {
        case .leading: return -UIScreen.main.bounds.width
        case .trailing: return UIScreen.main.bounds.width
        default: return 0
        }
    }
    
    private var offsetY: CGFloat {
        switch edge {
        case .top: return -UIScreen.main.bounds.height
        case .bottom: return UIScreen.main.bounds.height
        default: return 0
        }
    }
}

public struct ScaleTransitionModifier: ViewModifier {
    let isPresented: Bool
    let scale: CGFloat
    
    @StateObject private var transitionManager = TransitionManager.shared
    
    public func body(content: Content) -> some View {
        content
            .scaleEffect(isPresented ? 1 : scale)
            .opacity(isPresented ? 1 : 0)
            .animation(
                transitionManager.getAnimation(for: .scaleIn),
                value: isPresented
            )
    }
}

// MARK: - View Extensions

extension View {
    public func transition(_ type: TransitionType, isPresented: Bool) -> some View {
        self.modifier(TransitionModifier(transitionType: type, isPresented: isPresented))
    }
    
    public func slideTransition(from edge: Edge, isPresented: Bool) -> some View {
        self.modifier(SlideTransitionModifier(edge: edge, isPresented: isPresented))
    }
    
    public func scaleTransition(scale: CGFloat = 0.8, isPresented: Bool) -> some View {
        self.modifier(ScaleTransitionModifier(isPresented: isPresented, scale: scale))
    }
    
    public func animatedTransition<T: Equatable>(
        _ type: TransitionType,
        value: T,
        completion: (() -> Void)? = nil
    ) -> some View {
        self.animation(TransitionManager.shared.getAnimation(for: type), value: value)
            .onChange(of: value) { _, _ in
                completion?()
            }
    }
}