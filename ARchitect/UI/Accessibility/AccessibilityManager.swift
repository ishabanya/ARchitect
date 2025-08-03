import SwiftUI
import UIKit
import AVFoundation
import Combine

// MARK: - Accessibility Manager

@MainActor
public class AccessibilityManager: ObservableObject {
    
    // MARK: - Properties
    @Published public var isVoiceOverEnabled = false
    @Published public var isDynamicTypeEnabled = false
    @Published public var isReduceMotionEnabled = false
    @Published public var isReduceTransparencyEnabled = false
    @Published public var isButtonShapesEnabled = false
    @Published public var isOnOffLabelsEnabled = false
    @Published public var preferredContentSizeCategory: ContentSizeCategory = .medium
    
    // Voice control
    @Published public var isVoiceControlEnabled = false
    @Published public var currentVoiceCommand = ""
    
    // Audio feedback
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    
    // State tracking
    private var lastAnnouncementTime: Date = Date.distantPast
    private let minimumAnnouncementInterval: TimeInterval = 0.5
    
    private var cancellables = Set<AnyCancellable>()
    
    public static let shared = AccessibilityManager()
    
    private init() {
        setupObservers()
        updateAccessibilitySettings()
        
        logInfo("Accessibility manager initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // VoiceOver notifications
        NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateVoiceOverStatus()
            }
            .store(in: &cancellables)
        
        // Dynamic Type notifications
        NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification)
            .sink { [weak self] _ in
                self?.updateDynamicTypeSettings()
            }
            .store(in: &cancellables)
        
