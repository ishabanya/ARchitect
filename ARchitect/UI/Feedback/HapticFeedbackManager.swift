import UIKit
import SwiftUI
import Combine
import CoreHaptics

// MARK: - Haptic Feedback Manager

@MainActor
public class HapticFeedbackManager: ObservableObject {
    
    // MARK: - Properties
    @Published public var isHapticsEnabled = true
    @Published public var hapticIntensity: Float = 1.0
    @Published public var isEngineReady = false
    
    // Core Haptics
    private var hapticEngine: CHHapticEngine?
    private var engineNeedsStart = true
    
    // Standard feedback generators
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    // Custom patterns
    private var customPatterns: [HapticPattern: CHHapticPattern] = [:]
    
    // Settings
    private let maxConcurrentHaptics = 3
    private var activeHaptics: Set<UUID> = []
    
    public static let shared = HapticFeedbackManager()
    
    private init() {
        setupHapticEngine()
        loadCustomPatterns()
        prepareGenerators()
        
        logDebug("Haptic feedback manager initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            logWarning("Device does not support haptics", category: .general)
            return
        }
        
        do {
            hapticEngine = try CHHapticEngine()
            
            // Handle engine stopped
            hapticEngine?.stoppedHandler = { [weak self] reason in
                Task { @MainActor in
                    self?.handleEngineStop(reason: reason)
                }
            }
            
            // Handle engine reset
            hapticEngine?.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.handleEngineReset()
                }
            }
            