        // Reduce Motion notifications
        NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateReduceMotionStatus()
            }
            .store(in: &cancellables)
        
        // Other accessibility notifications
        NotificationCenter.default.publisher(for: UIAccessibility.reduceTransparencyStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateReduceTransparencyStatus()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIAccessibility.buttonShapesEnabledStatusDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateButtonShapesStatus()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIAccessibility.onOffSwitchLabelsDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateOnOffLabelsStatus()
            }
            .store(in: &cancellables)
    }
    
    private func updateAccessibilitySettings() {
        updateVoiceOverStatus()
        updateDynamicTypeSettings()
        updateReduceMotionStatus()
        updateReduceTransparencyStatus()
        updateButtonShapesStatus()
        updateOnOffLabelsStatus()
    }
    
    private func updateVoiceOverStatus() {
        isVoiceOverEnabled = UIAccessibility.isVoiceOverRunning
        
        if isVoiceOverEnabled {
            // Adjust speech rate for VoiceOver users
            speechRate = AVSpeechUtteranceDefaultSpeechRate * 0.8
        }
        
        logDebug("VoiceOver status updated", category: .general, context: LogContext(customData: [
            "enabled": isVoiceOverEnabled
        ]))
    }
    
    private func updateDynamicTypeSettings() {
        preferredContentSizeCategory = ContentSizeCategory(UIApplication.shared.preferredContentSizeCategory)
        isDynamicTypeEnabled = UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
        
        logDebug("Dynamic Type updated", category: .general, context: LogContext(customData: [
            "category": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "is_accessibility": isDynamicTypeEnabled
        ]))
    }
    
    private func updateReduceMotionStatus() {
        isReduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
    }
    
    private func updateReduceTransparencyStatus() {
        isReduceTransparencyEnabled = UIAccessibility.isReduceTransparencyEnabled
    }
    
    private func updateButtonShapesStatus() {
        isButtonShapesEnabled = UIAccessibility.buttonShapesEnabled
    }
    
    private func updateOnOffLabelsStatus() {
        isOnOffLabelsEnabled = UIAccessibility.isOnOffSwitchLabelsEnabled
    }
    
    // MARK: - Screen Reader Support
    
    public func announce(_ message: String, priority: AnnouncementPriority = .normal) {
        // Throttle announcements to prevent spam
        let now = Date()
        guard now.timeIntervalSince(lastAnnouncementTime) >= minimumAnnouncementInterval else {
            return
        }
        lastAnnouncementTime = now
        
        let notification: UIAccessibility.Notification = switch priority {
        case .low:
            .announcement
        case .normal:
            .announcement
        case .high:
            .screenChanged
        case .urgent:
            .screenChanged
        }
        
        UIAccessibility.post(notification: notification, argument: message)
        
        // Also use speech synthesizer for non-VoiceOver users if enabled
        if !isVoiceOverEnabled {
            speakMessage(message, priority: priority)
        }
        
        logDebug("Accessibility announcement", category: .general, context: LogContext(customData: [
            "message": message,
            "priority": priority.rawValue
        ]))
    }
    
    public func announceScreenChange(_ message: String) {
        UIAccessibility.post(notification: .screenChanged, argument: message)
        
        logDebug("Screen change announced", category: .general, context: LogContext(customData: [
            "message": message
        ]))
    }
    
    public func announceLayoutChange(_ message: String) {
        UIAccessibility.post(notification: .layoutChanged, argument: message)
        
        logDebug("Layout change announced", category: .general)
    }
    
    // MARK: - Speech Synthesis
    
    private func speakMessage(_ message: String, priority: AnnouncementPriority) {
        guard !isVoiceOverEnabled else { return } // Don't interfere with VoiceOver
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = speechRate
        utterance.volume = 0.8
        
        // Adjust properties based on priority
        switch priority {
        case .low:
            utterance.volume = 0.5
        case .normal:
            utterance.volume = 0.7
        case .high:
            utterance.volume = 0.9
            utterance.rate = speechRate * 0.9
        case .urgent:
            utterance.volume = 1.0
            utterance.rate = speechRate * 0.8
        }
        
        // Stop current speech for high priority messages
        if priority == .high || priority == .urgent {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        speechSynthesizer.speak(utterance)
    }
    
    public func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }
    
    // MARK: - AR-Specific Accessibility
    
    public func announceARAction(_ action: String, object: String? = nil) {
        let message = if let object = object {
            "\(action) \(object)"
        } else {
            action
        }
        
        announce(message, priority: .normal)
    }
    
    public func announceObjectSelection(_ objectName: String) {
        announce("Selected \(objectName). Double tap to manipulate, or use gestures to move, rotate, or scale.", priority: .high)
    }
    
    public func announceGestureStart(_ gesture: String, object: String) {
        announce("\(gesture) \(object)", priority: .normal)
    }
    
    public func announceGestureEnd(_ gesture: String, object: String) {
        announce("Finished \(gesture) \(object)", priority: .normal)
    }
    
    public func announceNavigationChange(_ from: String, to: String) {
        announce("Navigated from \(from) to \(to)", priority: .high)
    }
    
    // MARK: - Voice Commands (Future Enhancement)
    
    public func processVoiceCommand(_ command: String) {
        currentVoiceCommand = command.lowercased()
        
        // Basic voice command processing
        if command.contains("select") {
            announce("Voice selection mode activated")
        } else if command.contains("move") {
            announce("Voice move mode activated")
        } else if command.contains("rotate") {
            announce("Voice rotate mode activated")
        } else if command.contains("delete") {
            announce("Voice delete mode activated")
        } else {
            announce("Voice command not recognized")
        }
        
        logDebug("Voice command processed", category: .general, context: LogContext(customData: [
            "command": command
        ]))
    }
    
    // MARK: - Accessibility Helpers
    
    public func makeAccessible<T: View>(_ view: T, 
                                      label: String, 
                                      hint: String? = nil, 
                                      value: String? = nil,
                                      traits: AccessibilityTraits = []) -> some View {
        var accessibleView = view
            .accessibilityLabel(label)
            .accessibilityAddTraits(traits)
        
        if let hint = hint {
            accessibleView = accessibleView.accessibilityHint(hint)
        }
        
        if let value = value {
            accessibleView = accessibleView.accessibilityValue(value)
        }
        
        return accessibleView
    }
    
    public func makeButton<T: View>(_ view: T, 
                                  label: String, 
                                  hint: String? = nil,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            view
        }
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(.isButton)
    }
    
    public func makeToggle<T: View>(_ view: T,
                                   label: String,
                                   isOn: Bool,
                                   hint: String? = nil) -> some View {
        view
            .accessibilityLabel(label)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }
    
    // MARK: - Custom Actions
    
    public func addCustomActions(to view: some View, actions: [AccessibilityCustomAction]) -> some View {
        view.accessibilityAction(named: Text("Actions")) {
            // Show custom actions menu
        }
    }
    
    // MARK: - Focus Management
    
    public func moveFocusTo(_ element: AccessibilityFocusTarget) {
        switch element {
        case .firstElement:
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        case .specificElement(let view):
            UIAccessibility.post(notification: .layoutChanged, argument: view)
        case .announcement(let message):
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
    
    // MARK: - Configuration
    
    public func configureForARExperience() {
        // Provide specific guidance for AR usage
        if isVoiceOverEnabled {
            announce("AR mode activated. Use explore by touch to find furniture and controls. Double tap to select objects, then use standard gestures for manipulation.", priority: .high)
        }
        
        // Adjust UI for better accessibility
        if isDynamicTypeEnabled {
            // UI adjustments would be handled by the views
        }
        
        if isReduceMotionEnabled {
            // Disable animations - handled by views
        }
        
        logInfo("Configured for AR experience", category: .general, context: LogContext(customData: [
            "voice_over": isVoiceOverEnabled,
            "dynamic_type": isDynamicTypeEnabled,
            "reduce_motion": isReduceMotionEnabled
        ]))
    }
    
    // MARK: - Error Handling
    
    public func announceError(_ error: String) {
        announce("Error: \(error)", priority: .urgent)
        
        // Also provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
    
    public func announceSuccess(_ message: String) {
        announce("Success: \(message)", priority: .high)
        
        // Provide success haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }
}

// MARK: - Supporting Types

public enum AnnouncementPriority: String {
    case low = "low"
    case normal = "normal"
    case high = "high"
    case urgent = "urgent"
}

public enum AccessibilityFocusTarget {
    case firstElement
    case specificElement(UIView)
    case announcement(String)
}

public struct AccessibilityCustomAction {
    let name: String
    let action: () -> Void
    
    public init(name: String, action: @escaping () -> Void) {
        self.name = name
        self.action = action
    }
}

// MARK: - ContentSizeCategory Extension

extension ContentSizeCategory {
    init(_ uiContentSizeCategory: UIContentSizeCategory) {
        switch uiContentSizeCategory {
        case .extraSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .extraLarge: self = .extraLarge
        case .extraExtraLarge: self = .extraExtraLarge
        case .extraExtraExtraLarge: self = .extraExtraExtraLarge
        case .accessibilityMedium: self = .accessibilityMedium
        case .accessibilityLarge: self = .accessibilityLarge
        case .accessibilityExtraLarge: self = .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: self = .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: self = .accessibilityExtraExtraExtraLarge
        default: self = .medium
        }
    }
}

// MARK: - Accessibility Modifiers

public struct AccessibilityEnhancementModifier: ViewModifier {
    let accessibilityManager: AccessibilityManager
    let label: String
    let hint: String?
    let value: String?
    let traits: AccessibilityTraits
    
    public func body(content: Content) -> some View {
        var view = content
            .accessibilityLabel(label)
            .accessibilityAddTraits(traits)
        
        if let hint = hint {
            view = view.accessibilityHint(hint)
        }
        
        if let value = value {
            view = view.accessibilityValue(value)
        }
        
        return view
    }
}

public struct VoiceOverGuideModifier: ViewModifier {
    let accessibilityManager: AccessibilityManager
    let instructions: String
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                if accessibilityManager.isVoiceOverEnabled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        accessibilityManager.announce(instructions, priority: .normal)
                    }
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    public func accessibilityEnhanced(
        label: String,
        hint: String? = nil,
        value: String? = nil,
        traits: AccessibilityTraits = []
    ) -> some View {
        self.modifier(AccessibilityEnhancementModifier(
            accessibilityManager: AccessibilityManager.shared,
            label: label,
            hint: hint,
            value: value,
            traits: traits
        ))
    }
    
    public func voiceOverGuide(_ instructions: String) -> some View {
        self.modifier(VoiceOverGuideModifier(
            accessibilityManager: AccessibilityManager.shared,
            instructions: instructions
        ))
    }
    
    public func accessibilityCustomAction(name: String, action: @escaping () -> Void) -> some View {
        self.accessibilityAction(named: Text(name)) {
            action()
        }
    }
}