            startEngine()
            
        } catch {
            logError("Failed to create haptic engine", category: .general, error: error)
        }
    }
    
    private func startEngine() {
        guard let engine = hapticEngine else { return }
        
        do {
            try engine.start()
            isEngineReady = true
            engineNeedsStart = false
            
            logDebug("Haptic engine started", category: .general)
        } catch {
            logError("Failed to start haptic engine", category: .general, error: error)
            isEngineReady = false
        }
    }
    
    private func prepareGenerators() {
        // Pre-prepare standard generators for better performance
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        selectionFeedback.prepare()
        notificationFeedback.prepare()
    }
    
    private func loadCustomPatterns() {
        // Load predefined haptic patterns
        customPatterns[.objectSelection] = createObjectSelectionPattern()
        customPatterns[.objectPlacement] = createObjectPlacementPattern()
        customPatterns[.objectManipulation] = createObjectManipulationPattern()
        customPatterns[.surfaceSnap] = createSurfaceSnapPattern()
        customPatterns[.collision] = createCollisionPattern()
        customPatterns[.roomScan] = createRoomScanPattern()
        customPatterns[.error] = createErrorPattern()
        customPatterns[.success] = createSuccessPattern()
    }
    
    // MARK: - Basic Haptic Feedback
    
    public func impact(_ style: ImpactStyle, intensity: Float? = nil) {
        guard isHapticsEnabled else { return }
        
        let actualIntensity = (intensity ?? hapticIntensity).clamped(to: 0...1)
        
        switch style {
        case .light:
            if #available(iOS 17.0, *) {
                impactLight.impactOccurred(intensity: actualIntensity)
            } else {
                impactLight.impactOccurred()
            }
            
        case .medium:
            if #available(iOS 17.0, *) {
                impactMedium.impactOccurred(intensity: actualIntensity)
            } else {
                impactMedium.impactOccurred()
            }
            
        case .heavy:
            if #available(iOS 17.0, *) {
                impactHeavy.impactOccurred(intensity: actualIntensity)
            } else {
                impactHeavy.impactOccurred()
            }
        }
        
        logDebug("Impact haptic triggered", category: .general, context: LogContext(customData: [
            "style": style.rawValue,
            "intensity": actualIntensity
        ]))
    }
    
    public func selectionChanged() {
        guard isHapticsEnabled else { return }
        
        selectionFeedback.selectionChanged()
        
        logDebug("Selection haptic triggered", category: .general)
    }
    
    public func notification(_ type: NotificationType) {
        guard isHapticsEnabled else { return }
        
        let feedbackType: UINotificationFeedbackGenerator.FeedbackType = switch type {
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
        
        notificationFeedback.notificationOccurred(feedbackType)
        
        logDebug("Notification haptic triggered", category: .general, context: LogContext(customData: [
            "type": type.rawValue
        ]))
    }
    
    // MARK: - Custom Haptic Patterns
    
    public func playPattern(_ pattern: HapticPattern, intensity: Float? = nil) {
        guard isHapticsEnabled,
              let hapticPattern = customPatterns[pattern],
              let engine = hapticEngine,
              isEngineReady else { return }
        
        do {
            let actualIntensity = intensity ?? hapticIntensity
            let player = try engine.makePlayer(with: hapticPattern)
            
            // Apply intensity scaling
            if actualIntensity != 1.0 {
                let dynamicParameter = CHHapticDynamicParameter(
                    parameterID: .hapticIntensityControl,
                    value: actualIntensity,
                    relativeTime: 0
                )
                try player.sendParameters([dynamicParameter], atTime: 0)
            }
            
            let hapticID = UUID()
            activeHaptics.insert(hapticID)
            
            try player.start(atTime: CHHapticTimeImmediate)
            
            // Clean up after completion
            DispatchQueue.main.asyncAfter(deadline: .now() + pattern.duration) {
                self.activeHaptics.remove(hapticID)
            }
            
            logDebug("Custom haptic pattern played", category: .general, context: LogContext(customData: [
                "pattern": pattern.rawValue,
                "intensity": actualIntensity
            ]))
            
        } catch {
            logError("Failed to play haptic pattern", category: .general, error: error)
        }
    }
    
    // MARK: - AR-Specific Haptics
    
    public func objectSelected() {
        playPattern(.objectSelection)
    }
    
    public func objectPlaced() {
        playPattern(.objectPlacement)
    }
    
    public func objectManipulating() {
        // Light continuous feedback during manipulation
        impact(.light, intensity: 0.3)
    }
    
    public func surfaceSnapped() {
        playPattern(.surfaceSnap)
    }
    
    public func collision() {
        playPattern(.collision)
    }
    
    public func roomScanProgress() {
        playPattern(.roomScan)
    }
    
    public func operationSuccess() {
        playPattern(.success)
    }
    
    public func operationError() {
        playPattern(.error)
    }
    
    // MARK: - Navigation Haptics
    
    public func tabSwitch() {
        selectionChanged()
    }
    
    public func buttonPress() {
        impact(.light)
    }
    
    public func menuOpen() {
        impact(.medium)
    }
    
    public func menuClose() {
        impact(.light)
    }
    
    public func backNavigation() {
        impact(.light, intensity: 0.8)
    }
    
    // MARK: - Gesture Haptics
    
    public func gestureStarted() {
        impact(.light, intensity: 0.5)
    }
    
    public func gestureEnded() {
        impact(.medium, intensity: 0.7)
    }
    
    public func gestureCancelled() {
        // Double tap pattern
        impact(.light)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.impact(.light)
        }
    }
    
    // MARK: - Complex Haptic Sequences
    
    public func playSequence(_ sequence: HapticSequence) {
        guard isHapticsEnabled else { return }
        
        Task {
            for (index, event) in sequence.events.enumerated() {
                if index > 0 {
                    try await Task.sleep(nanoseconds: UInt64(event.delay * 1_000_000_000))
                }
                
                switch event.type {
                case .impact(let style, let intensity):
                    impact(style, intensity: intensity)
                case .pattern(let pattern, let intensity):
                    playPattern(pattern, intensity: intensity)
                case .selection:
                    selectionChanged()
                case .notification(let type):
                    notification(type)
                }
            }
        }
    }
    
    // MARK: - Pattern Creation
    
    private func createObjectSelectionPattern() -> CHHapticPattern? {
        let events = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0.1
            )
        ]
        
        return try? CHHapticPattern(events: events, parameters: [])
    }
    
    private func createObjectPlacementPattern() -> CHHapticPattern? {
        let events = [
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0,
                duration: 0.2
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0.2
            )
        ]
        
        return try? CHHapticPattern(events: events, parameters: [])
    }
    
    private func createObjectManipulationPattern() -> CHHapticPattern? {
        let events = [
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ],
                relativeTime: 0,
                duration: 0.1
            )
        ]
        
        return try? CHHapticPattern(events: events, parameters: [])
    }
    
    private func createSurfaceSnapPattern() -> CHHapticPattern? {
        let events = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                ],
                relativeTime: 0
            )
        ]
        
        return try? CHHapticPattern(events: events, parameters: [])
    }
    
    private func createCollisionPattern() -> CHHapticPattern? {
        let events = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ],
                relativeTime: 0
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0.05
            )
        ]
        
        return try? CHHapticPattern(events: events, parameters: [])
    }
    
    private func createRoomScanPattern() -> CHHapticPattern? {
        let events = [
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
                ],
                relativeTime: 0,
                duration: 0.3
            )
        ]
        
        return try? CHHapticPattern(events: events, parameters: [])
    }
    
    private func createErrorPattern() -> CHHapticPattern? {
        let events = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ],
                relativeTime: 0
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0.1
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                ],
                relativeTime: 0.2
            )
        ]
        
        return try? CHHapticPattern(events: events, parameters: [])
    }
    
    private func createSuccessPattern() -> CHHapticPattern? {
        let events = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0.1
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                ],
                relativeTime: 0.2
            )
        ]
        
        return try? CHHapticPattern(events: events, parameters: [])
    }
    
    // MARK: - Engine Management
    
    private func handleEngineStop(reason: CHHapticEngine.StoppedReason) {
        isEngineReady = false
        engineNeedsStart = true
        
        switch reason {
        case .audioSessionInterrupt:
            logDebug("Haptic engine stopped: Audio session interrupt", category: .general)
        case .applicationSuspended:
            logDebug("Haptic engine stopped: Application suspended", category: .general)
        case .idleTimeout:
            logDebug("Haptic engine stopped: Idle timeout", category: .general)
        case .systemError:
            logError("Haptic engine stopped: System error", category: .general)
        case .notifyWhenFinished:
            logDebug("Haptic engine stopped: Notify when finished", category: .general)
        case .gameControllerDisconnect:
            logDebug("Haptic engine stopped: Game controller disconnect", category: .general)
        @unknown default:
            logWarning("Haptic engine stopped: Unknown reason", category: .general)
        }
    }
    
    private func handleEngineReset() {
        isEngineReady = false
        engineNeedsStart = true
        
        // Reload custom patterns
        loadCustomPatterns()
        
        // Restart engine
        startEngine()
        
        logDebug("Haptic engine reset and restarted", category: .general)
    }
    
    // MARK: - Configuration
    
    public func setEnabled(_ enabled: Bool) {
        isHapticsEnabled = enabled
        
        if !enabled {
            stopAllHaptics()
        }
        
        logDebug("Haptics enabled changed", category: .general, context: LogContext(customData: [
            "enabled": enabled
        ]))
    }
    
    public func setIntensity(_ intensity: Float) {
        hapticIntensity = intensity.clamped(to: 0...1)
        
        logDebug("Haptic intensity changed", category: .general, context: LogContext(customData: [
            "intensity": hapticIntensity
        ]))
    }
    
    private func stopAllHaptics() {
        hapticEngine?.stop()
        activeHaptics.removeAll()
        
        logDebug("All haptics stopped", category: .general)
    }
    
    // MARK: - Public API for Custom Patterns
    
    public func createCustomPattern(events: [CHHapticEvent]) -> CHHapticPattern? {
        return try? CHHapticPattern(events: events, parameters: [])
    }
    
    public func playCustomPattern(_ pattern: CHHapticPattern, intensity: Float? = nil) {
        guard isHapticsEnabled,
              let engine = hapticEngine,
              isEngineReady else { return }
        
        do {
            let player = try engine.makePlayer(with: pattern)
            
            if let intensity = intensity {
                let dynamicParameter = CHHapticDynamicParameter(
                    parameterID: .hapticIntensityControl,
                    value: intensity,
                    relativeTime: 0
                )
                try player.sendParameters([dynamicParameter], atTime: 0)
            }
            
            try player.start(atTime: CHHapticTimeImmediate)
            
        } catch {
            logError("Failed to play custom haptic pattern", category: .general, error: error)
        }
    }
}

// MARK: - Supporting Types

public enum ImpactStyle: String {
    case light = "light"
    case medium = "medium"
    case heavy = "heavy"
}

public enum NotificationType: String {
    case success = "success"
    case warning = "warning"
    case error = "error"
}

public enum HapticPattern: String, CaseIterable {
    case objectSelection = "object_selection"
    case objectPlacement = "object_placement"
    case objectManipulation = "object_manipulation"
    case surfaceSnap = "surface_snap"
    case collision = "collision"
    case roomScan = "room_scan"
    case error = "error"
    case success = "success"
    
    var duration: TimeInterval {
        switch self {
        case .objectSelection: return 0.2
        case .objectPlacement: return 0.4
        case .objectManipulation: return 0.1
        case .surfaceSnap: return 0.1
        case .collision: return 0.15
        case .roomScan: return 0.3
        case .error: return 0.3
        case .success: return 0.3
        }
    }
}

public struct HapticSequence {
    let events: [HapticEvent]
    
    public init(events: [HapticEvent]) {
        self.events = events
    }
}

public struct HapticEvent {
    let type: HapticEventType
    let delay: TimeInterval
    
    public init(type: HapticEventType, delay: TimeInterval = 0) {
        self.type = type
        self.delay = delay
    }
}

public enum HapticEventType {
    case impact(ImpactStyle, intensity: Float?)
    case pattern(HapticPattern, intensity: Float?)
    case selection
    case notification(NotificationType)
}

// MARK: - Extensions

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}